//
//  MCHJSONEmailMessageGateway.m
//  MailChat
//
//  Created by Gwynne Raskind on 12/14/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "MCHJSONEmailMessageGateway.h"
#import "MAGenerator.h"
#import "GCDAsyncSocket.h"
#import "ELWAsyncPOP3Socket.h"
#import <CommonCrypto/CommonDigest.h>
#import "Base64.h"
#import "NSData+MCHUtilities.h"
#import "NSString+MCHUtilities.h"
#import <libkern/OSAtomic.h>

@interface NSDictionary (JSONGatewayAdditions)
- (NSString *)byteStuffedRFC822Message;
- (instancetype)initWithByteStuffedRFC822Message:(NSData *)rfc822;
@end

@implementation NSDictionary (JSONGatewayAdditions)

- (instancetype)initWithByteStuffedRFC822Message:(NSData *)rfc822
{
	NSMutableData *data = rfc822.mutableCopy;
	NSData *byteStuff = [@"\r\n.." dataUsingEncoding:NSASCIIStringEncoding];
	NSRange lastRange = { NSNotFound, 0 };
	
	while ((lastRange = [data rangeOfData:byteStuff options:0 range:(NSRange){ 0, data.length }]).location != NSNotFound)
		[data replaceBytesInRange:lastRange withBytes:"\r\n." length:sizeof("\r\n.") - 1];
	[data replaceBytesInRange:[data rangeOfData:[@"\r\n.\r\n" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:(NSRange){ 0, data.length }]
		  withBytes:"\r\n" length:sizeof("\r\n") - 1];
	while ((lastRange = [data rangeOfData:[GCDAsyncSocket CRLFData] options:0 range:(NSRange){ 0, data.length }]).location != NSNotFound)
		[data replaceBytesInRange:lastRange withBytes:"\n" length:sizeof("\n") - 1];
	
	NSRange crlfRange = [data rangeOfData:[@"\n\n" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:(NSRange){ 0, data.length }];
	//NSString *headers = [[NSString alloc] initWithData:[data subdataWithRange:(NSRange){ 0, crlfRange.location }] encoding:NSASCIIStringEncoding];
	NSDictionary *messageInfo = [NSJSONSerialization JSONObjectWithData:
		[data subdataWithRange:(NSRange){ crlfRange.location + crlfRange.length, data.length - crlfRange.location - crlfRange.length }]
		options:0 error:nil];
	if (!messageInfo || ![messageInfo isKindOfClass:[NSDictionary class]])
		return nil;
	
	return [self initWithDictionary:@{
		@"sender": messageInfo[@"sender"],
		@"recipient": messageInfo[@"recipient"],
		@"uuid": [[NSUUID alloc] initWithUUIDString:messageInfo[@"uuid"]],
		@"timestamp": [NSDate dateWithTimeIntervalSinceReferenceDate:[messageInfo[@"timestamp"] doubleValue]],
		@"body": messageInfo[@"body"],
		@"rawData": rfc822,
	} copyItems:NO];
}

- (NSString *)byteStuffedRFC822Message
{
	NSDictionary *dict = @{
		@"sender": self[@"sender"],
		@"recipient": self[@"recipient"],
		@"timestamp": @([self[@"timestamp"] ?: [NSDate class] timeIntervalSinceReferenceDate]),
		@"uuid": [self[@"uuid"] UUIDString],
		@"body": self[@"body"],
	};
	NSDictionary *headers = @{
		@"Content-Type": @"application/json; charset=utf-8",
		@"Content-Transfer-Encoding": @"8bit",
		@"Subject": @"Generated Chat Message",
		@"From": dict[@"sender"],
		@"To": dict[@"recipient"],
		@"Date": ({ struct tm t = *localtime_r(&(time_t){ (long)[dict[@"timestamp"] doubleValue] }, &t); char datebuf[32] = {0};
					strftime(datebuf, 32, "%a, %d %b %Y %H %M %S %z", &t); [NSString stringWithUTF8String:datebuf]; }),
		@"Message-Id": [NSString stringWithFormat:@"<%@@mailchat>", dict[@"uuid"]],
		@"MIME-Version": @"1.0",
	};
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
	NSString *json = [[[[jsonData stringUsingEncoding:NSUTF8StringEncoding]
								  stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"]
								  stringByReplacingOccurrencesOfString:@"\r\n." withString:@"\r\n.."]
								  stringByAppendingString:@"\r\n.\r\n"];
	NSString * __block headersStr = @"";
	[headers enumerateKeysAndObjectsUsingBlock:^ (NSString *key, NSString *obj, BOOL *stop) {
		headersStr = [headersStr stringByAppendingFormat:@"%@: %@\r\n", key, obj];
	}];
	return [[headersStr stringByAppendingString:@"\r\n"] stringByAppendingString:json];
}
@end

@interface MCHJSONEmailMessageGateway () <GCDAsyncSocketDelegate>
@end

GENERATOR_DECL(bool, MCHPOP3StateMachineGenerator(GCDAsyncSocket *socket, NSTimeInterval timeout, NSDictionary *credentials, MCHMessageGateway *gateway),
			   (NSString *, NSData *, NSError **));
typedef bool (^MCHPOP3StateMachine)(NSString *, NSData *, NSError **);

GENERATOR_DECL(bool, MCHSMTPStateMachineGenerator(GCDAsyncSocket *socket, NSTimeInterval timeout, MCHMessageGateway *gateway),
			   (NSString *, NSData *, NSError **));
typedef bool (^MCHSMTPStateMachine)(NSString *, NSData *, NSError **);

@implementation MCHJSONEmailMessageGateway
{
	bool _timerRunning;	// because dispatch_suspend/resume() are badly designed
	bool _checkInProgress;
	dispatch_source_t _timer;
	dispatch_queue_t _queue, _sendQueue;
	dispatch_semaphore_t _readSignal, _writeSignal;
	NSError *_lastReadError, *_lastWriteError;
	MCHPOP3StateMachine _mboxProcessor;
	MCHSMTPStateMachine _sendProcessor;
	NSTimeInterval _checkInterval;
}

- (id)init
{
	if ((self = [super init]))
	{
		_timerRunning = false;
		_sendQueue = dispatch_queue_create([[NSBundle mainBundle].bundleIdentifier stringByAppendingString:@".outqueue"].UTF8String,
										   DISPATCH_QUEUE_SERIAL);
		_queue = dispatch_queue_create([[NSBundle mainBundle].bundleIdentifier stringByAppendingString:@".mailqueue"].UTF8String, DISPATCH_QUEUE_SERIAL);
		_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
		__weak MCHJSONEmailMessageGateway *ws = self; dispatch_source_set_event_handler(_timer, ^ {
			__strong MCHJSONEmailMessageGateway *ss = ws;
			NSError *result = [ss pullMessages];
			
			if (result)
				[(id<MCHMessageGatewayDelegate>)ss.delegate gateway:ss didFailWithError:result message:nil];
		});
		_mailHost = @"localhost";
		
		self.checkInterval = 5.0;	// we explicitly want the mutator's side effect
	}
	return self;
}

- (void)dealloc
{
	dispatch_source_cancel(_timer);
}

- (NSTimeInterval)checkInterval
{
	return _checkInterval;
}

- (void)setCheckInterval:(NSTimeInterval)checkInterval
{
	_checkInterval = checkInterval;
	dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, (uint64_t)_checkInterval * NSEC_PER_SEC, UINT64_MAX);
}

- (void)setActive:(bool)active
{
	[super setActive:active];
	if (active && !_timerRunning) {
		_timerRunning = true;
		dispatch_resume(_timer);
	} else if (!active && _timerRunning) {
		_timerRunning = false;
		dispatch_suspend(_timer);
	}
}

- (NSError *)pullMessages
{
	NSError *result = nil;
	
	if (OSAtomicTestAndSet(1, &_checkInProgress))
		return nil;
	
	GCDAsyncSocket *socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_queue];
	NSError *error = nil;
	
	_lastReadError = nil;
	_readSignal = dispatch_semaphore_create(0);
	if ([socket connectToHost:self.mailHost onPort:kPOP3DefaultPort withTimeout:_checkInterval * 0.67 error:&error])
		dispatch_semaphore_wait(_readSignal, DISPATCH_TIME_FOREVER);
	else
		_lastReadError = error;
	_readSignal = nil;
	result = _lastReadError;
	OSAtomicTestAndClear(1, &_checkInProgress); // This really doesn't need to be atomic, but it balances the call at the top nicely.
	
	return result;
}

#define CHECK_POP3_RESPONSE(r, m) do {	\
	if ([r characterAtIndex:0] == '-') {	\
		*_lastReadError = [NSError errorWithDomain:@"POP3Errors" code:0 userInfo:@{ @"issue": m, @"message": r }];	\
		GENERATOR_YIELD((bool)false);	\
	}	\
} while (0)

