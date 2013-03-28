//
//  NSData+MCHUtilities.m
//  MailChat
//
//  Created by Gwynne Raskind on 12/22/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "NSData+MCHUtilities.h"
#import <CommonCrypto/CommonDigest.h>

@implementation NSData (MCHUtilities)

- (NSString *)stringUsingEncoding:(NSStringEncoding)encoding
{
	return [[NSString alloc] initWithData:self encoding:encoding];
}

- (NSString *)hexadecimalRepresentation
{
	NSUInteger length = self.length << 1;
	uint8_t *hexRep = calloc(sizeof(uint8_t), length + 1);
	const uint8_t *bytes = self.bytes;
	
	for (NSUInteger i = 0; i < length; ++i) {
		uint8_t nibble = ((bytes[i >> 1] & (0x0F << (4 & ~((i & 0x1) << 2)))) >> (4 & ~((i & 0x1) << 2)));

		hexRep[i] = nibble + (nibble > 9 ? 'a' - 10 : '0');
	}
	return [[NSString alloc] initWithBytesNoCopy:hexRep length:length encoding:NSUTF8StringEncoding freeWhenDone:YES];
}

+ (instancetype)dataWithHexadecimalRepresentation:(NSString *)hex
{
	return [[self alloc] initWithHexadecimalRepresentation:hex];
}

- (instancetype)initWithHexadecimalRepresentation:(NSString *)hex
{
	NSUInteger size = hex.length >> 1;
	uint8_t *rawData = calloc(sizeof(uint8_t), size);
	const uint8_t *ascii = [hex dataUsingEncoding:NSNonLossyASCIIStringEncoding allowLossyConversion:NO].bytes;
	
	if (!ascii)
		return nil;
	
	for (NSUInteger i = 0; i < size << 2; i += 2)
	{
		if (((ascii[i + 0] < '0' || ascii[i + 0] > '9') && (ascii[i + 0] < 'A' || ascii[i + 0] > 'F') && (ascii[i + 0] < 'a' || ascii[i + 0] > 'f')) ||
			((ascii[i + 1] < '0' || ascii[i + 1] > '9') && (ascii[i + 1] < 'A' || ascii[i + 1] > 'F') && (ascii[i + 1] < 'a' || ascii[i + 1] > 'f'))) {
			size = i;
			break;
		}
		rawData[i >> 1] = (uint8_t)((ascii[i + 0] - (ascii[i + 0] >= 'a' ? 'a' - 10 : (ascii[i + 0] >= 'A' ? 'A' - 10 : '0'))) << 4) |
						  (uint8_t)((ascii[i + 1] - (ascii[i + 1] >= 'a' ? 'a' - 10 : (ascii[i + 1] >= 'A' ? 'A' - 10 : '0'))) << 0);
	}
	return [self initWithBytesNoCopy:rawData length:size freeWhenDone:YES];
}

- (NSData *)MD5Digest
{
	NSMutableData *result = [NSMutableData dataWithLength:CC_MD5_DIGEST_LENGTH];
	
	CC_MD5(self.bytes, (CC_LONG)self.length, result.mutableBytes);
	return result;
}

@end
