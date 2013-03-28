//
//  ELWAsyncPOP3Socket.m
//  MailChat
//
//  Created by Gwynne Raskind on 12/16/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "ELWAsyncPOP3Socket.h"
#import "Base64.h"
#import "DRAtomicQueue.h"
#import <libkern/OSAtomic.h>
#import <CommonCrypto/CommonDigest.h>

typedef enum : uint16_t
{
	kELWPOP3Hello,
	kELWPOP3Quit,
	kELWPOP3Capabilities,
	kELWPOP3AuthUser,
	kELWPOP3AuthPass,
	kELWPOP3AuthMD5,
	kELWPOP3AuthGeneric,
	kELWPOP3StartTLS,
	kELWPOP3Status,
	kELWPOP3List,
	kELWPOP3UniqueID,
	kELWPOP3TopOrRetrieve,
	kELWPOP3Delete,
	kELWPOP3Reset,
} ELWPOP3CommandType;

enum : long
{
	kELWPOP3TagStatusRead = 1L, // tag for a read of the initial + or - of a response
	kELWPOP3TagResponseRead, // tag for a read of single-line remaining response data
	kELWPOP3TagMultilineRead, // tag for a read of multiline remaining response data
	kELWPOP3TagErrorRead, // tag for a read of an error response
};

typedef enum : uint32_t
{
	kELWPOP3StateDISCONNECT = 0, // This state is not part of the POP3 spec
	kELWPOP3StateAUTHORIZATION,
	kELWPOP3StateTRANSACTION,
	kELWPOP3StateUPDATE,
} ELWPOP3State;

@interface ELWPOP3Command : NSObject

@property(nonatomic,assign) ELWPOP3CommandType type;
@property(nonatomic,strong) NSString *commandLine;
@property(nonatomic,assign) bool hasMultilineResponse;
@property(nonatomic,assign) bool hasGoodStatus;
@property(nonatomic,strong) id response;

@end

@implementation ELWPOP3Command
@end

@implementation ELWAsyncPOP3Socket
{
	__weak id<ELWAsyncPOP3SocketDelegate> _pop3Delegate;

	ELWPOP3State _state;
	dispatch_queue_t _myDelegateQueue, _internalDelegateQueue;
	DRAtomicQueue *_commandQueue;

	NSArray *_cachedCapabilities;
	NSString *_cachedNonce;
	DRAtomicQueue *_cachedAuthMethods;
	DRAtomicQueue *_cachedAuthPasswords;
	NSDictionary *_savedTLSSettings;
	
	NSRegularExpression *_statMatcher, *_listMatcher, *_uidMatcher;
}

#pragma mark Initialization

- (instancetype)init
{
	return [self initWithDelegate:nil delegateQueue:NULL socketQueue:NULL];
}

- (instancetype)initWithDelegate:(id)aDelegate delegateQueue:(dispatch_queue_t)dq
{
	return [self initWithDelegate:aDelegate delegateQueue:dq socketQueue:NULL];
}

- (instancetype)initWithSocketQueue:(dispatch_queue_t)sq
{
	return [self initWithDelegate:nil delegateQueue:NULL socketQueue:sq];
}

- (instancetype)initWithDelegate:(id)aDelegate delegateQueue:(dispatch_queue_t)dq socketQueue:(dispatch_queue_t)sq
{
	return [self initWithPOP3Delegate:(id<ELWAsyncPOP3SocketDelegate>)aDelegate delegateQueue:dq socketQueue:sq];
}

- (instancetype)initWithPOP3Delegate:(id<ELWAsyncPOP3SocketDelegate>)aDelegate delegateQueue:(dispatch_queue_t)dq
{
	return [self initWithPOP3Delegate:aDelegate delegateQueue:dq socketQueue:NULL];
}

