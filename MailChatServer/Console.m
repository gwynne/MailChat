//
//  Console.m
//  MailChat
//
//  Created by Gwynne Raskind on 12/24/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "Console.h"

const NSTimeInterval timeout = 15.0;

#define MCHSubsystemMessageWriter(subsystem, color, name)	\
void MCH ## subsystem ## ConsoleMessage(NSString *format, ...)	\
{	\
	va_list args;	\
	va_start(args, format);	\
	MCHConsoleMessage(@"[^" @#color @"^" @name @"^.^] ");	\
	MCHConsoleMessagev(format, args);	\
	va_end(args);	\
}

MCHSubsystemMessageWriter(SMTP, 14, "SMTP");
MCHSubsystemMessageWriter(POP3, 16, "POP3");
MCHSubsystemMessageWriter(Core, 12, "Core");
MCHSubsystemMessageWriter(Info, 15, "Info");
MCHSubsystemMessageWriter(Mbox,  5, "Mbox");

void MCHConsoleMessagev(NSString *format, va_list args)
{
	static NSRegularExpression *colorMatcher = nil;
	static dispatch_once_t predicate = 0;
	NSString *formatted = nil;
	
	dispatch_once(&predicate, ^ {
		colorMatcher = [NSRegularExpression regularExpressionWithPattern:@"\\^(1)?([0-7])\\^" options:0 error:nil];
	});
	formatted = [[NSString alloc] initWithFormat:format arguments:args];
	dispatch_async(dispatch_get_main_queue(), ^ {
		NSString *formatting = formatted, *newStr = formatting;
		
		do newStr = [(formatting = newStr) stringByReplacingOccurrencesOfString:@"^^" withString:@"^"]; while (newStr.length != formatting.length);
		formatting = [formatting stringByReplacingOccurrencesOfString:@"^.^" withString:@"\033[m"];
		
		NSMutableString *finalStr = formatting.mutableCopy;
		NSInteger __block rangeAdjust = 0;
		
		[colorMatcher enumerateMatchesInString:formatting options:0 range:(NSRange){ 0, formatting.length }
					  usingBlock:
		^ (NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
			NSString *replacement = [NSString stringWithFormat:@"\033[%u;%ldm",
											  [result rangeAtIndex:1].location == NSNotFound ? 0 : 1,
											  [formatting substringWithRange:[result rangeAtIndex:2]].integerValue + 30];

			[finalStr replaceCharactersInRange:(NSRange){ (NSUInteger)((NSInteger)result.range.location + rangeAdjust), result.range.length }
					  withString:replacement];
			rangeAdjust += (NSInteger)replacement.length - (NSInteger)result.range.length;
		}];
		
		dprintf(STDOUT_FILENO, "%s", finalStr.UTF8String);
	});
}

void MCHConsoleMessage(NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	MCHConsoleMessagev(format, args);
	va_end(args);
}
