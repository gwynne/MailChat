//
//  main.m
//  MailChatServer
//
//  Created by Gwynne Raskind on 12/23/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GCDAsyncSocket.h"
#import "NSData+Base64.h"
#import "NSData+MCHUtilities.h"
#import "NSString+Base64.h"
#import "MAGenerator.h"
#import "Console.h"
#import "MCHServerSMTP.h"
#import "MCHServerPOP3.h"
#import "MCHServerMailbox.h"

int main(int argc, const char **argv)
{
	@autoreleasepool
	{
		MCHCoreConsoleMessage(@"Starting up...\n");
		
		MCHServerPOP3 * __block pop3Listener = [[MCHServerPOP3 alloc] init];
		MCHServerSMTP * __block smtpListener = [[MCHServerSMTP alloc] init];
		
		if (pop3Listener && smtpListener) {
			dispatch_source_t infoSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINFO, 0, dispatch_get_main_queue());
			
			signal(SIGINFO, SIG_IGN);
			dispatch_source_set_event_handler(infoSource, ^ {
				MCHConsoleMessage(@"\r");
				[smtpListener dumpInfo];
				[pop3Listener dumpInfo];
				[[MCHServerMailbox sharedMailbox] dumpInfo];
			});
			dispatch_resume(infoSource);

			dispatch_source_t interruptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
			
			signal(SIGINT, SIG_IGN);
			dispatch_source_set_event_handler(interruptSource, ^ {
				MCHConsoleMessage(@"\r");
				MCHCoreConsoleMessage(@"Received SIGINT, closing down.\n");
				pop3Listener = nil;
				smtpListener = nil;
				MCHCoreConsoleMessage(@"Exiting.\n");
				dispatch_source_cancel(infoSource);
				dispatch_source_cancel(interruptSource);
				dispatch_async(dispatch_get_main_queue(), ^ __attribute__((noreturn)) { exit(EXIT_SUCCESS); });
			});
			dispatch_resume(interruptSource);
			
		} else {
			MCHCoreConsoleMessage(@"Initialization failed. Exiting.\n");
			dispatch_async(dispatch_get_main_queue(), ^ __attribute__((noreturn)) { exit(EXIT_FAILURE); });
		}
		dispatch_main();
	}
}