- (instancetype)initWithPOP3Delegate:(id<ELWAsyncPOP3SocketDelegate>)aDelegate delegateQueue:(dispatch_queue_t)dq socketQueue:(dispatch_queue_t)sq
{
	if ((self = [super initWithSocketQueue:sq]))
	{
		_internalDelegateQueue = dispatch_queue_create("com.elwea.AsyncPOP3Socket.delegate", DISPATCH_QUEUE_SERIAL);
		[self synchronouslySetDelegate:self delegateQueue:_internalDelegateQueue];
		_pop3Delegate = aDelegate;
		_myDelegateQueue = dq;
		_commandQueue = [[DRAtomicQueue alloc] init];
		_cachedAuthMethods = [[DRAtomicQueue alloc] init];
		_cachedAuthPasswords = [[DRAtomicQueue alloc] init];
	}
	return self;
}

#pragma mark Accessors

- (dispatch_queue_t)delegateQueue
{
	__block dispatch_queue_t result = NULL;
	
	[self performBlock:^ { result = _myDelegateQueue; }];
	return result;
}

- (void)setDelegateQueue:(dispatch_queue_t)delegateQueue
{
	// -performBlock: is synchronous; this should really be async on the socket queue, but we can't get at it in a subclass
	dispatch_async(_internalDelegateQueue, ^ { [self performBlock:^ { _myDelegateQueue = delegateQueue; }]; });
}

- (id<ELWAsyncPOP3SocketDelegate>)pop3Delegate
{
	__block id<ELWAsyncPOP3SocketDelegate> result = nil;
	
	[self performBlock:^ { result = _pop3Delegate; }];
	return result;
}

- (void)setPop3Delegate:(id<ELWAsyncPOP3SocketDelegate>)pop3Delegate
{
	dispatch_async(_internalDelegateQueue, ^ { [self performBlock:^ { _pop3Delegate = pop3Delegate; }]; });
}

- (void)setPOP3Delegate:(id<ELWAsyncPOP3SocketDelegate>)delegate delegateQueue:(dispatch_queue_t)delegateQueue
{
	dispatch_async(_internalDelegateQueue, ^ { [self performBlock:^ { _pop3Delegate = delegate; _myDelegateQueue = delegateQueue; }]; });
}

- (void)synchronouslySetPOP3Delegate:(id<ELWAsyncPOP3SocketDelegate>)pop3Delegate
{
	[self performBlock:^ { _pop3Delegate = pop3Delegate; }];
}

- (void)synchronouslySetPOP3Delegate:(id<ELWAsyncPOP3SocketDelegate>)pop3Delegate delegateQueue:(dispatch_queue_t)delegateQueue
{
	[self performBlock:^ { _pop3Delegate = pop3Delegate; _myDelegateQueue = delegateQueue; }];
}

- (void)synchronouslySetDelegateQueue:(dispatch_queue_t)delegateQueue
{
	[self performBlock:^ { _myDelegateQueue = delegateQueue; }];
}

- (dispatch_queue_t)internalQueue
{
	__block dispatch_queue_t result = NULL;
	
	[self performBlock:^ { result = _internalDelegateQueue; }];
	return result;
}

- (void)setInternalQueue:(dispatch_queue_t)internalQueue
{
	dispatch_async(_internalDelegateQueue, ^ { [self performBlock:^ { _internalDelegateQueue = internalQueue; }]; });
}

- (void)synchronouslySetInternalQueue:(dispatch_queue_t)internalQueue
{
	[self performBlock:^ { _internalDelegateQueue = internalQueue; }];
}

#pragma mark Utility

+ (NSData *)terminatorData
{
	return [@"\r\n.\r\n" dataUsingEncoding:NSASCIIStringEncoding];
}

- (void)callDelegateSelector:(SEL)cmd sync:(bool)synchronously withBlock:(void (^)(id<ELWAsyncPOP3SocketDelegate>))block
{
	id<ELWAsyncPOP3SocketDelegate> delegate = _pop3Delegate;
	
	if (_myDelegateQueue == _internalDelegateQueue && synchronously) {
		if ([delegate respondsToSelector:cmd])
			block(delegate);
	} else if (synchronously) {
		dispatch_sync(_myDelegateQueue, ^ { if ([delegate respondsToSelector:cmd]) block(delegate); });
	} else {
		dispatch_async(_myDelegateQueue, ^ { if ([delegate respondsToSelector:cmd]) block(delegate); });
	}
}

