//
//  MCHAppDelegate.m
//  MailChat
//
//  Created by Gwynne Raskind on 11/15/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "MCHAppDelegate.h"
#import "MCHJSONEmailMessageGateway.h"
#import "MCHMessage.h"
#import "MCHUser.h"
#import "MCHConversation.h"
#import "NSString+MCHUtilities.h"
#import <CoreData/CoreData.h>

@interface MCHAppDelegate () <MCHMessageGatewayDelegate>
@end

@implementation MCHAppDelegate
{
	NSEntityDescription *_messageEntity, *_userEntity, *_conversationEntity;
	dispatch_source_t _timer;
}

- (NSURL *)storeURL
{
	return [[[[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil]
			URLByAppendingPathComponent:@"MCHMessageLogs"] URLByAppendingPathExtension:@"sqlite3"];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	NSError *error = nil;
	
	_mom = [[NSManagedObjectModel alloc] initWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"MCHMessageStore" withExtension:@"momd"]];
	_psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:_mom];
	if (![_psc addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:[self storeURL] options:nil error:&error])
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"PSC store failure" userInfo:@{ @"error": error }];
	_moc = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
	_moc.persistentStoreCoordinator = _psc;
	_messageEntity = [NSEntityDescription entityForName:@"MCHMessage" inManagedObjectContext:_moc];
	_userEntity = [NSEntityDescription entityForName:@"MCHUser" inManagedObjectContext:_moc];
	_conversationEntity = [NSEntityDescription entityForName:@"MCHConversation" inManagedObjectContext:_moc];

	MCHJSONEmailMessageGateway *gateway = [[MCHJSONEmailMessageGateway alloc] init];
	_gateway = gateway;
	gateway.delegate = self;
	gateway.checkInterval = 30.0;
	gateway.mailHost = @"localhost";
	gateway.authCredentials = @{ @"username": @"clientUser@localhost", @"password": @"tesseract" };
	gateway.active = YES;
	
	dispatch_async(dispatch_get_main_queue(), ^{
		NSError *err = nil;

		_localUser = [self userForRFC822Address:@"Local User <clientUser@localhost>"];
		if (![_moc save:&err])
			@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"save error" userInfo:@{ @"error": err }];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"MCHDidChangeLoggedInUser" object:@"clientUser@localhost" userInfo:nil];
	});
	
#if 0
	_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, (uint64_t)(5 * NSEC_PER_SEC), 10000);
	uint32_t __block n = 0;
	dispatch_source_set_event_handler(_timer, ^{
		n = (n > 6 ? 1 : n + 1);
		[_gateway sendMessage:@{
			@"body": [NSString stringWithFormat:@"Message %" PRIu32 " %@", n, [NSDate date]],
			@"sender": @"clientUser@localhost",
			@"recipient": [NSString stringWithFormat:@"ASDF%" PRIu32 " <userClient%" PRIu32 "@localhost>", n, n],
			@"uuid": [NSUUID UUID],
			@"timestamp": [NSDate date],
		}];
	});
	dispatch_resume(_timer);
#endif

    return YES;
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
	_gateway.active = NO;
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
	_gateway.active = YES;
}

- (void)applicationWillTerminate:(UIApplication *)application
{
	_gateway.active = NO;
	_gateway = nil; // release it early if possible
}

- (MCHConversation *)conversationBetweenUser:(MCHUser *)user1 andUser:(MCHUser *)user2
{
	NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"MCHConversation"];
	req.predicate = [NSPredicate predicateWithFormat:@"%@ IN participants AND %@ IN participants", user1, user2];
	req.fetchLimit = 1;
	NSError *error = nil;
	NSArray *results = [_moc executeFetchRequest:req error:&error];
	
	if (!results)
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"fetch error" userInfo:@{ @"error": error }];
	if (results.count)
		return results[0];
	
	MCHConversation *conversation = [[MCHConversation alloc] initWithEntity:_conversationEntity insertIntoManagedObjectContext:_moc];
	
	[conversation addParticipants:[NSSet setWithObjects:user1, user2, nil]];
	// a new conversation has no messages
	return conversation;
}

- (MCHUser *)userForRFC822Address:(NSString *)rfc822Address
{
	NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"MCHUser"];
	req.predicate = [NSPredicate predicateWithFormat:@"address LIKE[c] %@", rfc822Address.rfc822Address];
	NSError *error = nil;
	NSArray *results = nil;
	
	if (!(results = [_moc executeFetchRequest:req error:&error]))
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"fetch error" userInfo:@{ @"error": error }];
	if (results.count)
		return results[0];
	
	MCHUser *user = [[MCHUser alloc] initWithEntity:_userEntity insertIntoManagedObjectContext:_moc];
	
	user.displayName = rfc822Address.rfc822Name;
	user.address = rfc822Address.rfc822Address;
	// a new user has no sent or received messages and participates in no conversations
	return user; // defer save, as all callers of this method will save soon
}

- (void)dispatchMessage:(NSDictionary *)message withNotificationName:(NSString *)noteName
{
	MCHMessage *messageObj = [[MCHMessage alloc] initWithEntity:_messageEntity insertIntoManagedObjectContext:_moc];
	MCHConversation *conversation = nil;
	NSError *error = nil;
	
	messageObj.sender = [self userForRFC822Address:message[@"sender"]];
	messageObj.recipient = [self userForRFC822Address:message[@"recipient"]];
	messageObj.uuid = message[@"uuid"];
	messageObj.timestamp = [message[@"timestamp"] timeIntervalSinceReferenceDate];
	messageObj.body = message[@"body"];
	conversation = [self conversationBetweenUser:messageObj.sender andUser:messageObj.recipient];
	[conversation insertObject:messageObj
				  inMessagesAtIndex:[conversation.messages indexOfObject:messageObj inSortedRange:(NSRange){ 0, conversation.messages.count }
					options:NSBinarySearchingInsertionIndex usingComparator:[MCHMessage comparator]]];
	if (![_moc save:&error])
		@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"save error" userInfo:@{ @"error": error }];
	[[NSNotificationCenter defaultCenter] postNotificationName:noteName object:messageObj userInfo:nil];
}

- (void)gateway:(MCHMessageGateway *)gateway didReceiveIncomingMessage:(NSDictionary *)message
{
	dispatch_async(dispatch_get_main_queue(), ^ { [self dispatchMessage:message withNotificationName:@"MCHDidReceiveMessageNotification"]; });
	NSLog(@"Received messsage %@", message);
}

- (void)gateway:(MCHMessageGateway *)gateway didSendOutgoingMessage:(NSDictionary *)message
{
	dispatch_async(dispatch_get_main_queue(), ^ { [self dispatchMessage:message withNotificationName:@"MCHDidSendMessageNotification"]; });
	NSLog(@"Sent message %@", message);
}

- (void)gateway:(MCHMessageGateway *)gateway didFailWithError:(NSError *)error message:(NSDictionary *)message
{
	dispatch_async(dispatch_get_main_queue(), ^ {
		if (message)
			[[NSNotificationCenter defaultCenter] postNotificationName:@"MCHDidFailMessageSendNotification" object:message userInfo:@{@"error": error}];
		else
			[[NSNotificationCenter defaultCenter] postNotificationName:@"MCHDidFailMessageCheckNotification" object:nil userInfo:@{@"error": error}];
	});
	NSLog(@"Message %@ failed: %@", message, error);
}

@end
