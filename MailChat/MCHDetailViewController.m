//
//  MCHDetailViewController.m
//  MailChat
//
//  Created by Gwynne Raskind on 11/15/12.
//  Copyright (c) 2012 Dark Rainfall. All rights reserved.
//

#import "MCHDetailViewController.h"
#import "MCHChatTableCell.h"
#import "MCHInsetTextField.h"
#import "UIScrollView+SVPullToRefresh.h"
#import "MCHConversation.h"
#import "MCHMessage.h"
#import "MCHUser.h"
#import <AddressBook/AddressBook.h>
#import <AddressBookUI/AddressBookUI.h>
#import "SVProgressHUD.h"
#import "NSIndexPath+MCHUITableViewUnsignedIndexes.h"
#import "MCHAppDelegate.h"
#import "NSString+MCHUtilities.h"

@interface UITextView (MCHAdditions)
@property(nonatomic,copy) NSAttributedString *lineBreakingAttributedText;
@end

@implementation UITextView (MCHAdditions)
- (NSAttributedString *)lineBreakingAttributedText { return self.attributedText; }
- (void)setLineBreakingAttributedText:(NSAttributedString *)lineBreakingAttributedText
{
	self.attributedText = [[NSAttributedString alloc]
		initWithString:[lineBreakingAttributedText.string stringByReplacingOccurrencesOfString:@"\n" withString:@"\u2028"]
		attributes:[lineBreakingAttributedText attributesAtIndex:0 effectiveRange:NULL]];
}
@end

@interface MCHDetailViewController () <UITextFieldDelegate, ABPeoplePickerNavigationControllerDelegate>
@property(nonatomic,strong) IBOutlet UIView *headerView;
@property(nonatomic,strong) IBOutlet UIView *footerView;
@property(nonatomic,strong) IBOutlet UITextField *toField;
@property(nonatomic,strong) IBOutlet UIButton *addContactButton;
@property(nonatomic,strong) IBOutlet MCHInsetTextField *messageField;
@property(nonatomic,strong) IBOutlet UIButton *sendButton;
- (IBAction)addContact:(id)sender;
- (IBAction)sendMessage:(id)sender;
@end

@implementation MCHDetailViewController
{
	id _receiveObservation, _sendObservation, _failObservation;
	NSUUID *_pendingSendUUID;
	MCHUser *_recipient;
}	

- (void)didReceiveMessage:(MCHMessage *)message
{
	[self.tableView insertRowsAtIndexPaths:@[[NSIndexPath mch_indexPathForRow:[_conversation.messages indexOfObject:message] inSection:0]]
					withRowAnimation:UITableViewRowAnimationAutomatic];
}

// Extra info required because this method may change the controller mode.
- (void)didSendMessage:(MCHMessage *)message
{
	if (![_pendingSendUUID isEqual:message.uuid])
		return;
	
	if (!_conversation) { // Must come before the table view insert.
		_conversation = message.conversation;
		_recipient = [_conversation.participants objectsPassingTest:^ BOOL (id obj, BOOL *stop) {
			MCHAppDelegate *delegate = [UIApplication sharedApplication].delegate;
			return (*stop = ![obj isEqual:delegate.localUser]);
		}].anyObject;
		dispatch_async(dispatch_get_main_queue(), ^ {
			[UIView animateWithDuration:0.33 delay:0.0 options:UIViewAnimationOptionTransitionCrossDissolve animations:^ {
				UIViewController *presenter = self.navigationController.presentingViewController;
				
				self.tableView.tableHeaderView = nil;
				[self setNavBarIsModal:false];
				[presenter dismissViewControllerAnimated:NO completion:NULL];
				[presenter.navigationController pushViewController:self animated:NO];
			} completion:NULL];
		});
	}
	[SVProgressHUD dismiss];
	_messageField.text = nil;
	_pendingSendUUID = nil;
	_sendButton.enabled = NO;
	[self.tableView insertRowsAtIndexPaths:@[[NSIndexPath mch_indexPathForRow:[message.conversation.messages indexOfObject:message] inSection:0]]
					withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)didFailMessage:(NSDictionary *)message
{
	if (![_pendingSendUUID isEqual:message[@"uuid"]])
		return;
	[SVProgressHUD showErrorWithStatus:@"Send failed."];
	_pendingSendUUID = nil;
}

- (void)cancel
{
	[self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:NULL];
}

- (void)setNavBarIsModal:(bool)isModal
{
	if (isModal) {
		self.navigationItem.title = NSLocalizedString(@"New Message", @"new message");
		self.navigationItem.leftBarButtonItem = nil;
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
																		  target:self action:@selector(cancel)];
	} else {
		self.navigationItem.title = _recipient.displayName ?: _recipient.address;
		self.navigationItem.leftBarButtonItem = self.navigationItem.backBarButtonItem;
		self.navigationItem.rightBarButtonItem = nil;
	}
}