- (void)queueCommand:(ELWPOP3CommandType)type withString:(NSString *)str isMultiline:(bool)isMultiline
{
	ELWPOP3Command *command = [[ELWPOP3Command alloc] init];
	
	command.type = type;
	command.commandLine = str;
	command.hasMultilineResponse = isMultiline;
	[_commandQueue push:command];
	if (command.commandLine.length) // the hello command has no write
		[self writeData:[command.commandLine dataUsingEncoding:NSASCIIStringEncoding] withTimeout:_operationTimeout tag:0];
	// No need to issue a read; the delegate methods will always do that for us.
}

#pragma mark POP3 Commands

- (void)issueQuit
{
	[self queueCommand:kELWPOP3Quit withString:@"QUIT\r\n" isMultiline:false];
}

- (void)requestCapabilitiesWithRefresh:(bool)doRefresh
{
	if (!_cachedCapabilities || doRefresh)
		[self queueCommand:kELWPOP3Capabilities withString:@"CAPA\r\n" isMultiline:false];
	else {
		[self callDelegateSelector:@selector(pop3Socket:didReceiveCapabilityList:) sync:false withBlock:^(id<ELWAsyncPOP3SocketDelegate> delegate) {
			[delegate pop3Socket:self didReceiveCapabilityList:_cachedCapabilities];
		}];
	}
}

- (void)authWithUsername:(NSString *)username password:(NSString *)password
{
	[self authWithUsername:username password:password usingMD5:false];
}

- (void)authWithMethod:(NSString *)authMethod initialResponse:(NSData *)initialResponseOrNil
{
	[self queueCommand:kELWPOP3AuthGeneric
		  withString:[NSString stringWithFormat:@"AUTH %@ %@\r\n", authMethod,
						initialResponseOrNil ? initialResponseOrNil.base64EncodedString : @"="]
		  isMultiline:false];
}

- (void)authWithUsername:(NSString *)username password:(NSString *)password usingMD5:(bool)useAPOP
{
	if (useAPOP) { // If there's no nonce, we send a bad string to the server. Oh well. Client should've checked capabilities.
		uint8_t hash[CC_MD5_DIGEST_LENGTH] = {0};
		NSData *hashData = [NSData dataWithBytesNoCopy:hash length:CC_MD5_DIGEST_LENGTH freeWhenDone:NO],
			   *hashStr = [[_cachedNonce stringByAppendingString:password] dataUsingEncoding:NSASCIIStringEncoding];
		
		CC_MD5(hashStr.bytes, hashStr.length, hash);
		[_cachedAuthMethods push:@"APOP-MD5"];
		[self queueCommand:kELWPOP3AuthMD5
			  withString:[NSString stringWithFormat:@"APOP %@ %@\r\n", username, hashData.base64EncodedString]
			  isMultiline:false];
	} else {
		[_cachedAuthMethods push:@"INSECURE"];
		[_cachedAuthPasswords push:password];
		[self queueCommand:kELWPOP3AuthUser withString:[NSString stringWithFormat:@"USER %@\r\n", username] isMultiline:false];
	}
}

- (void)startTLS:(NSDictionary *)tlsSettings
{
	_state = kELWPOP3StateDISCONNECT;
	_savedTLSSettings = tlsSettings;
	[self queueCommand:kELWPOP3StartTLS withString:@"STLS\r\n" isMultiline:false];
}

- (void)requestStatus
{
	[self queueCommand:kELWPOP3Status withString:@"STAT\r\n" isMultiline:false];
}

- (void)requestMessageSize:(NSInteger)msgNum
{
	[self queueCommand:kELWPOP3List
		  withString:[NSString stringWithFormat:@"LIST%s%@\r\n", msgNum == -1 ? "" : " ", msgNum == -1 ? @"" : @(msgNum)]
		  isMultiline:msgNum == -1];
}

