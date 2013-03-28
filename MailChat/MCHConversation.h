//
//  MCHConversation.h
//  MailChat
//
//  Created by Gwynne Raskind on 1/1/13.
//  Copyright (c) 2013 Dark Rainfall. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class MCHMessage, MCHUser;

@interface MCHConversation : NSManagedObject

+ (NSComparator)comparator;
+ (NSComparator)reverseComparator;
- (NSComparisonResult)compare:(MCHConversation *)conversation;

@property(nonatomic,strong) NSOrderedSet *messages;
@property(nonatomic,strong) NSSet *participants;
@end

@interface MCHConversation (CoreDataGeneratedAccessors)

- (void)insertObject:(MCHMessage *)value inMessagesAtIndex:(NSUInteger)idx;
- (void)removeObjectFromMessagesAtIndex:(NSUInteger)idx;
- (void)insertMessages:(NSArray *)value atIndexes:(NSIndexSet *)indexes;
- (void)removeMessagesAtIndexes:(NSIndexSet *)indexes;
- (void)replaceObjectInMessagesAtIndex:(NSUInteger)idx withObject:(MCHMessage *)value;
- (void)replaceMessagesAtIndexes:(NSIndexSet *)indexes withMessages:(NSArray *)values;
- (void)addMessagesObject:(MCHMessage *)value;
- (void)removeMessagesObject:(MCHMessage *)value;
- (void)addMessages:(NSOrderedSet *)values;
- (void)removeMessages:(NSOrderedSet *)values;
- (void)addParticipantsObject:(MCHUser *)value;
- (void)removeParticipantsObject:(MCHUser *)value;
- (void)addParticipants:(NSSet *)values;
- (void)removeParticipants:(NSSet *)values;

@end
