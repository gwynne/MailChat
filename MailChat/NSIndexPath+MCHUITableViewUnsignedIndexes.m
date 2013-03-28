//
//  NSIndexPath+MCHUITableViewUnsignedIndexes.m
//  MailChat
//
//  Created by Gwynne Raskind on 1/2/13.
//  Copyright (c) 2013 Dark Rainfall. All rights reserved.
//

#import "NSIndexPath+MCHUITableViewUnsignedIndexes.h"

@implementation NSIndexPath (MCHUITableViewUnsignedIndexes)

+ (NSIndexPath *)mch_indexPathForRow:(NSUInteger)row inSection:(NSUInteger)section
{
	return [self indexPathForItem:(NSInteger)row inSection:(NSInteger)section];
}

@end
