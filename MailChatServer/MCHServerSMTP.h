//
//  MCHServerSMTP.h
//  MailChat
//
//  Created by Gwynne Raskind on 12/24/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GCDAsyncSocket.h"

@interface MCHServerSMTP : NSObject <GCDAsyncSocketDelegate>
@property(atomic,readonly) NSUInteger numClients;
- (void)dumpInfo;
@end
