//
//  MCHMessageGateway.h
//  MailChat
//
//  Created by Gwynne Raskind on 12/14/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <Foundation/Foundation.h>

// Message dictionary (unknown keys are both ignored and preserved):
//	@"sender" -> NSString RFC822 form
//	@"recipient" -> NSString RFC822 form
//	@"body" -> NSString
//	@"uuid" -> NSUUID
//	@"timestamp" -> NSDate
//	@"rawData" -> NSData (only present in delegate callbacks)

@class MCHMessageGateway;

@protocol MCHMessageGatewayDelegate <NSObject>

- (void)gateway:(MCHMessageGateway *)gateway didReceiveIncomingMessage:(NSDictionary *)message;
- (void)gateway:(MCHMessageGateway *)gateway didSendOutgoingMessage:(NSDictionary *)message;
- (void)gateway:(MCHMessageGateway *)gateway didFailWithError:(NSError *)error message:(NSDictionary *)message;

@end

@interface MCHMessageGateway : NSObject

@property(atomic,weak) id<MCHMessageGatewayDelegate> delegate;
@property(nonatomic,assign) bool active;
@property(atomic,copy) NSDictionary *authCredentials; // interpreted by subclasses

- (void)sendMessage:(NSDictionary *)message;

@end
