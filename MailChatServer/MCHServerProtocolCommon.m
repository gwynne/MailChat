//
//  MCHServerProtocolCommon.m
//  MailChat
//
//  Created by Gwynne Raskind on 12/25/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "MCHServerProtocolCommon.h"
#import "NSData+MCHUtilities.h"

NSArray *match_command(NSString *pattern, NSData *line)
{
	NSString *possiblyASCII = [line stringUsingEncoding:NSNonLossyASCIIStringEncoding];
	
	if (!possiblyASCII)
		return nil;
	
	NSRegularExpression *regexp = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"^%@\\r\\n$", pattern]
													   options:0 error:NULL];
	NSTextCheckingResult *result = [regexp firstMatchInString:possiblyASCII options:NSMatchingAnchored range:(NSRange){ 0, possiblyASCII.length }];
	
	if (result) {
		NSMutableArray *results = @[possiblyASCII].mutableCopy;
		
		for (NSUInteger i = 1; i < result.numberOfRanges; ++i) {
			NSRange range = [result rangeAtIndex:i];
			
			[results addObject:range.location == NSNotFound ? @"" : [possiblyASCII substringWithRange:range]];
		}
		return results;
	}
	return nil;
}