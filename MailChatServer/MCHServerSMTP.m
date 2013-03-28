//
//  MCHServerSMTP.m
//  MailChat
//
//  Created by Gwynne Raskind on 12/24/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "MCHServerSMTP.h"
#import "GCDAsyncSocket.h"
#import "NSData+Base64.h"
#import "NSData+MCHUtilities.h"
#import "NSString+Base64.h"
#import "MAGenerator.h"
#import "Console.h"
#import "MCHServerCertificates.h"
#import "MCHServerMailbox.h"

@implementation MCHServerSMTP
{
	GCDAsyncSocket *_listener;
	NSMutableSet *_clients;
}

- (NSUInteger)numClients
{
	NSUInteger __block result = 0;
	
	[_listener performBlock:^ { result = _clients.count; }];
	return result;
}

- (instancetype)init
{
	if ((self = [super init]))
	{
		NSError *error = nil;
		
		_clients = [NSMutableSet set];
		_listener = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:NULL];
		MCHSMTPConsoleMessage(@"Initializing SMTP listener...\n");
		if (![_listener acceptOnPort:25 error:&error])
		{
			MCHSMTPConsoleMessage(@"Failed to listen on port 25: %@\n", error.localizedDescription);
			return nil;
		}
	}
	return self;
}

- (void)dealloc
{
	MCHSMTPConsoleMessage(@"Closing SMTP listener.\n");
	[_listener disconnect];
	[_clients makeObjectsPerformSelector:@selector(disconnect)]; // threadsafe because the listener's queue is dead at this point
}

