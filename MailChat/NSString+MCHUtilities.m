//
//  NSString+MCHUtilities.m
//  MailChat
//
//  Created by Gwynne Raskind on 12/26/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "NSString+MCHUtilities.h"
#import "NSData+MCHUtilities.h"

@implementation NSString (MCHUtilities)

- (NSData *)dataByInterpretingAsHexadecimal
{
	return [NSData dataWithHexadecimalRepresentation:self];
}

- (NSData *)MD5Digest
{
	return [self MD5DigestUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)MD5DigestUsingEncoding:(NSStringEncoding)encoding
{
	return [self dataUsingEncoding:encoding].MD5Digest;
}

static NSRegularExpression *get_matcher(void)
{
	static NSRegularExpression *matcher = nil;
	static dispatch_once_t predicate = 0;

	dispatch_once(&predicate, ^ { matcher = [NSRegularExpression regularExpressionWithPattern:@"^(.+)\\s+<([^>]+)>$" options:0 error:nil]; });
	return matcher;
}

- (NSString *)rfc822Address
{
	NSTextCheckingResult *result = nil;
	
	if ((result = [get_matcher() firstMatchInString:self options:0 range:(NSRange){ 0, self.length }]))
		return [self substringWithRange:[result rangeAtIndex:2]];
	return self;
}

- (NSString *)rfc822Name
{
	NSTextCheckingResult *result = nil;
	
	if ((result = [get_matcher() firstMatchInString:self options:0 range:(NSRange){ 0, self.length }]))
		return [self substringWithRange:[result rangeAtIndex:1]];
	return nil;
}

- (instancetype)initWithRFC822Name:(NSString *)name address:(NSString *)address
{
	return name.length ? [self initWithFormat:@"%@ <%@>", name, address] : [self initWithString:address];
}

@end

