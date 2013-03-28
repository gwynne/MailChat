//
//  MCHJSONEmailMessageGateway.h
//  MailChat
//
//  Created by Gwynne Raskind on 12/14/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "MCHMessageGateway.h"

@interface MCHJSONEmailMessageGateway : MCHMessageGateway

@property(nonatomic,copy) NSString *mailHost;
@property(atomic,assign) NSTimeInterval checkInterval;

@end
