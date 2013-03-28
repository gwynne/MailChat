//
//  MCHServerMailbox.m
//  MailChat
//
//  Created by Gwynne Raskind on 12/24/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "MCHServerMailbox.h"
#import "GCDAsyncSocket.h"
#import "Base64.h"
#import "NSData+MCHUtilities.h"
#import "MAGenerator.h"
#import "Console.h"

@implementation MCHServerMailbox
{
	dispatch_queue_t _mailboxQueue;
	NSMutableDictionary *_mailboxes;
	NSMutableSet *_locks;
}

+ (MCHServerMailbox *)sharedMailbox
{
	static MCHServerMailbox *singleton = nil;
	static dispatch_once_t predicate = 0;
	
	dispatch_once(&predicate, ^ { singleton = [[MCHServerMailbox alloc] init]; });
	return singleton;
}

- (id)init
{
	if ((self = [super init]))
	{
		_mailboxes = @{}.mutableCopy;
		_locks = [NSMutableSet set];
		_mailboxQueue = dispatch_queue_create("org.darkrainfall.mailchatserver.mailboxqueue", DISPATCH_QUEUE_SERIAL);
	}
	return self;
}

- (NSArray *)listOfUsers
{
	NSArray * __block result = nil;
	
	dispatch_sync(_mailboxQueue, ^ { result = _mailboxes.allKeys.copy; } );
	return result;
}

- (void)depositRawMessageData:(NSDictionary *)info
{
	dispatch_async(_mailboxQueue, ^ {
		NSData *buffer = info[@"dataBuffer"];
		NSRange r = [buffer rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding] options:0 range:(NSRange){ 0, buffer.length }];
		NSString *headers = nil, *body = nil;
		
		if (r.location == NSNotFound) {
			headers = @"";
			body = [buffer stringUsingEncoding:NSUTF8StringEncoding];
		} else {
			headers = [[buffer subdataWithRange:(NSRange){ 0, r.location }] stringUsingEncoding:NSASCIIStringEncoding];
			body = [[buffer subdataWithRange:(NSRange){ r.location + r.length, buffer.length - r.location - r.length }]
							stringUsingEncoding:NSUTF8StringEncoding];
		}
		headers = [[headers stringByReplacingOccurrencesOfString:@"\r\n.." withString:@"\r\n."]
							stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
		body = [[body stringByReplacingOccurrencesOfString:@"\r\n.." withString:@"\r\n."]
					  stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];

		NSDictionary *msgData = @{
			@"senderServer": info[@"senderDomain"],
			@"sender": [info[@"sender"] lowercaseString],
			@"headers": headers,
			@"body": body,
			@"size": @(headers.length + body.length + 2),
			@"uniqueID": ((NSData *)info[@"dataBuffer"]).MD5Digest.hexadecimalRepresentation,
		};
		
		for (NSString *recipient in info[@"recipients"])
		{
			if (!_mailboxes[recipient.lowercaseString])
				_mailboxes[recipient.lowercaseString] = @[].mutableCopy;
			[_mailboxes[recipient.lowercaseString] addObject:msgData];
			MCHMboxConsoleMessage(@"Deposited message for %@\n", recipient.lowercaseString);
		}
	});
}

- (NSArray *)lockMboxForUser:(NSString *)user
{
	NSArray * __block result = nil;
	
	user = user.lowercaseString;
	dispatch_sync(_mailboxQueue, ^ {
		if (![_locks containsObject:user]) {
			if (!_mailboxes[user])
				_mailboxes[user] = @[].mutableCopy;
			result = [_mailboxes[user] copy];
			[_locks addObject:user];
			MCHMboxConsoleMessage(@"Locked mailbox for %@\n", user);
		}
	});
	return result;
}

- (void)updateAndReleaseMboxForUser:(NSString *)user deletingMessageNumbers:(NSIndexSet *)deletedNumbers
{
	user = user.lowercaseString;
	dispatch_async(_mailboxQueue, ^ {
		if (![_locks containsObject:user])
			return;
		[_locks removeObject:user];
		[_mailboxes[user] removeObjectsAtIndexes:deletedNumbers];
		MCHMboxConsoleMessage(@"Unlocked mailbox for %@, deleted %lu messages\n", user, deletedNumbers.count);
	});
}

- (void)dumpInfo
{
	dispatch_sync(_mailboxQueue, ^ {
		uint32_t __block count = 0;
		[_mailboxes.allValues enumerateObjectsUsingBlock:^ (id obj, NSUInteger idx, BOOL *stop) {
			count += [obj count];
		}];
		MCHInfoConsoleMessage(@"Mailbox contains %u messages for %lu users.\n",
			count,
			_mailboxes.count
		);
	});
}

@end
