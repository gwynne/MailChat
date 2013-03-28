//
//  MCHServerMailbox.h
//  MailChat
//
//  Created by Gwynne Raskind on 12/24/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MCHServerMailbox : NSObject
+ (MCHServerMailbox *)sharedMailbox;
- (NSArray *)listOfUsers;
- (void)depositRawMessageData:(NSDictionary *)info;
- (NSArray *)lockMboxForUser:(NSString *)user;
- (void)updateAndReleaseMboxForUser:(NSString *)user deletingMessageNumbers:(NSIndexSet *)deletedNumbers;
- (void)dumpInfo;
@end