- (void)requestMessageIdentifier:(NSInteger)msgNum
{
	[self queueCommand:kELWPOP3UniqueID
		  withString:[NSString stringWithFormat:@"UIDL%s%@\r\n", msgNum == -1 ? "" : " ", msgNum == -1 ? @"" : @(msgNum)]
		  isMultiline:msgNum == -1];
}

- (void)requestMessage:(NSInteger)msgNum limitedToLines:(NSInteger)lineLimit
{
	[self queueCommand:kELWPOP3TopOrRetrieve
		  withString:[NSString stringWithFormat:@"%s %d%s%@\r\n", lineLimit == -1 ? "RETR" : "TOP", msgNum,
						lineLimit == -1 ? "" : " ", lineLimit == -1 ? @"" : @(lineLimit)]
		  isMultiline:true];
}

- (void)markMessageDeleted:(NSInteger)msgNum
{
	[self queueCommand:kELWPOP3Delete withString:[NSString stringWithFormat:@"DELE %d\r\n", msgNum] isMultiline:false];
}

- (void)resetMessageStatus
{
	[self queueCommand:kELWPOP3Reset withString:@"RSET\r\n" isMultiline:false];
}

#pragma mark Response Parsers

#define BAD_RESPONSE(...) do {	\
	[self callDelegateSelector:@selector(pop3Socket:didReceivePOP3Error:) sync:true	\
		  withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) {	\
		  	[delegate pop3Socket:self didReceivePOP3Error:[NSString stringWithFormat:__VA_ARGS__]];	\
		  }]; \
	[self disconnect];	\
	return; /* Don't re-queue the command or issue another read */	\
} while (0)

- (NSString *)fullSingleLineResponse:(NSData *)data
{
	return [[[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding]
			stringByReplacingOccurrencesOfString:@"\r\n" withString:@""]
			substringFromIndex:3];
}

- (NSData *)undoByteStuffingOfData:(NSData *)data
{
	// Right now, a multiline response with byte-stuffed terminators looks like this:
	//	OK blah\r\nasdf\r\n..asdf\r\nfdsa\r\n.\r\n
	// We need to turn it into this:
	//	blah\nasdf\n.asdf\nfdsa\n
	// And respect that the response may well have weird encoding that NSString can't arbitrarily handle
	// A more correct solution would do a full RFC822 decode on responses known to be messages and treat
	//	other multiline responses as pure ASCII (in either case, NSString could do this operation much
	//	more trivially, at least from the caller's perspective).
	if (data.length < 6)
		return data; // don't even try if the data's too short

	NSMutableData *result = [NSMutableData dataWithLength:data.length];
	const char *inPtr = data.bytes + 3, *endPtr = inPtr + (data.length - 6); // chop the leading OK and trailing .\r\n
	char *outPtr = result.mutableBytes;
	NSUInteger lengthAdjust = 6;
	
	while (inPtr < endPtr) {
		const char *foundPtr = memchr(inPtr, '\r', (uintptr_t)endPtr - (uintptr_t)inPtr);
		
		if (!foundPtr) {
			memcpy(outPtr, inPtr, endPtr - inPtr);
			break;
		}
		memcpy(outPtr, inPtr, foundPtr - inPtr);
		inPtr = foundPtr;
		if (memcmp(inPtr, "\r\n.", MIN(3UL, (uintptr_t)endPtr - (uintptr_t)inPtr)) == 0) {
			*outPtr++ = '\n';
			lengthAdjust += 2;
			inPtr += 3;
		} else if (memcmp(inPtr, "\r\n", MIN(2UL, (uintptr_t)endPtr - (uintptr_t)inPtr)) == 0) {
			*outPtr++ = '\n';
			++lengthAdjust;
			inPtr += 2;
		} else {
			*outPtr++ = '\r';
			++inPtr;
		}
	}
	[result setLength:result.length - lengthAdjust];
	return result;
}

