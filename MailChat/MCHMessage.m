//
//  MCHMessage.m
//  MailChat
//
//  Created by Gwynne Raskind on 1/1/13.
//  Copyright (c) 2013 Dark Rainfall. All rights reserved.
//

#import "MCHMessage.h"
#import "MCHConversation.h"
#import "MCHUser.h"


@implementation MCHMessage

+ (NSComparator)comparator
{
	// Hulk want Apple use instancetype!
	return ^ NSComparisonResult (MCHMessage *obj1, MCHMessage *obj2) { return [obj1 compare:obj2]; };
}

+ (NSComparator)reverseComparator
{
	return ^ NSComparisonResult (MCHMessage *obj1, MCHMessage *obj2) { return [obj2 compare:obj1]; };
}

- (NSComparisonResult)compare:(MCHMessage *)message
{
	return [(NSDate *)[NSDate dateWithTimeIntervalSinceReferenceDate:self.timestamp] compare:
			(NSDate *)[NSDate dateWithTimeIntervalSinceReferenceDate:message.timestamp]];
}

@dynamic body;
@dynamic timestamp;
@dynamic uuid;
@dynamic conversation;
@dynamic recipient;
@dynamic sender;

@end
