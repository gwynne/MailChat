//
//  NSData+MCHUtilities.h
//  MailChat
//
//  Created by Gwynne Raskind on 12/22/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (MCHUtilities)

+ (instancetype)dataWithHexadecimalRepresentation:(NSString *)hex;
- (instancetype)initWithHexadecimalRepresentation:(NSString *)hex;
- (NSString *)stringUsingEncoding:(NSStringEncoding)encoding;
- (NSString *)hexadecimalRepresentation;
- (NSData *)MD5Digest;

@end