- (void)parseHelloResponse:(ELWPOP3Command *)command
{
	NSRange r = [command.response rangeOfString:@"(<.+?@.+?>)$" options:NSRegularExpressionSearch];
	
	_cachedNonce = (r.location == NSNotFound ? nil : [command.response substringWithRange:r]);
	command.response = [command.response substringToIndex:r.location == NSNotFound ? [command.response length] : r.location];
	_state = kELWPOP3StateAUTHORIZATION;
	[self callDelegateSelector:@selector(pop3Socket:didSayHello:) sync:false
		  withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) { [delegate pop3Socket:self didSayHello:command.response]; }];
}

- (void)parseAuthResponse:(ELWPOP3Command *)command
{
	switch (command.type)
	{
		case kELWPOP3AuthUser: {
			[self queueCommand:kELWPOP3AuthPass withString:[_cachedAuthPasswords pop] isMultiline:false];
			break;
		}
		case kELWPOP3AuthGeneric: {
			NSData *response = [NSData dataWithBase64EncodedString:[[NSString alloc] initWithData:command.response encoding:NSASCIIStringEncoding]];
			id<ELWAsyncPOP3SocketDelegate> delegate = _pop3Delegate;
			__block NSData *reply = nil;

			if (_internalDelegateQueue == _myDelegateQueue) {
				if ([delegate respondsToSelector:@selector(pop3Socket:didReplyToAuthenticationRequest:)])
					reply = [delegate pop3Socket:self didReplyToAuthenticationRequest:response];
			} else {
				dispatch_sync(_myDelegateQueue, ^{
					if ([delegate respondsToSelector:@selector(pop3Socket:didReplyToAuthenticationRequest:)])
						reply = [delegate pop3Socket:self didReplyToAuthenticationRequest:response];
				});
			}
			if (reply) {
				[self queueCommand:kELWPOP3AuthGeneric withString:reply.base64EncodedString isMultiline:false];
				break;
			}
			// fall-through
		}
		case kELWPOP3AuthPass:
		case kELWPOP3AuthMD5: {
			_state = kELWPOP3StateTRANSACTION;
			[self callDelegateSelector:@selector(pop3Socket:didAuthenticateWithMethod:) sync:false
				  withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) {
				  	[delegate pop3Socket:self didAuthenticateWithMethod:[_cachedAuthMethods pop]];
				  }];
			break;
		}
		case kELWPOP3Hello: case kELWPOP3Quit: case kELWPOP3Capabilities: case kELWPOP3StartTLS: case kELWPOP3Status:
		case kELWPOP3List: case kELWPOP3UniqueID: case kELWPOP3TopOrRetrieve: case kELWPOP3Delete: case kELWPOP3Reset:
		default: {
			@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"not an auth command" userInfo:@{ @"command": command }];
		}
	}
}

- (void)parseStatusResponse:(ELWPOP3Command *)command
{
	if (!_statMatcher)
		_statMatcher = [NSRegularExpression regularExpressionWithPattern:@"^OK (\\d+) (\\d+)$" options:0 error:nil];
	NSTextCheckingResult *r = [_statMatcher firstMatchInString:command.response options:0 range:(NSRange){ 0, [command.response length] }];
	
	if (!r || [r rangeAtIndex:1].location == NSNotFound || [r rangeAtIndex:2].location == NSNotFound)
		BAD_RESPONSE(@"unknown stat response: %@", command.response);
	
	[self callDelegateSelector:@selector(pop3Socket:didReceiveMaildropCount:maildropSize:) sync:false
		  withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) {
			[delegate pop3Socket:self
					  didReceiveMaildropCount:[command.response substringWithRange:[r rangeAtIndex:1]].integerValue
					  maildropSize:[command.response substringWithRange:[r rangeAtIndex:2]].integerValue];
		  }];
}

