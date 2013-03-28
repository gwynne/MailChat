//
//  Console.h
//  MailChat
//
//  Created by Gwynne Raskind on 12/24/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <Foundation/Foundation.h>

void MCHConsoleMessagev(NSString *format, va_list args) NS_FORMAT_FUNCTION(1, 0);
void MCHConsoleMessage(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

#define MCHSubsystemMessageWriterH(subsystem, color, name)	\
void MCH ## subsystem ## ConsoleMessage(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

MCHSubsystemMessageWriterH(SMTP, 14, "SMTP");
MCHSubsystemMessageWriterH(POP3, 16, "POP3");
MCHSubsystemMessageWriterH(Core, 12, "Core");
MCHSubsystemMessageWriterH(Info, 15, "Info");
MCHSubsystemMessageWriterH(Mbox,  5, "Mbox");

extern const NSTimeInterval timeout;
