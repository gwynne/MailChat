//
//  MCHAppDelegate.h
//  MailChat
//
//  Created by Gwynne Raskind on 11/15/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MCHMessageGateway.h"
#import "MCHUser.h"

@interface MCHAppDelegate : UIResponder <UIApplicationDelegate>

@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) NSManagedObjectContext *moc;
@property(nonatomic,strong) NSPersistentStoreCoordinator *psc;
@property(nonatomic,strong) NSManagedObjectModel *mom;
@property(nonatomic,strong) MCHUser *localUser;
@property(nonatomic,strong) MCHMessageGateway *gateway;

@end
