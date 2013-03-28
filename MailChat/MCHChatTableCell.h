//
//  MCHChatTableCell.h
//  MailChat
//
//  Created by Gwynne Raskind on 12/11/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MCHBubbleButton.h"

@interface MCHChatTableCell : UITableViewCell

+ (CGSize)sizeForText:(NSAttributedString *)text constrainedToWidth:(CGFloat)maxWidth;

@property(nonatomic,strong) IBOutlet MCHBubbleButton *bubble;
@property(nonatomic,strong) IBOutlet UITextView *label;

@end
