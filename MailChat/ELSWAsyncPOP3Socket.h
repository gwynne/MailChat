//
//  ELSWAsyncPOP3Socket.h
//  MailChat
//
//  Created by Gwynne Raskind on 12/16/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "GCDAsyncSocket.h"

@protocol ELSWAsyncPOP3SocketDelegate;

enum { kPOP3DefaultPort = 110, kPOP3SDefaultPort = 995 };

// RFCs 1939, 2449, 2595, 5034
@interface ELSWAsyncPOP3Socket : GCDAsyncSocket

// It is strongly recommended to use these methods to initialize a POP3 socket.
- (instancetype)initWithPOP3Delegate:(id<ELSWAsyncPOP3SocketDelegate>)aDelegate delegateQueue:(dispatch_queue_t)dq;
- (instancetype)initWithPOP3Delegate:(id<ELSWAsyncPOP3SocketDelegate>)aDelegate delegateQueue:(dispatch_queue_t)dq socketQueue:(dispatch_queue_t)sq;

// WARNING: Always use the pop3Delegate of a POP3 socket. NEVER set the socket's
//	"delegate" property.
@property(atomic,weak) id<ELSWAsyncPOP3SocketDelegate> pop3Delegate;
- (void)setPOP3Delegate:(id<ELSWAsyncPOP3SocketDelegate>)delegate delegateQueue:(dispatch_queue_t)delegateQueue;
- (void)synchronouslySetPOP3Delegate:(id<ELSWAsyncPOP3SocketDelegate>)pop3Delegate;
- (void)synchronouslySetPOP3Delegate:(id<ELSWAsyncPOP3SocketDelegate>)pop3Delegate delegateQueue:(dispatch_queue_t)delegateQueue;
// The POP3 socket uses an extra internal queue for managing its
//	protocol-specific operations. It can optionally be set to be the same as the
//	delegate queue and/or the socket queue, but it must not be a concurrent
//	queue.
@property(atomic,strong) dispatch_queue_t internalQueue;
- (void)synchronouslySetInternalQueue:(dispatch_queue_t)internalQueue;

// Note that the operation timeout resets each time any part of an operation
//	completes, as no attempt is made to manage the timout more powerfully. This
//	means that if you set a timeout of 10 seconds, and then it takes 9 seconds
//	to send the command to the server and a further 9 seconds to receive the
//	response status, and 9 more seconds after that to read the rest of the
//	reply, the entire operation will have an effective timeout of 30 seconds.
@property(atomic,assign) NSTimeInterval operationTimeout;

// Always-valid POP3 commands

// QUIT: Orderly disconnect request. Delegate will receive a disconnect message with no error.
- (void)issueQuit;
// CAPA: Request capability list. Delegate will receive list of capabilities supported by server.
//	If doRefresh is false, call delegate immediately with the cached capabilities.
- (void)requestCapabilitiesWithRefresh:(bool)doRefresh;

// AUTHORIZATION state

// USER/PASS: simple unencrypted user/password authentication. Not recommended.
- (void)authWithUsername:(NSString *)username password:(NSString *)password;
// AUTH: authentication with user-supplied mechanism. Delegate must negotiate authentication. Initial response will be Base64 encoded.
- (void)authWithMethod:(NSString *)authMethod initialResponse:(NSData *)initialResponseOrNil;
// APOP: authentication with MD5 user/password. Not recommended; MD5 is weak.
- (void)authWithUsername:(NSString *)username password:(NSString *)password usingMD5:(bool)useAPOP;
// STLS: start TLS negotiation; this is an override of GCDAsyncSocket's method
- (void)startTLS:(NSDictionary *)tlsSettings;

// TRANSACTION state

