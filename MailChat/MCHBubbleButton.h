//
//  MCHBubbleButton.h
//  MailChat
//
//  Created by Gwynne Raskind on 12/7/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MCHBubbleButton : UIControl

+ (UIEdgeInsets)metricsForDirection:(UIPopoverArrowDirection)direction;

@property(nonatomic,strong) UIColor *bubbleColor;
@property(nonatomic,assign) UIPopoverArrowDirection direction;

@end