- (void)parseListResponse:(ELWPOP3Command *)command
{
	if (!_listMatcher)
		_listMatcher = [NSRegularExpression regularExpressionWithPattern:@"^(OK )?(\\d+) (\\d+)$"
											options:NSRegularExpressionAnchorsMatchLines error:nil];
	
	NSString *response = command.hasMultilineResponse ? [[NSString alloc] initWithData:command.response encoding:NSASCIIStringEncoding] :
														command.response;
	NSArray *rs = response ? [_listMatcher matchesInString:response options:0 range:(NSRange){ 0, [response length] }] : nil;
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	
	if (!rs || rs.count < 1)
		BAD_RESPONSE(@"unknown list response: %@", command.response);
	for (NSTextCheckingResult *r in rs)
	{
		if (command.hasMultilineResponse) {
			if (r.numberOfRanges < 3 || [r rangeAtIndex:1].location == NSNotFound ||
				[r rangeAtIndex:2].location == NSNotFound || [r rangeAtIndex:3].location == NSNotFound)
				BAD_RESPONSE(@"unknown list response: %@", command.response);
		} else if (r.numberOfRanges < 3 || [r rangeAtIndex:1].location != NSNotFound || // notice condition invert on index 1
				   [r rangeAtIndex:2].location == NSNotFound || [r rangeAtIndex:3].location == NSNotFound)
				BAD_RESPONSE(@"unknown list response: %@", command.response);
		[d setObject:@([response substringWithRange:[r rangeAtIndex:3]].integerValue)
		   forKey:@([response substringWithRange:[r rangeAtIndex:2]].integerValue)];
	}
	[self callDelegateSelector:@selector(pop3Socket:didReceiveMessageInfoList:) sync:false
		  withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) { [delegate pop3Socket:self didReceiveMessageInfoList:d]; }];
}

- (void)parseUIDResponse:(ELWPOP3Command *)command
{
	if (!_uidMatcher)
		_uidMatcher = [NSRegularExpression regularExpressionWithPattern:@"^(OK )?(\\d+) (.+)$"
											options:NSRegularExpressionAnchorsMatchLines error:nil];
	
	NSString *response = command.hasMultilineResponse ? [[NSString alloc] initWithData:command.response encoding:NSASCIIStringEncoding] :
														command.response;
	NSArray *rs = response ? [_uidMatcher matchesInString:response options:0 range:(NSRange){ 0, [response length] }] : nil;
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	
	if (!rs || rs.count < 1)
		BAD_RESPONSE(@"unknown uidl response: %@", command.response);
	for (NSTextCheckingResult *r in rs)
	{
		if (command.hasMultilineResponse) {
			if (r.numberOfRanges < 3 || [r rangeAtIndex:1].location == NSNotFound ||
				[r rangeAtIndex:2].location == NSNotFound || [r rangeAtIndex:3].location == NSNotFound)
				BAD_RESPONSE(@"unknown uidl response: %@", command.response);
		} else if (r.numberOfRanges < 3 || [r rangeAtIndex:1].location != NSNotFound || // notice condition invert on index 1
				   [r rangeAtIndex:2].location == NSNotFound || [r rangeAtIndex:3].location == NSNotFound)
				BAD_RESPONSE(@"unknown uidl response: %@", command.response);
		[d setObject:[response substringWithRange:[r rangeAtIndex:3]] forKey:@([response substringWithRange:[r rangeAtIndex:2]].integerValue)];
	}
	[self callDelegateSelector:@selector(pop3Socket:didReceiveMessageInfoList:) sync:false
		  withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) { [delegate pop3Socket:self didReceiveMessageInfoList:d]; }];
}

