//
//  MCHDetailViewController.h
//  MailChat
//
//  Created by Gwynne Raskind on 11/15/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <UIKit/UIKit.h>

@class MCHConversation;

@interface MCHDetailViewController : UITableViewController

@property(nonatomic,strong) MCHConversation *conversation;

@end
