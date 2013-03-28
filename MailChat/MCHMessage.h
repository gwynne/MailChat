//
//  MCHMessage.h
//  MailChat
//
//  Created by Gwynne Raskind on 1/1/13.
//  Copyright (c) 2013 Dark Rainfall. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class MCHConversation, MCHUser;

@interface MCHMessage : NSManagedObject

+ (NSComparator)comparator;
+ (NSComparator)reverseComparator;
- (NSComparisonResult)compare:(MCHMessage *)conversation;

@property(nonatomic,strong) NSString *body;
@property(nonatomic,assign) NSTimeInterval timestamp;
@property(nonatomic,strong) NSUUID *uuid;
@property(nonatomic,strong) MCHConversation *conversation;
@property(nonatomic,strong) MCHUser *recipient;
@property(nonatomic,strong) MCHUser *sender;

@end