enum : int {
	kSMTPStateWaitHello,
	kSMTPStateWaitMail,
	kSMTPStateWaitRcpt,
	kSMTPStateWaitData,
	kSMTPStateWaitMoreData,
	kSMTPStateWaitQuit,
};

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
	[_clients addObject:newSocket];
	newSocket.userData = @{
		@"state": @(kSMTPStateWaitHello),
		@"remote": [NSString stringWithFormat:@"%@:%hu", newSocket.connectedHost, newSocket.connectedPort],
	}.mutableCopy;
	MCHSMTPConsoleMessage(@"Accepted connection from %@\n", newSocket.userData[@"remote"]);
	[newSocket writeData:[@"250 MailChat Server ready\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
	[newSocket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:timeout tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
	MCHSMTPConsoleMessage(@"Read line: %@\n", [[data stringUsingEncoding:NSASCIIStringEncoding] substringToIndex:data.length - 2]);
	if ([self socket:sock doSMTPWithClientLine:data])
		[sock readDataToData:[GCDAsyncSocket CRLFData] withTimeout:timeout tag:0];
}

- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutReadWithTag:(long)tag elapsed:(NSTimeInterval)elapsed bytesDone:(NSUInteger)length
{
	[sock writeData:[@"421 Timeout exceeded, closing connection\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
	[sock disconnectAfterWriting];
	MCHSMTPConsoleMessage(@"Lost connection with %@ (timeout)\n", sock.userData[@"remote"]);
	return 10.0;
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
	if (err)
		MCHSMTPConsoleMessage(@"Lost connection with %@ due to: %@\n", sock.userData[@"remote"], err);
	[_clients removeObject:sock];
}

#define has_prefix(d, p) (strncmp(d.bytes, p, MIN(sizeof(p) - 1, d.length)) == 0)
#define bad_syntax() do {	\
	[sock writeData:[@"501 Syntax error in parameters or arguments\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];	\
} while (0)
#define bad_command(is_seq) do {	\
	[sock writeData:[is_seq ? @"503 Bad sequence of commands\r\n" : @"500 Syntax Error, command unrecognized\r\n"	\
					 dataUsingEncoding:NSASCIIStringEncoding]	\
		  withTimeout:timeout tag:0];	\
} while (0)

- (bool)socket:(GCDAsyncSocket *)sock doSMTPWithClientLine:(NSData *)line
{
	NSMutableDictionary *vars = sock.userData;
	
	if (has_prefix(line, "QUIT")) {
		if (line.length != sizeof("QUIT\r\n") - 1)
			bad_syntax();
		else {
			MCHSMTPConsoleMessage(@"Client %@ leaving\n", vars[@"remote"]);
			[sock writeData:[@"221 TTFN\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
			[sock disconnectAfterWriting];
		}
		return true;
	}
	switch (((NSNumber *)vars[@"state"]).intValue)
	{
		case kSMTPStateWaitHello:
			if (has_prefix(line, "EHLO ")) {
				vars[@"senderDomain"] = [[line stringUsingEncoding:NSASCIIStringEncoding] substringWithRange:(NSRange){ 5, line.length - 7 }];
				[sock writeData:[@"250-MailChat greets you\r\n250-8BITMIME\r\n250-PIPELINING\r\n250 STARTTLS\r\n"
									dataUsingEncoding:NSASCIIStringEncoding]
					  withTimeout:timeout tag:0];
				vars[@"state"] = @(kSMTPStateWaitMail);
				MCHSMTPConsoleMessage(@"Client %@ said hello from %@\n", vars[@"remote"], vars[@"senderDomain"]);
			} else
				bad_command(false);
			break;
		case kSMTPStateWaitMail:
			if (has_prefix(line, "MAIL FROM:<")) {
				NSRange rangeOfEnd = [line rangeOfData:[@">" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:(NSRange){ 0, line.length }],
						addrRange = { sizeof("MAIL FROM:<") - 1, rangeOfEnd.location - (sizeof("MAIL FROM:<") - 1) };
				
				if (rangeOfEnd.location == NSNotFound)
					bad_syntax();
				else {
					vars[@"sender"] = [[line subdataWithRange:addrRange] stringUsingEncoding:NSASCIIStringEncoding];
					vars[@"recipients"] = @[].mutableCopy;
					MCHSMTPConsoleMessage(@"Client %@ wants to send mail from %@\n", vars[@"remote"], vars[@"sender"]);
					vars[@"state"] = @(kSMTPStateWaitRcpt);
					[sock writeData:[@"250 Sender accepted\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
				}
			} else if (has_prefix(line, "STARTTLS")) {
				if (line.length == sizeof("STARTTLS\r\n") - 1) {
					if (sock.isSecure) {
						bad_command(true);
					} else {
						MCHSMTPConsoleMessage(@"Client %@ requesting secure connection, starting TLS...\n", vars[@"remote"]);
						[sock writeData:[@"220 Starting TLS\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
						[sock startTLS:@{
							(__bridge NSString *)kCFStreamSSLValidatesCertificateChain: @NO,
							(__bridge NSString *)kCFStreamSSLIsServer: @YES,
							(__bridge NSString *)kCFStreamSSLCertificates: [MCHServerCertificates sharedCertificates].SSLCertificates,
						}];
						vars[@"state"] = @(kSMTPStateWaitHello);
						[sock writeData:[@"250 MailChat Server ready (secure)\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
					}
				} else
					bad_syntax();
			} else
				bad_command(false);
			break;
		case kSMTPStateWaitRcpt:
		case kSMTPStateWaitData:
			if (has_prefix(line, "RCPT TO:<")) {
				NSRange rangeOfEnd = [line rangeOfData:[@">" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:(NSRange){ 0, line.length }],
						addrRange = { sizeof("RCPT TO:<") - 1, rangeOfEnd.location - (sizeof("RCPT TO:<") - 1) };
				
				if (rangeOfEnd.location == NSNotFound)
					bad_syntax();
				else {
					[vars[@"recipients"] addObject:[[line subdataWithRange:addrRange] stringUsingEncoding:NSASCIIStringEncoding]];
					MCHSMTPConsoleMessage(@"Client %@ wants to send mail to %@\n", vars[@"remote"], [vars[@"recipients"] lastObject]);
					vars[@"state"] = @(kSMTPStateWaitData);
					[sock writeData:[@"250 Recipient accepted\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
				}
			} else if (has_prefix(line, "DATA")) {
				if (((NSNumber *)vars[@"state"]).intValue != kSMTPStateWaitData)
					bad_command(true);
				else if (line.length != sizeof("DATA\r\n") - 1)
					bad_syntax();
				else {
					vars[@"dataBuffer"] = [NSMutableData data];
					MCHSMTPConsoleMessage(@"Client %@ is ready to send data\n", vars[@"remote"]);
					vars[@"state"] = @(kSMTPStateWaitMoreData);
					[sock writeData:[@"354 Start input, end with <CRLF>.<CRLF>\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
				}
			} else
				bad_command(false);
			break;
		case kSMTPStateWaitMoreData:
			if (memcmp(line.bytes, ".\r\n", sizeof(".\r\n") - 1) == 0 && line.length == sizeof(".\r\n") - 1) {
				MCHSMTPConsoleMessage(@"Client %@ completed data sending\n", vars[@"remote"]);
				[[MCHServerMailbox sharedMailbox] depositRawMessageData:vars];
				vars[@"state"] = @(kSMTPStateWaitQuit);
				[sock writeData:[@"250 Message accepted for delivery.\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
			} else
				[vars[@"dataBuffer"] appendData:line];
			break;
		case kSMTPStateWaitQuit:
			bad_command(false);
			break;
	}
	return true;
}

- (void)dumpInfo
{
	MCHInfoConsoleMessage(@"SMTP servicing %lu clients\n", self.numClients);
}

@end
