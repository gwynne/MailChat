//
//  NSIndexPath+MCHUITableViewUnsignedIndexes.h
//  MailChat
//
//  Created by Gwynne Raskind on 1/2/13.
//  Copyright (c) 2013 Dark Rainfall. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSIndexPath (MCHUITableViewUnsignedIndexes)
+ (NSIndexPath *)mch_indexPathForRow:(NSUInteger)row inSection:(NSUInteger)section;
@end