#define MALFORMED_POP3_RESPONSE(r, m) do {	\
	*_lastReadError = [NSError errorWithDomain:@"POP3Errors" code:1 userInfo:@{ @"issue": m, @"message": r }];	\
	GENERATOR_YIELD((bool)false);	\
} while (0)

GENERATOR(bool, MCHPOP3StateMachineGenerator(GCDAsyncSocket *socket, NSTimeInterval timeout,
											 NSDictionary *credentials, MCHMessageGateway *gateway),
		  (NSString *, NSData *, NSError **));
{
	NSInteger __block numMessages = 0, i = 0;
	
	GENERATOR_BEGIN(NSString *receivedResponse, NSData *rawData, NSError **_lastReadError)
	{
		// First response is the hello:
		CHECK_POP3_RESPONSE(receivedResponse, @"hello failure");
		[socket writeData:[@"STLS\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
		[socket readDataToLength:1 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// TLS response
		CHECK_POP3_RESPONSE(receivedResponse, @"TLS failure");
		[socket startTLS:@{ (__bridge NSString *)kCFStreamSSLValidatesCertificateChain: @NO }];
		[socket readDataToLength:1 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// TLS success, new hello:
		CHECK_POP3_RESPONSE(receivedResponse, @"second hello failure");
		{
			NSRange nonceRange = [receivedResponse rangeOfString:@"<.+?@.+?>$" options:NSRegularExpressionSearch];
			if (nonceRange.location == NSNotFound)
				MALFORMED_POP3_RESPONSE(receivedResponse, @"missing nonce");
			NSString *hashValue = [[receivedResponse substringWithRange:nonceRange] stringByAppendingString:credentials[@"password"]];
			NSString *command = [NSString stringWithFormat:@"APOP %@ %@\r\n", credentials[@"username"], hashValue.MD5Digest.hexadecimalRepresentation];
			[socket writeData:[command dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
			[socket readDataToLength:1 withTimeout:timeout tag:0];
		}
		GENERATOR_YIELD((bool)true);
		
		// Next is the auth reply:
		CHECK_POP3_RESPONSE(receivedResponse, @"auth failure");
		[socket writeData:[@"STAT\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
		[socket readDataToLength:1 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// Stat reply:
		CHECK_POP3_RESPONSE(receivedResponse, @"stat failure");
		NSRange countRange = [receivedResponse rangeOfString:@"^\\+OK \\d+ " options:NSRegularExpressionSearch]; // don't care about mbox size
		if (countRange.location == NSNotFound)
			MALFORMED_POP3_RESPONSE(receivedResponse, @"no maildrop count");
		numMessages = [receivedResponse substringWithRange:(NSRange){ countRange.location + 4, countRange.length - 5 }].integerValue;
		// since we don't care about the message sizes or server-side unique IDs, go straight into the RETR loop
		// make sure to use the loop counter from the block, or else the generator will fail
		for (i = 0; i < numMessages; ++i)
		{
			[socket writeData:[[NSString stringWithFormat:@"RETR %u\r\n", i + 1] dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
			[socket readDataToLength:1 withTimeout:timeout tag:2];
			GENERATOR_YIELD((bool)true);
			
			// RETR reply:
			CHECK_POP3_RESPONSE(receivedResponse, @"retrieve failure");
			bool validMessage = true;
			{
				NSDictionary *message = [[NSDictionary alloc] initWithByteStuffedRFC822Message:rawData];
				if (message) {
					id<MCHMessageGatewayDelegate> __strong delegate = gateway.delegate;
					
					[delegate gateway:gateway didReceiveIncomingMessage:message];
					[socket writeData:[[NSString stringWithFormat:@"DELE %u\r\n", i + 1] dataUsingEncoding:NSASCIIStringEncoding]
							withTimeout:timeout tag:0];
					[socket readDataToLength:1 withTimeout:timeout tag:0];
				} else
					validMessage = false;
			}
			if (!validMessage)
				MALFORMED_POP3_RESPONSE(receivedResponse, @"message parse failure");
			GENERATOR_YIELD((bool)true);
			
			// Delete reply:
			CHECK_POP3_RESPONSE(receivedResponse, @"delete failure");
		}
		[socket writeData:[@"QUIT\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
		[socket readDataToLength:1 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// Quit reply:
		CHECK_POP3_RESPONSE(receivedResponse, @"quit failure??");
		GENERATOR_YIELD((bool)false);
	}
	GENERATOR_END
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
	if (sock.userData) {
		_sendProcessor = MCHSMTPStateMachineGenerator(sock, _checkInterval * 0.67, self);
		[sock readDataToLength:4 withTimeout:_checkInterval * 0.67 tag:0];
	} else {
		_mboxProcessor = MCHPOP3StateMachineGenerator(sock, _checkInterval * 0.67, self.authCredentials, self);
		[sock readDataToLength:1 withTimeout:_checkInterval * 0.67 tag:0];
	}
}

- (void)socket:(GCDAsyncSocket *)sock didReadPOP3Data:(NSData *)data withTag:(long)tag
{
	switch (tag) {
		case 0: // read 1-char response, single-line expected
		case 1: // read 1-char response, multi-line expected
		case 2: // read 1-char response, RFC822 multi-line expected
			if (data.length && *(const char *)data.bytes == '+') {
				[sock readDataToData:tag ? [@"\r\n.\r\n" dataUsingEncoding:NSASCIIStringEncoding] : [GCDAsyncSocket CRLFData]
					  withTimeout:_checkInterval * 0.67 tag:tag + 3];
			} else
				[sock readDataToData:[GCDAsyncSocket CRLFData] withTimeout:_checkInterval * 0.67 tag:6];
			break;
		case 3: // read full response, single-line
		case 4: // read full response, multi-line
		case 6: // read full response, error
		{
			NSString *adata = [[NSString alloc] initWithBytesNoCopy:(void *)data.bytes
															 length:data.length encoding:NSASCIIStringEncoding freeWhenDone:NO];
			NSString *response = [(tag == 6 ? @"-" : @"+") stringByAppendingString:adata];
			NSError *error = nil;
			
			if (!_mboxProcessor(response, nil, &error))
				[sock disconnect];
			_lastReadError = error;
			break;
		}
		case 5: // read full response, RFC822 multi-line
		{
			NSRange crlfRange = [data rangeOfData:[GCDAsyncSocket CRLFData] options:0 range:(NSRange){ 0, data.length }];
			
			if (crlfRange.location == NSNotFound)
				[sock disconnect];
			NSString *responseLine = [@"+" stringByAppendingString:
					[[NSString alloc] initWithData:[data subdataWithRange:(NSRange){ 0, crlfRange.location + 1 }] encoding:NSASCIIStringEncoding]];
			NSError *error = nil;
			if (!_mboxProcessor(responseLine, [data subdataWithRange:(NSRange){ crlfRange.location + 2, data.length - crlfRange.location - 2 }], &error))
				[sock disconnect];
			if (!_lastReadError)
				_lastReadError = error;
			break;
		}
		default: // unknown tag, treat as fatal error
			[sock disconnect];
			break;
	}
}

#define CHECK_SMTP_RESPONSE(r, m, expectedCode) do {	\
	if ([r intValue] != expectedCode) {	\
		*_lastWriteError = [NSError errorWithDomain:@"SMTPErrors" code:0 userInfo:@{ @"issue": m, @"message": r }];	\
		GENERATOR_YIELD((bool)false);	\
	}	\
} while (0)

GENERATOR(bool, MCHSMTPStateMachineGenerator(GCDAsyncSocket *socket, NSTimeInterval timeout, MCHMessageGateway *gateway),
		  (NSString *, NSData *, NSError **));
{
	GENERATOR_BEGIN(NSString *receivedResponse, NSData *rawData, NSError **_lastWriteError)
	{
		// hello response
		CHECK_SMTP_RESPONSE(receivedResponse, @"hello failure", 250);
		[socket writeData:[@"EHLO localhost\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
		[socket readDataToLength:4 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// EHLO response
		CHECK_SMTP_RESPONSE(receivedResponse, @"ehlo failure", 250);
		[socket writeData:[@"STARTTLS\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
		[socket readDataToLength:4 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// TLS response
		CHECK_SMTP_RESPONSE(receivedResponse, @"tls failure", 220);
		[socket startTLS:@{ (__bridge NSString *)kCFStreamSSLValidatesCertificateChain: @NO }];
		[socket readDataToLength:4 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// new hello response
		CHECK_SMTP_RESPONSE(receivedResponse, @"second hello failure", 250);
		[socket writeData:[@"EHLO localhost\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
		[socket readDataToLength:4 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// EHLO response
		CHECK_SMTP_RESPONSE(receivedResponse, @"second ehlo failure", 250);
		[socket writeData:[[NSString stringWithFormat:@"MAIL FROM:<%@>\r\n", [socket.userData[@"message"][@"sender"] rfc822Address]]
							dataUsingEncoding:NSASCIIStringEncoding]
				withTimeout:timeout tag:0];
		[socket readDataToLength:4 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// MAIL FROM response
		CHECK_SMTP_RESPONSE(receivedResponse, @"mail failure", 250);
		[socket writeData:[[NSString stringWithFormat:@"RCPT TO:<%@>\r\n", [socket.userData[@"message"][@"recipient"] rfc822Address]]
							dataUsingEncoding:NSASCIIStringEncoding]
				withTimeout:timeout tag:0];
		[socket readDataToLength:4 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// RCPT TO response
		CHECK_SMTP_RESPONSE(receivedResponse, @"rcpt failure", 250);
		[socket writeData:[@"DATA\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
		[socket readDataToLength:4 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// DATA response
		CHECK_SMTP_RESPONSE(receivedResponse, @"data failure", 354);
		[socket writeData:[[NSString stringWithFormat:@"%@\r\n.\r\n", [socket.userData[@"message"] byteStuffedRFC822Message]]
							dataUsingEncoding:NSASCIIStringEncoding]
				withTimeout:timeout tag:0];
		[socket readDataToLength:4 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// Data response
		CHECK_SMTP_RESPONSE(receivedResponse, @"senddata failure", 250);
		[socket writeData:[@"QUIT\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
		[socket readDataToLength:4 withTimeout:timeout tag:0];
		GENERATOR_YIELD((bool)true);
		
		// QUIT response
		CHECK_SMTP_RESPONSE(receivedResponse, @"quit failure??", 221);
		GENERATOR_YIELD((bool)false);
	}
	GENERATOR_END
}

- (void)socket:(GCDAsyncSocket *)sock didReadSMTPData:(NSData *)data withTag:(long)tag
{
	NSMutableDictionary *vars = sock.userData;
	
	switch (tag) {
		case 0: // read 4-character response code, check for multiline continuation
		case 1: // read 4-character response code, part of multiline continuation
		{
			int nexttag = 2;
			
			if (data.length > 3 && *((const char *)data.bytes + 3) == '-')
				nexttag = 3;
			if (tag == 0)
				vars[@"responseBuffer"] = data.mutableCopy;
			else
				[vars[@"responseBuffer"] appendData:data];
			[sock readDataToData:[GCDAsyncSocket CRLFData] withTimeout:_checkInterval * 0.67 tag:nexttag];
			break;
		}
		case 2: // read full response, no continuation
		case 3: // read full response, has continuation
		{
			NSError *error = nil;
			
			[vars[@"responseBuffer"] appendData:data];
			if (tag == 3)
				[sock readDataToLength:4 withTimeout:_checkInterval * 0.67 tag:1];
			else {
				if (!_sendProcessor([vars[@"responseBuffer"] stringUsingEncoding:NSASCIIStringEncoding], vars[@"responseBuffer"], &error))
					[sock disconnect];
				if (!_lastWriteError)
					_lastReadError = error;
			}
			break;
		}
		default: // unknown tag, treat as fatal error
			[sock disconnect];
			break;
	}
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
	if (sock.userData)
		[self socket:sock didReadSMTPData:data withTag:tag];
	else
		[self socket:sock didReadPOP3Data:data withTag:tag];
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
	if (sock.userData) {
		_sendProcessor = nil;
		if (!_lastWriteError)
			_lastWriteError = err;
		dispatch_semaphore_signal(_writeSignal);
	} else {
		_mboxProcessor = nil;
		if (!_lastReadError)
			_lastReadError = err;
		dispatch_semaphore_signal(_readSignal);
	}
}

- (void)sendMessage:(NSDictionary *)message
{
	__weak MCHJSONEmailMessageGateway *ws = self;
	dispatch_async(_sendQueue, ^ {
		__strong MCHJSONEmailMessageGateway *ss = ws;
		if (ss) {
			NSError *error = nil;
			GCDAsyncSocket *socket = [[GCDAsyncSocket alloc] initWithDelegate:ss delegateQueue:ss->_queue];
			id<MCHMessageGatewayDelegate> __strong delegate = ss.delegate;
			
			socket.userData = @{ @"message": message }.mutableCopy;
			ss->_lastWriteError = nil;
			ss->_writeSignal = dispatch_semaphore_create(0);
			if ([socket connectToHost:ss.mailHost onPort:25 error:&error])
				dispatch_semaphore_wait(ss->_writeSignal, DISPATCH_TIME_FOREVER);
			else
				ss->_lastWriteError = error;
			ss->_writeSignal = nil;
			if (ss->_lastWriteError)
				[delegate gateway:ss didFailWithError:ss->_lastWriteError message:message];
			else
				[delegate gateway:ss didSendOutgoingMessage:message];
		}
	});
}

@end
