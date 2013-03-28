//
//  MCHUser.h
//  MailChat
//
//  Created by Gwynne Raskind on 1/1/13.
//  Copyright (c) 2013 Dark Rainfall. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class MCHConversation, MCHMessage;

@interface MCHUser : NSManagedObject

@property(nonatomic,strong) NSString *address;
@property(nonatomic,strong) NSString *displayName;
@property(nonatomic,strong) NSSet *conversations;
@property(nonatomic,strong) NSSet *receivedMessages;
@property(nonatomic,strong) NSSet *sentMessages;

@end

@interface MCHUser (CoreDataGeneratedAccessors)

- (void)addConversationsObject:(MCHConversation *)value;
- (void)removeConversationsObject:(MCHConversation *)value;
- (void)addConversations:(NSSet *)values;
- (void)removeConversations:(NSSet *)values;

- (void)addReceivedMessagesObject:(MCHMessage *)value;
- (void)removeReceivedMessagesObject:(MCHMessage *)value;
- (void)addReceivedMessages:(NSSet *)values;
- (void)removeReceivedMessages:(NSSet *)values;

- (void)addSentMessagesObject:(MCHMessage *)value;
- (void)removeSentMessagesObject:(MCHMessage *)value;
- (void)addSentMessages:(NSSet *)values;
- (void)removeSentMessages:(NSSet *)values;

@end