- (void)viewDidLoad
{
	self.tableView.tableFooterView = _footerView;
	
	_messageField.background = [[UIImage imageNamed:@"input-field-cover"]
		resizableImageWithCapInsets:(UIEdgeInsets){ .top = 21.0, .bottom = 18.0, .left = 14.0f, .right = 17.0f }];
	_messageField.textInsets = (UIEdgeInsets){ .top = 2.0, .bottom = 0.0, .left = 10.0, .right = 11.0 };
	
	[_sendButton setBackgroundImage:[[UIImage imageNamed:@"SendButton"]
		resizableImageWithCapInsets:(UIEdgeInsets){ .top = 13.0, .bottom = 13.0, .left = 13.0, .right = 13.0 }]
				 forState:UIControlStateNormal];
	[_sendButton setBackgroundImage:[[UIImage imageNamed:@"SendButtonDisabled"]
		resizableImageWithCapInsets:(UIEdgeInsets){ .top = 13.0, .bottom = 13.0, .left = 13.0, .right = 13.0 }]
				 forState:UIControlStateDisabled];
	[_sendButton setBackgroundImage:[[UIImage imageNamed:@"SendButtonPressed"]
		resizableImageWithCapInsets:(UIEdgeInsets){ .top = 13.0, .bottom = 13.0, .left = 13.0, .right = 13.0 }]
				 forState:UIControlStateHighlighted];
}

- (void)viewWillAppear:(BOOL)animated
{
	self.tableView.tableHeaderView = _conversation ? nil : _headerView;
	_recipient = [_conversation.participants objectsPassingTest:^ BOOL (id obj, BOOL *stop) {
		MCHAppDelegate *delegate = [UIApplication sharedApplication].delegate;
		return (*stop = ![obj isEqual:delegate.localUser]);
	}].anyObject;
	[self setNavBarIsModal:!_conversation];

	MCHDetailViewController * __weak w_self = self;
	#define S_SELF() MCHDetailViewController * __strong s_self = w_self
	
	_receiveObservation = [[NSNotificationCenter defaultCenter] addObserverForName:@"MCHDidReceiveMessageNotification" object:nil
										queue:[NSOperationQueue mainQueue]
										usingBlock:^ (NSNotification *note) { S_SELF(); [s_self didReceiveMessage:note.object]; }];
	_sendObservation = [[NSNotificationCenter defaultCenter] addObserverForName:@"MCHDidSendMessageNotification" object:nil
										queue:[NSOperationQueue mainQueue]
										usingBlock:^ (NSNotification *note) { S_SELF(); [s_self didSendMessage:note.object]; }];
	_failObservation = [[NSNotificationCenter defaultCenter] addObserverForName:@"MCHDidFailMessageSendNotification" object:nil
										queue:[NSOperationQueue mainQueue]
										usingBlock:^ (NSNotification *note) { S_SELF(); [s_self didFailMessage:note.object]; }];
}

- (void)viewWillDisappear:(BOOL)animated
{
	if (_pendingSendUUID)
		[SVProgressHUD dismiss];
	[[NSNotificationCenter defaultCenter] removeObserver:_failObservation];
	_failObservation = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:_sendObservation];
	_sendObservation = nil;
	[[NSNotificationCenter defaultCenter] removeObserver:_receiveObservation];
	_receiveObservation = nil;
}

