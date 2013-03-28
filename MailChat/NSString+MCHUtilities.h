//
//  NSString+MCHUtilities.h
//  MailChat
//
//  Created by Gwynne Raskind on 12/26/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (MCHUtilities)

- (NSData *)dataByInterpretingAsHexadecimal;
- (NSData *)MD5Digest;
- (NSData *)MD5DigestUsingEncoding:(NSStringEncoding)encoding;

- (NSString *)rfc822Address;
- (NSString *)rfc822Name;
- (instancetype)initWithRFC822Name:(NSString *)name address:(NSString *)address;

@end
