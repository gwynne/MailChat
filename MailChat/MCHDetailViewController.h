//
//  MCHDetailViewController.h
//  MailChat
//
//  Created by Gwynne Raskind on 11/15/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface MCHDetailViewController : UIViewController

@property (strong, nonatomic) id detailItem;

@property (weak, nonatomic) IBOutlet UILabel *detailDescriptionLabel;
@end