// STAT: Current mailbox status. Delegate receives message count and total size.
- (void)requestStatus;
// LIST: Specific message information. Delegate receives array of message sizes. Pass -1 to get sizes for all messages.
- (void)requestMessageSize:(NSInteger)msgNum;
// UIDL: Like LIST, but returns unique IDs instead of sizes.
- (void)requestMessageIdentifier:(NSInteger)msgNum;
// TOP/RETR: Retrieve the first n lines of a message. Pass -1 to get whole message. Delegate receives message body without terminator.
- (void)requestMessage:(NSInteger)msgNum limitedToLines:(NSInteger)lineLimit;
// DELE: Mark a message deleted. Delegate receives success indication.
- (void)markMessageDeleted:(NSInteger)msgNum;
// RSET: Reset deleted status of all message. Delegate receives success indication.
- (void)resetMessageStatus;

@end

@protocol ELSWAsyncPOP3SocketDelegate <NSObject, GCDAsyncSocketDelegate>

@optional

// The delegate will receive a disconnect message immediately after this call if
//	the server closes the connection.
- (void)pop3Socket:(ELSWAsyncPOP3Socket *)socket didReceivePOP3Error:(NSString *)serverMessage;

// The POP3 server said hello. This is usually followed by a call to the
//	-pop3Socket:didReceiveCapabilityList: method. If the server sent an APOP
//	nonce in the hello message, it is stripped; use
//	-authWithUsername:password:usingMD5: to send APOP authentication. The most
//	common use of this method is expected to be detecting connection success.
//	The GCDAsyncSocketDelegate method -socket:didConnectToHost:port: can also be
//	implemented.
- (void)pop3Socket:(ELSWAsyncPOP3Socket *)socket didSayHello:(NSString *)helloMessage;

// The POP3 server replied to a request for a list of capabilities. The
//	capability array contains the set of raw strings returned by the server.
- (void)pop3Socket:(ELSWAsyncPOP3Socket *)socket didReceiveCapabilityList:(NSArray *)capabilities;

// The POP3 server replied to an authorization request (of any type) with
//	success. The method is "INSECURE" for user/pass auth, "APOP-MD5" for APOP,
//	or the method string passed to -authWithMethod:initialResponse:
- (void)pop3Socket:(ELSWAsyncPOP3Socket *)socket didAuthenticateWithMethod:(NSString *)authMethod;

// The POP3 server replied to an AUTH request with the given data, which is
//	Base64 decoded before being passed to this method. If this method returns a
//	non-nil NSData, it is Base64-encoded and sent to the server to continue the
//	authentication process; otherwise authentication is assumed to have
//	succeeded, and pop3Socket:didAuthenticateWithCredentials: is called.
- (NSData *)pop3Socket:(ELSWAsyncPOP3Socket *)socket didReplyToAuthenticationRequest:(NSData *)serverReply;

// The POP3 server replied to a STAT request with the given number of messages
//	and message byte count.
- (void)pop3Socket:(ELSWAsyncPOP3Socket *)socket didReceiveMaildropCount:(NSInteger)numMessages maildropSize:(NSInteger)octets;

// The POP3 server replied to a LIST or UIDL request with the given list of
//	message sizes or unique IDs. Dictionary maps message numbers to data. Test
//	the dictionary value type to disambiguate; a message size is guaranteed to
//	be of type NSNumber, while a message ID is guaranteed to be of type
//	NSString.
- (void)pop3Socket:(ELSWAsyncPOP3Socket *)socket didReceiveMessageInfoList:(NSDictionary *)messageSizes;

// The POP3 server received the partial or complete content of a requested
//	message. It is not possible to disambiguate whether the content is in
//	response to TOP or RETR, as this capability was not considered useful.
- (void)pop3Socket:(ELSWAsyncPOP3Socket *)socket didReceiveMessage:(NSData *)message withNumber:(NSInteger)messageNum;

// The POP3 server replied with success to a DELE command (wasDeleted == true)
//	or a RETR command (wasDeleted == false, messageNum == -1).
- (void)pop3Socket:(ELSWAsyncPOP3Socket *)socket didMarkMessage:(NSInteger)messageNum deleted:(bool)wasDeleted;

@end
