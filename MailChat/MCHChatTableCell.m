//
//  MCHChatTableCell.m
//  MailChat
//
//  Created by Gwynne Raskind on 12/11/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "MCHChatTableCell.h"
#import <QuartzCore/QuartzCore.h>

@implementation MCHChatTableCell

+ (CGSize)borderSize { return (CGSize){ 4.0, 4.0 }; }

+ (CGSize)sizeForText:(NSAttributedString *)text constrainedToWidth:(CGFloat)maxWidth
{
	// Metrics don't change total size when direction changes
	UIEdgeInsets metrics = [MCHBubbleButton metricsForDirection:UIPopoverArrowDirectionLeft];
	CGSize minSize = { metrics.left + metrics.right, metrics.top + metrics.bottom };
	CGRect textRect = [text boundingRectWithSize:(CGSize){ maxWidth - minSize.width, 99999.0 }
							options:NSStringDrawingUsesLineFragmentOrigin
							context:nil];
	CGSize result = { .width = minSize.width + textRect.size.width + (self.borderSize.width * 2.0f),
					  .height = minSize.height + textRect.size.height + (self.borderSize.height * 2.0f) };
	
	return result;
}

- (void)layoutSubviews
{
	self.contentView.frame = (CGRect){ CGPointZero, { floor(self.frame.size.width * 0.67), self.frame.size.height } };
	_bubble.frame = CGRectInset(self.contentView.frame, self.class.borderSize.width, self.class.borderSize.height);
	_label.frame = UIEdgeInsetsInsetRect(_bubble.frame, [MCHBubbleButton metricsForDirection:_bubble.direction]);

	if (_bubble.direction != UIPopoverArrowDirectionLeft) {
		self.contentView.frame = (CGRect){ .origin = { floor(self.frame.size.width * 0.33) - self.class.borderSize.width, 0.0 },
										   .size = self.contentView.frame.size };
	}
}

@end
