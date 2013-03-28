//
//  MCHServerPOP3.m
//  MailChat
//
//  Created by Gwynne Raskind on 12/24/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "MCHServerPOP3.h"
#import "GCDAsyncSocket.h"
#import "Base64.h"
#import "NSData+MCHUtilities.h"
#import "NSString+MCHUtilities.h"
#import "MAGenerator.h"
#import "Console.h"
#import "MCHServerCertificates.h"
#import "MCHServerMailbox.h"
#import "MCHServerProtocolCommon.h"

@implementation MCHServerPOP3
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
		
		_clients = [NSMutableArray array];
		_listener = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:NULL];
		MCHPOP3ConsoleMessage(@"Initializing POP3 listener...\n");
		if (![_listener acceptOnPort:110 error:&error])
		{
			MCHPOP3ConsoleMessage(@"Failed to listen on port 110: %@\n", error.localizedDescription);
			return nil;
		}
	}
	return self;
}

- (void)dealloc
{
	MCHPOP3ConsoleMessage(@"Closing POP3 listener.\n");
	[_listener disconnect];
	[_clients makeObjectsPerformSelector:@selector(disconnect)]; // threadsafe because the listener's queue is dead at this point
}

- (void)dumpInfo
{
	MCHInfoConsoleMessage(@"POP3 servicing %lu clients\n", self.numClients);
}

enum : int {
	kPOP3StateAUTHORIZATION,
	kPOP3StateAUTHORIZATION_WaitPass,
	kPOP3StateTRANSACTION,
	kPOP3StateUPDATE,
};

- (void)makeNewNonceForSocket:(GCDAsyncSocket *)sock
{
	NSError *e = nil;
	NSFileHandle *h = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:@"/dev/random"] error:&e];
	NSData *nonceData = [h readDataOfLength:8];
	
	sock.userData[@"nonceData"] = nonceData;
	sock.userData[@"nonce"] = [NSString stringWithFormat:@"<%" PRIu32 ".%" PRIu32 "@localhost>",
		*(uint32_t *)nonceData.bytes, *(((uint32_t *)nonceData.bytes) + 1)
	];
}

- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
	[_clients addObject:newSocket];
	newSocket.userData = @{
		@"state": @(kPOP3StateAUTHORIZATION),
		@"remote": [NSString stringWithFormat:@"%@:%hu", newSocket.connectedHost, newSocket.connectedPort],
	}.mutableCopy;
	[self makeNewNonceForSocket:newSocket];
	MCHPOP3ConsoleMessage(@"Accepted connection from %@\n", newSocket.userData[@"remote"]);
	[newSocket writeData:[[NSString stringWithFormat:@"+OK MailChat Server ready %@\r\n", newSocket.userData[@"nonce"]]
									dataUsingEncoding:NSASCIIStringEncoding]
			   withTimeout:timeout tag:0];
	[newSocket readDataToData:[GCDAsyncSocket CRLFData] withTimeout:timeout tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
	MCHPOP3ConsoleMessage(@"Read line: %@ (%@)\n", [[data stringUsingEncoding:NSASCIIStringEncoding] substringToIndex:data.length - 2], data);
	if ([self socket:sock doPOP3WithClientLine:data])
		[sock readDataToData:[GCDAsyncSocket CRLFData] withTimeout:timeout tag:0];
}

- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutReadWithTag:(long)tag elapsed:(NSTimeInterval)elapsed bytesDone:(NSUInteger)length
{
	[sock writeData:[@"-ERR Timeout exceeded, closing connection\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
	[sock disconnectAfterWriting];
	MCHPOP3ConsoleMessage(@"Lost connection with %@ (timeout)\n", sock.userData[@"remote"]);
	return 10.0;
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
	if (err)
		MCHPOP3ConsoleMessage(@"Lost connection with %@ due to: %@\n", sock.userData[@"remote"], err);
	if (sock.userData[@"mailbox"])
		[[MCHServerMailbox sharedMailbox] updateAndReleaseMboxForUser:sock.userData[@"username"] deletingMessageNumbers:[NSIndexSet indexSet]];
	[_clients removeObject:sock];
}

#define bad_syntax() do {	\
	[sock writeData:[@"-ERR Syntax error in parameters or arguments\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];	\
} while (0)
#define bad_command(is_seq) do {	\
	[sock writeData:[(is_seq) ? @"-ERR Bad sequence of commands\r\n" : @"-ERR Syntax Error, command unrecognized\r\n"	\
					 dataUsingEncoding:NSASCIIStringEncoding]	\
		  withTimeout:timeout tag:0];	\
} while (0)

- (bool)socket:(GCDAsyncSocket *)sock doPOP3WithClientLine:(NSData *)line
{
	NSMutableDictionary *vars = sock.userData;
	NSArray *matches = nil;
	
	switch (((NSNumber *)vars[@"state"]).intValue)
	{
		case kPOP3StateAUTHORIZATION:
			if (match_command(@"USER .*", line)) {
				if ((matches = match_command(@"USER ([A-Za-z0-9._@+\\-!~%]+)", line))) {
					vars[@"username"] = matches[1];
					vars[@"state"] = @(kPOP3StateAUTHORIZATION_WaitPass);
					[sock writeData:[@"+OK Send password\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
					MCHPOP3ConsoleMessage(@"Client %@ offered username %@\n", vars[@"remote"], vars[@"username"]);
				} else
					bad_syntax();
			} else if (match_command(@"APOP .*", line)) {
				if ((matches = match_command(@"APOP ([A-Za-z0-9._@+\\-!~%]+) ([a-z0-9]{32})", line))) {
					vars[@"username"] = matches[1];
					if ([matches[2] isEqualToString:[[vars[@"nonce"] stringByAppendingString:@"tesseract"] MD5Digest].hexadecimalRepresentation]) {
						MCHPOP3ConsoleMessage(@"Client %@ successfully APOP authenticated as %@\n", vars[@"remote"], vars[@"username"]);
						{
							NSArray *mbox = [[MCHServerMailbox sharedMailbox] lockMboxForUser:vars[@"username"]];
							if (!mbox) {
								[sock writeData:[@"-ERR Maildrop locked\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
							} else {
								vars[@"mailbox"] = mbox;
								vars[@"deletions"] = [NSMutableIndexSet indexSet];
								vars[@"state"] = @(kPOP3StateTRANSACTION);
								[sock writeData:[@"+OK Maildrop ready\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
							}
						}
					} else
						[sock writeData:[@"-ERR Authorization failed\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
				} else
					bad_syntax();
			} else if (match_command(@"STLS.+", line)) {
				bad_syntax();
			} else if (match_command(@"STLS", line)) {
				MCHPOP3ConsoleMessage(@"Client %@ requesting secure connection, starting TLS...\n", vars[@"remote"]);
				[sock writeData:[@"+OK Starting TLS\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
				[sock startTLS:@{
					(__bridge NSString *)kCFStreamSSLValidatesCertificateChain: @NO,
					(__bridge NSString *)kCFStreamSSLIsServer: @YES,
					(__bridge NSString *)kCFStreamSSLCertificates: [MCHServerCertificates sharedCertificates].SSLCertificates,
				}];
				[self makeNewNonceForSocket:sock];
				[sock writeData:[[NSString stringWithFormat:@"+OK MailChat Server ready %@\r\n", sock.userData[@"nonce"]]
										   dataUsingEncoding:NSASCIIStringEncoding]
					  withTimeout:timeout tag:0];
			} else if (match_command(@"QUIT.+", line)) {
				bad_syntax();
			} else if (match_command(@ "QUIT", line)) {
				MCHPOP3ConsoleMessage(@"Client %@ leaving\n", vars[@"remote"]);
				[sock writeData:[@"+OK Goodbye\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
				[sock disconnectAfterWriting];
			} else
				bad_command(match_command(@"(PASS|STAT|LIST|UIDL|RETR|TOP|DELE|RSET) ", line) ? true : false);
			break;
		case kPOP3StateAUTHORIZATION_WaitPass:
			if (match_command(@"PASS .*", line)) {
				if ((matches = match_command(@"PASS (.+)", line))) {
					if ([matches[1] isEqualToString:@"tesseract"]) {
						MCHPOP3ConsoleMessage(@"Client %@ successfully USER/PASS authenticated as %@\n", vars[@"remote"], vars[@"username"]);
						vars[@"mailbox"] = [[MCHServerMailbox sharedMailbox] lockMboxForUser:vars[@"username"]];
						vars[@"deletions"] = [NSMutableIndexSet indexSet];
						vars[@"state"] = @(kPOP3StateTRANSACTION);
						[sock writeData:[@"+OK Maildrop ready\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
					} else
						[sock writeData:[@"-ERR Authorization failed\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
				} else
					bad_syntax();
			} else if (match_command(@"QUIT.+", line)) {
				bad_syntax();
			} else if (match_command(@ "QUIT", line)) {
				MCHPOP3ConsoleMessage(@"Client %@ leaving\n", vars[@"remote"]);
				[sock writeData:[@"+OK Goodbye\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
				[sock disconnectAfterWriting];
			} else
				bad_command(match_command(@"(USER|APOP|STLS|STAT|LIST|UIDL|RETR|TOP|DELE|RSET) .*", line) ? true : false);
			break;
		case kPOP3StateTRANSACTION:
			if (match_command(@"STAT.+", line)) {
				bad_syntax();
			} else if (match_command(@"STAT", line)) {
				MCHPOP3ConsoleMessage(@"Client %@ asked for status\n", vars[@"remote"]);
				[sock writeData:[[NSString stringWithFormat:@"+OK %lu %lu\r\n", [vars[@"mailbox"] count],
											[[vars[@"mailbox"] valueForKeyPath:@"@sum.size"] unsignedIntegerValue]] dataUsingEncoding:NSASCIIStringEncoding]
					  withTimeout:timeout tag:0];
			} else if (match_command(@"LIST.+", line)) {
				if ((matches = match_command(@"LIST (\\d+)", line))) {
					NSUInteger msgNum = (NSUInteger)[matches[1] integerValue];
					MCHPOP3ConsoleMessage(@"Client %@ asked for size of message %@\n", vars[@"remote"], matches[1]);
					if (msgNum && msgNum <= [vars[@"mailbox"] count]) {
						[sock writeData:[[NSString stringWithFormat:@"+OK %lu %lu\r\n", msgNum,
													[vars[@"mailbox"][msgNum - 1][@"size"] unsignedIntegerValue]]
								dataUsingEncoding:NSASCIIStringEncoding]
							  withTimeout:timeout tag:0];
					} else {
						[sock writeData:[@"-ERR No such message\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
					}
				} else
					bad_syntax();
			} else if (match_command(@"LIST", line)) {
				MCHPOP3ConsoleMessage(@"Client %@ asked for message list\n", vars[@"remote"]);
				[sock writeData:[@"+OK\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
				[(NSArray *)vars[@"mailbox"] enumerateObjectsUsingBlock:^ (NSDictionary *obj, NSUInteger idx, BOOL *stop) {
					[sock writeData:[[NSString stringWithFormat:@"%lu %lu\r\n", idx + 1, [obj[@"size"] unsignedIntegerValue]]
							dataUsingEncoding:NSASCIIStringEncoding]
						  withTimeout:timeout tag:0];
				}];
				[sock writeData:[@".\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
			} else if (match_command(@"UIDL.+", line)) {
				if ((matches = match_command(@"UIDL (\\d+)", line))) {
					NSUInteger msgNum = (NSUInteger)[matches[1] integerValue];
					MCHPOP3ConsoleMessage(@"Client %@ asked for unique ID of message %@\n", vars[@"remote"], matches[1]);
					if (msgNum && msgNum <= [vars[@"mailbox"] count]) {
						[sock writeData:[[NSString stringWithFormat:@"+OK %lu %@\r\n", msgNum, vars[@"mailbox"][msgNum - 1][@"uniqueID"]]
								dataUsingEncoding:NSASCIIStringEncoding]
							  withTimeout:timeout tag:0];
					} else {
						[sock writeData:[@"-ERR No such message\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
					}
				} else
					bad_syntax();
			} else if (match_command(@"UIDL", line)) {
				MCHPOP3ConsoleMessage(@"Client %@ asked for message ID list\n", vars[@"remote"]);
				[sock writeData:[@"+OK\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
				[(NSArray *)vars[@"mailbox"] enumerateObjectsUsingBlock:^ (NSDictionary *obj, NSUInteger idx, BOOL *stop) {
					[sock writeData:[[NSString stringWithFormat:@"%lu %@\r\n", idx + 1, obj[@"uniqueID"]] dataUsingEncoding:NSASCIIStringEncoding]
						  withTimeout:timeout tag:0];
				}];
				[sock writeData:[@".\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
			} else if (match_command(@"TOP .*", line)) {
				if ((matches = match_command(@"TOP (\\d+) (\\d+)", line))) {
					NSUInteger msgNum = (NSUInteger)[matches[1] integerValue], count = (NSUInteger)[matches[2] integerValue];
					MCHPOP3ConsoleMessage(@"Client %@ asked for top %lu lines of message %lu\n", vars[@"remote"], count, msgNum);
					if (msgNum && msgNum <= [vars[@"mailbox"] count]) {
						[sock writeData:[@"+OK\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
						NSArray *lines = [vars[@"mailbox"][msgNum - 1][@"body"] componentsSeparatedByString:@"\n"];
						NSString *preppedData = [NSString stringWithFormat:@"%@\r\n\r\n%@\r\n.\r\n",
							[[vars[@"mailbox"][msgNum - 1][@"headers"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"]
																	   stringByReplacingOccurrencesOfString:@"\r\n." withString:@"\r\n.."],
							[[[lines subarrayWithRange:(NSRange){ 0, MIN(count, lines.count) }] componentsJoinedByString:@"\r\n"]
								stringByReplacingOccurrencesOfString:@"\r\n." withString:@"\r\n.."]];
						[sock writeData:[preppedData dataUsingEncoding:NSUTF8StringEncoding] withTimeout:timeout tag:0];
					} else {
						[sock writeData:[@"-ERR No such message\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
					}
				} else
					bad_syntax();
			} else if (match_command(@"RETR .*", line)) {
				if ((matches = match_command(@"RETR (\\d+)", line))) {
					NSUInteger msgNum = (NSUInteger)[matches[1] integerValue];
					MCHPOP3ConsoleMessage(@"Client %@ asked for message %lu\n", vars[@"remote"], msgNum);
					if (msgNum && msgNum <= [vars[@"mailbox"] count]) {
						[sock writeData:[@"+OK\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
						NSString *preppedData = [NSString stringWithFormat:@"%@\r\n\r\n%@\r\n.\r\n",
							[[vars[@"mailbox"][msgNum - 1][@"headers"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"]
																	   stringByReplacingOccurrencesOfString:@"\r\n." withString:@"\r\n.."],
							[[vars[@"mailbox"][msgNum - 1][@"body"] stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"]
																	stringByReplacingOccurrencesOfString:@"\r\n." withString:@"\r\n.."]];
						[sock writeData:[preppedData dataUsingEncoding:NSUTF8StringEncoding] withTimeout:timeout tag:0];
					} else {
						[sock writeData:[@"-ERR No such message\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
					}
				} else
					bad_syntax();
			} else if (match_command(@"DELE .*", line)) {
				if ((matches = match_command(@"DELE (\\d+)", line))) {
					NSUInteger msgNum = (NSUInteger)[matches[1] integerValue];
					MCHPOP3ConsoleMessage(@"Client %@ wants to delete message %lu\n", vars[@"remote"], msgNum);
					if (msgNum && msgNum <= [vars[@"mailbox"] count]) {
						[vars[@"deletions"] addIndex:msgNum - 1];
						[sock writeData:[@"+OK Message deleted\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
					} else {
						[sock writeData:[@"-ERR No such message\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
					}
				} else
					bad_syntax();
			} else if (match_command(@"RSET.+", line)) {
				bad_syntax();
			} else if (match_command(@"RSET", line)) {
				MCHPOP3ConsoleMessage(@"Client %@ reset deletions.\n", vars[@"remote"]);
				vars[@"deletions"] = [NSMutableIndexSet indexSet];
				[sock writeData:[@"+OK Reset\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
			} else if (match_command(@"QUIT.+", line)) {
				bad_syntax();
			} else if (match_command(@"QUIT", line)) {
				MCHPOP3ConsoleMessage(@"Client %@ leaving with update\n", vars[@"remote"]);
				vars[@"state"] = @(kPOP3StateUPDATE);
				[[MCHServerMailbox sharedMailbox] updateAndReleaseMboxForUser:vars[@"username"] deletingMessageNumbers:vars[@"deletions"]];
				[vars removeObjectForKey:@"mailbox"];
				[sock writeData:[@"+OK Goodbye\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:timeout tag:0];
				[sock disconnectAfterWriting];
			} else
				bad_command(match_command(@"(USER|PASS|APOP|STLS) ", line) ? true : false);
			break;
		case kPOP3StateUPDATE:
		default:
			// should never get here, but just in case
			bad_command(false);
			break;
	}
	return true;
}

@end