- (void)dispatchCommand:(ELWPOP3Command *)command
{
	switch (command.type)
	{
		case kELWPOP3Hello:
			[self parseHelloResponse:command];
			[self requestCapabilitiesWithRefresh:true];
			break;
		case kELWPOP3Quit:
			_state = kELWPOP3StateUPDATE;
			break;
		case kELWPOP3Capabilities: {
			_cachedCapabilities = [command.response componentsSeparatedByString:@"\n"];
			_cachedCapabilities = [_cachedCapabilities subarrayWithRange:(NSRange){ 1, _cachedCapabilities.count }];
			[self callDelegateSelector:@selector(pop3Socket:didReceiveCapabilityList:) sync:false
				  withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) { [delegate pop3Socket:self didReceiveCapabilityList:_cachedCapabilities]; }];
			break;
		}
		case kELWPOP3AuthUser:
		case kELWPOP3AuthPass:
		case kELWPOP3AuthGeneric:
		case kELWPOP3AuthMD5:
			[self parseAuthResponse:command];
			break;
		case kELWPOP3StartTLS:
			_state = kELWPOP3StateDISCONNECT;
			[self startTLS:_savedTLSSettings];
			_savedTLSSettings = nil;
			break;
		case kELWPOP3Status:
			[self parseStatusResponse:command];
			break;
		case kELWPOP3List:
			[self parseListResponse:command];
			break;
		case kELWPOP3UniqueID:
			[self parseUIDResponse:command];
			break;
		case kELWPOP3TopOrRetrieve: {
			[self callDelegateSelector:@selector(pop3Socket:didReceiveMessage:withNumber:) sync:false
				  withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) {
				  	[delegate pop3Socket:self didReceiveMessage:command.response
				  			  withNumber:[command.commandLine substringFromIndex:5].integerValue];
				  }];
			break;
		}
		case kELWPOP3Delete: {
			[self callDelegateSelector:@selector(pop3Socket:didMarkMessage:deleted:) sync:false
				  withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) {
				  	[delegate pop3Socket:self didMarkMessage:[command.commandLine substringFromIndex:5].integerValue deleted:true];
				  }];
			break;
		}
		case kELWPOP3Reset: {
			[self callDelegateSelector:@selector(pop3Socket:didMarkMessage:deleted:) sync:false
				  withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) { [delegate pop3Socket:self didMarkMessage:-1 deleted:false]; }];
			break;
		}
		default:
			BAD_RESPONSE(@"unknown POP3 response: %@", command.response);
	}
	// Don't put anything here unless BAD_RESPONSE() is modified accordingly.
}

#pragma mark GCDAsyncSocket Delegate

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
	if (OSAtomicCompareAndSwap32(kELWPOP3StateDISCONNECT, kELWPOP3StateAUTHORIZATION, (int32_t *)&_state))
	{
		[self callDelegateSelector:_cmd sync:false withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) {
			[delegate socket:sock didConnectToHost:host port:port];
		}];
		[self queueCommand:kELWPOP3Hello withString:nil isMultiline:false];
		[self readDataToLength:1 withTimeout:_operationTimeout tag:kELWPOP3TagStatusRead];
	}
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
	[self callDelegateSelector:_cmd sync:false withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) {
		[delegate socket:sock didReadData:data withTag:tag];
	}];

	ELWPOP3Command *command = [_commandQueue pop];
			
	switch (tag)
	{
		case kELWPOP3TagStatusRead:
			if (data.length < 1)
				BAD_RESPONSE(@"no POP3 response where there should be");
			switch (*(char *)data.bytes)
			{
				case '+':
					command.hasGoodStatus = true;
					if (command.hasMultilineResponse)
						[self readDataToData:[self.class terminatorData] withTimeout:_operationTimeout tag:kELWPOP3TagMultilineRead];
					else
						[self readDataToData:[GCDAsyncSocket CRLFData] withTimeout:_operationTimeout tag:kELWPOP3TagResponseRead];
					break;
				case '-':
					[self readDataToData:[GCDAsyncSocket CRLFData] withTimeout:_operationTimeout tag:kELWPOP3TagErrorRead];
					break;
				default:
					BAD_RESPONSE(@"unknown POP3 response: %@", data);
			}
			[_commandQueue unPop:command];
			break;
		case kELWPOP3TagResponseRead:
			if (!command.hasGoodStatus || command.hasMultilineResponse) // yes, throwing an exception will blow up hard in a queue like this
				@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"command queue bad" userInfo:@{ @"command": command }];
			if (data.length < [GCDAsyncSocket CRLFData].length)
				BAD_RESPONSE(@"single-line response too short to hold terminator: %@", data);
			command.response = [self fullSingleLineResponse:data];
			[self dispatchCommand:command];
			[self readDataToLength:1 withTimeout:_operationTimeout tag:kELWPOP3TagStatusRead]; // start the next command's read, even if there isn't one
			break;
		case kELWPOP3TagMultilineRead:
			if (!command.hasGoodStatus || !command.hasMultilineResponse) // yes, throwing an exception will blow up hard in a queue like this
				@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"command queue bad" userInfo:@{ @"command": command }];
			if (data.length < [self.class terminatorData].length)
				BAD_RESPONSE(@"multiline response too short to hold terminator: %@", data);
			command.response = [self undoByteStuffingOfData:data];
			[self dispatchCommand:command];
			[self readDataToLength:1 withTimeout:_operationTimeout tag:kELWPOP3TagStatusRead]; // start the next read
			break;
		case kELWPOP3TagErrorRead:
			if (command.hasGoodStatus) // yes, throwing an exception will blow up hard in a queue like this
				@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"command queue bad" userInfo:@{ @"command": command }];
			if (data.length < [GCDAsyncSocket CRLFData].length)
				BAD_RESPONSE(@"error response too short to hold terminator: %@", data);
			command.response = data;
			[self dispatchCommand:command]; // dispatch must detect error status and update current state accordingly
			break;
		default:
			@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"unknown POP3 read tag" userInfo:@{ @"tag": @(tag) }];
	}
}

