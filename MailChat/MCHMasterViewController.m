//
//  MCHMasterViewController.m
//  MailChat
//
//  Created by Gwynne Raskind on 11/15/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "MCHMasterViewController.h"
#import "MCHDetailViewController.h"
#import "MCHAppDelegate.h"
#import "MGOrderedDictionary.h"
#import "MCHUser.h"
#import "MCHMessage.h"
#import "MCHConversation.h"
#import "NSIndexPath+MCHUITableViewUnsignedIndexes.h"

@implementation MCHMasterViewController
{
	NSMutableArray *_openChats;
	id _receiveObservation, _sendObservation, _loginObservation;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	MCHMasterViewController * __weak w_self = self;
	
	void (^addMessageBlock)(MCHMessage *) = ^ (MCHMessage *message) {
		MCHConversation *conversation = message.conversation;
		MCHMasterViewController * __strong s_self = w_self;
		NSUInteger idx = [s_self->_openChats indexOfObject:conversation];
		
		if (idx == NSNotFound) {
			idx = [s_self->_openChats indexOfObject:conversation inSortedRange:(NSRange){ 0, s_self->_openChats.count }
									  options:NSBinarySearchingInsertionIndex usingComparator:[MCHConversation reverseComparator]];
			[s_self->_openChats insertObject:conversation atIndex:idx];
			[s_self.tableView insertRowsAtIndexPaths:@[[NSIndexPath mch_indexPathForRow:idx inSection:0]]
							  withRowAnimation:UITableViewRowAnimationAutomatic];
		} else {
//			NSArray *oldArray = s_self->_openChats.copy;
//			NSMutableArray *indexPaths = [NSMutableArray array];
			
			[s_self.tableView beginUpdates];
			[s_self->_openChats sortUsingComparator:[MCHConversation reverseComparator]];
			[s_self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
//			[s_self->_openChats enumerateObjectsUsingBlock:^ (id obj, NSUInteger newIdx, BOOL *stop) {
//				NSUInteger oldIdx = [oldArray indexOfObject:obj];
//				
//				[indexPaths	addObject:[NSIndexPath mch_indexPathForRow:newIdx inSection:0]];
//				if (newIdx != oldIdx)
//					[s_self.tableView moveRowAtIndexPath:[NSIndexPath mch_indexPathForRow:oldIdx inSection:0] toIndexPath:indexPaths.lastObject];
//			}];
			[s_self.tableView endUpdates];
		}
	};
	_receiveObservation = [[NSNotificationCenter defaultCenter] addObserverForName:@"MCHDidReceiveMessageNotification" object:nil
								queue:[NSOperationQueue mainQueue] usingBlock:^ (NSNotification *note) { addMessageBlock(note.object); }];
	_sendObservation = [[NSNotificationCenter defaultCenter] addObserverForName:@"MCHDidSendMessageNotification" object:nil
								queue:[NSOperationQueue mainQueue] usingBlock:^ (NSNotification *note) { addMessageBlock(note.object); }];
	_loginObservation = [[NSNotificationCenter defaultCenter] addObserverForName:@"MCHDidChangeLoggedInUser" object:nil
															  queue:[NSOperationQueue mainQueue] usingBlock:
	^ (NSNotification *note) {
		MCHMasterViewController * __strong s_self = w_self;
		MCHAppDelegate *delegate = [UIApplication sharedApplication].delegate;
		s_self->_openChats = [delegate.localUser.conversations.allObjects sortedArrayUsingComparator:[MCHConversation reverseComparator]].mutableCopy;
		[s_self.tableView reloadData];
	}];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:_loginObservation];
	[[NSNotificationCenter defaultCenter] removeObserver:_sendObservation];
	[[NSNotificationCenter defaultCenter] removeObserver:_receiveObservation];
}	

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return (NSInteger)_openChats.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"chat" forIndexPath:indexPath];
	MCHConversation *conversation = _openChats[(NSUInteger)indexPath.row];
	MCHUser *nonlocalUser = [conversation.participants objectsPassingTest:^ BOOL (MCHUser *obj, BOOL *stop) {
		MCHAppDelegate *delegate = [UIApplication sharedApplication].delegate;
		return (*stop = ![obj isEqual:delegate.localUser]);
	}].anyObject;
	
	cell.textLabel.text = nonlocalUser.displayName ?: nonlocalUser.address;
	cell.detailTextLabel.text = ((MCHMessage *)conversation.messages.lastObject).body;
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle == UITableViewCellEditingStyleDelete) {
		MCHConversation *deadConversation = _openChats[(NSUInteger)indexPath.row];
		NSError *error = nil;
		
		[_openChats removeObjectAtIndex:(NSUInteger)indexPath.row];
		[deadConversation.managedObjectContext deleteObject:deadConversation];
		if (![deadConversation.managedObjectContext save:&error])
			@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"save error" userInfo:@{ @"error": error }];
		[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
	}
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	if ([segue.identifier isEqualToString:@"chat"]) {
		NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
		MCHConversation *conversation = _openChats[(NSUInteger)indexPath.row];
		
		((MCHDetailViewController *)segue.destinationViewController).conversation = conversation;
	} else if ([segue.identifier isEqualToString:@"newchat"]) {
		((MCHDetailViewController *)((UINavigationController *)segue.destinationViewController).topViewController).conversation = nil;
	}
}

@end
