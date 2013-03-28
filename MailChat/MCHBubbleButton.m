//
//  MCHBubbleButton.mm
//  MailChat
//
//  Created by Gwynne Raskind on 12/7/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "MCHBubbleButton.h"

@implementation MCHBubbleButton

+ (UIEdgeInsets)metricsForDirection:(UIPopoverArrowDirection)direction
{
	return direction == UIPopoverArrowDirectionLeft ?
			(UIEdgeInsets){ .top = 14.0, .bottom = 17.0, .left = 24.0, .right = 18.0 } :
			(UIEdgeInsets){ .top = 14.0, .bottom = 17.0, .left = 18.0, .right = 24.0 };
}

- (void)drawRect:(CGRect)rect
{
	UIImage *_cachedImage = [UIImage imageNamed:@"Balloon_2"];
	
	_cachedImage = [_cachedImage resizableImageWithCapInsets:[self.class metricsForDirection:UIPopoverArrowDirectionRight]];
	if (_direction == UIPopoverArrowDirectionLeft) {
		CGContextSaveGState(UIGraphicsGetCurrentContext());
		CGContextConcatCTM(UIGraphicsGetCurrentContext(),
						   CGAffineTransformScale(CGAffineTransformMakeTranslation(self.bounds.size.width, 0.0), -1.0, 1.0));
	}
	[_cachedImage drawInRect:self.bounds];
	[_bubbleColor set];
	UIRectFillUsingBlendMode(self.bounds, kCGBlendModeOverlay);
	if (_direction == UIPopoverArrowDirectionLeft)
		CGContextRestoreGState(UIGraphicsGetCurrentContext());
}

@end