- (void)dealloc
{
	if (_failObservation)
		[[NSNotificationCenter defaultCenter] removeObserver:_failObservation];
	if (_sendObservation)
		[[NSNotificationCenter defaultCenter] removeObserver:_sendObservation];
	if (_receiveObservation)
		[[NSNotificationCenter defaultCenter] removeObserver:_receiveObservation];
}

- (IBAction)addContact:(id)sender
{
	ABPeoplePickerNavigationController *controller = [[ABPeoplePickerNavigationController alloc] init];
	
	controller.peoplePickerDelegate = self;
	controller.displayedProperties = @[@(kABPersonEmailProperty)];
	[self presentViewController:controller animated:YES completion:^ {}];
}

- (void)peoplePickerNavigationControllerDidCancel:(ABPeoplePickerNavigationController *)peoplePicker
{
	[self dismissViewControllerAnimated:YES completion:^ {}];
}

- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)peoplePicker shouldContinueAfterSelectingPerson:(ABRecordRef)person
{
	return YES;
}

- (BOOL)peoplePickerNavigationController:(ABPeoplePickerNavigationController *)peoplePicker shouldContinueAfterSelectingPerson:(ABRecordRef)person
		property:(ABPropertyID)property identifier:(ABMultiValueIdentifier)identifier
{
	NSString *name = (__bridge_transfer NSString *)ABRecordCopyCompositeName(person);
	id prop = (__bridge_transfer id)ABRecordCopyValue(person, property);
	NSString *email = (__bridge_transfer NSString *)ABMultiValueCopyValueAtIndex((__bridge ABMultiValueRef)prop,
								ABMultiValueGetIndexForIdentifier((__bridge ABMultiValueRef)prop, identifier));
	NSString *finalTo = name.length ? [NSString stringWithFormat:@"%@ <%@>", name, email] : email;
	
	_toField.text = finalTo;
	[self dismissViewControllerAnimated:YES completion:^ {}];
	return NO;
}

- (IBAction)sendMessage:(id)sender
{
	[SVProgressHUD showWithStatus:@"Sending..." maskType:SVProgressHUDMaskTypeGradient];
	MCHAppDelegate *delegate = [UIApplication sharedApplication].delegate;
	NSDictionary *message = @{
		@"body": _messageField.text,
		@"sender": [[NSString alloc] initWithRFC822Name:delegate.localUser.displayName address:delegate.localUser.address],
		@"recipient": _recipient ? [[NSString alloc] initWithRFC822Name:_recipient.displayName address:_recipient.address] : _toField.text,
		@"uuid": [NSUUID UUID],
		@"timestamp": [NSDate date],
	};
	if (!_conversation)
		_pendingSendUUID = message[@"uuid"];
	[delegate.gateway sendMessage:message];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return (NSInteger)_conversation.messages.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	MCHMessage *message = _conversation.messages[(NSUInteger)indexPath.row];

	return [MCHChatTableCell sizeForText:[[NSAttributedString alloc] initWithString:message.body]
							 constrainedToWidth:self.tableView.frame.size.width * 0.67f].height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	MCHChatTableCell *cell = [tableView dequeueReusableCellWithIdentifier:@"message" forIndexPath:indexPath];
	MCHMessage *message = _conversation.messages[(NSUInteger)indexPath.row];

	cell.label.lineBreakingAttributedText = [[NSAttributedString alloc] initWithString:message.body];
	cell.bubble.direction = UIPopoverArrowDirectionLeft << (![_recipient isEqual:message.sender]);
	cell.bubble.bubbleColor = [UIColor clearColor];
	return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	// Return NO if you do not want the specified item to be editable.
	return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle == UITableViewCellEditingStyleDelete) {
//		[_objects removeObjectAtIndex:indexPath.row];
		[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
	} else if (editingStyle == UITableViewCellEditingStyleInsert) {
	}
}

// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath
{
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
}

@end
