//
//  MCHInsetTextField.m
//  MailChat
//
//  Created by Gwynne Raskind on 1/2/13.
//  Copyright (c) 2013 Dark Rainfall. All rights reserved.
//

#import "MCHInsetTextField.h"

@implementation MCHInsetTextField

- (CGRect)textRectForBounds:(CGRect)bounds
{
	return UIEdgeInsetsInsetRect([super textRectForBounds:bounds], self.textInsets);
}

- (CGRect)editingRectForBounds:(CGRect)bounds
{
	return UIEdgeInsetsInsetRect([super editingRectForBounds:bounds], self.textInsets);
}

@end