- (void)socket:(GCDAsyncSocket *)sock didReadPartialDataOfLength:(NSUInteger)partialLength tag:(long)tag
{
	[self callDelegateSelector:_cmd sync:false withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) {
		[delegate socket:sock didReadPartialDataOfLength:partialLength tag:tag];
	}];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
	[self callDelegateSelector:_cmd sync:false withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) {
		[delegate socket:sock didWriteDataWithTag:tag];
	}];
}

- (void)socket:(GCDAsyncSocket *)sock didWritePartialDataOfLength:(NSUInteger)partialLength tag:(long)tag
{
	[self callDelegateSelector:_cmd sync:false withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) {
		[delegate socket:sock didWritePartialDataOfLength:partialLength tag:tag];
	}];
}

- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutReadWithTag:(long)tag
                                                                 elapsed:(NSTimeInterval)elapsed
                                                               bytesDone:(NSUInteger)length
{
	id<ELWAsyncPOP3SocketDelegate> delegate = _pop3Delegate;
	
	if (_myDelegateQueue == _internalDelegateQueue && [delegate respondsToSelector:_cmd])
		return [delegate socket:sock shouldTimeoutReadWithTag:tag elapsed:elapsed bytesDone:length];
	
	__block NSTimeInterval result = 0.0;
	
	dispatch_sync(_myDelegateQueue, ^ {
		if ([delegate respondsToSelector:_cmd])
			result = [delegate socket:sock shouldTimeoutReadWithTag:tag elapsed:elapsed bytesDone:length];
	});
	return result;
}

- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutWriteWithTag:(long)tag
                                                                  elapsed:(NSTimeInterval)elapsed
                                                                bytesDone:(NSUInteger)length
{
	id<ELWAsyncPOP3SocketDelegate> delegate = _pop3Delegate;
	
	if (_myDelegateQueue == _internalDelegateQueue && [delegate respondsToSelector:_cmd])
		return [delegate socket:sock shouldTimeoutWriteWithTag:tag elapsed:elapsed bytesDone:length];
	
	__block NSTimeInterval result = 0.0;
	
	dispatch_sync(_myDelegateQueue, ^ {
		if ([delegate respondsToSelector:_cmd])
			result = [delegate socket:sock shouldTimeoutWriteWithTag:tag elapsed:elapsed bytesDone:length];
	});
	return result;
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
	_state = kELWPOP3StateDISCONNECT;
	[self callDelegateSelector:_cmd sync:false withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) {
		[delegate socketDidDisconnect:sock withError:err];
	}];
}

- (void)socketDidSecure:(GCDAsyncSocket *)sock
{
	// reissue the hello command after TLS success
	[self queueCommand:kELWPOP3Hello withString:@"" isMultiline:false];
	[self callDelegateSelector:_cmd sync:false withBlock:^ (id<ELWAsyncPOP3SocketDelegate> delegate) { [delegate socketDidSecure:sock]; }];
}

@end
