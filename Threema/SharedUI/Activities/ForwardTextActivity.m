//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2015-2024 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

#import "ForwardTextActivity.h"
#import "ContactGroupPickerViewController.h"
#import "BundleUtil.h"

@interface ForwardTextActivity () <ContactGroupPickerDelegate, ModalNavigationControllerDelegate>

@property NSString *text;

@end

@implementation ForwardTextActivity

+ (UIActivityCategory)activityCategory {
    return UIActivityCategoryAction;
}

- (NSString *)activityType {
    return [NSString stringWithFormat:@"%@.forwardMsg", [[BundleUtil mainBundle] bundleIdentifier]];
}

- (NSString *)activityTitle {
    return [BundleUtil localizedStringForKey:@"forward"];
}

- (UIImage *)activityImage {
    return [UIImage systemImageNamed:@"arrowshape.turn.up.right.fill"];
}

- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems {
    if (activityItems.count != 1) {
        return NO;
    }
    
    return [activityItems[0] isKindOfClass:[NSString class]];
}

- (void)prepareWithActivityItems:(NSArray *)activityItems {
    _text = activityItems[0];
}

- (UIViewController *)activityViewController {
    ModalNavigationController *navigationController = [ContactGroupPickerViewController pickerFromStoryboardWithDelegate:self];
    return navigationController;
}

- (void)sendMessageToConversation:(Conversation *)conversation {
    MessageSender *messageSender = [[BusinessInjector new] messageSenderObjC];
    [messageSender sendTextMessageWithText:_text in:conversation quickReply:NO requestID:nil completion:nil];
}

#pragma mark - ContactPickerDelegate

- (void)contactPicker:(ContactGroupPickerViewController*)contactPicker didPickConversations:(NSSet *)conversations renderType:(NSNumber *)renderType sendAsFile:(BOOL)sendAsFile {
    MessageSender *messageSender = [[BusinessInjector new] messageSenderObjC];
    for (Conversation *conversation in conversations) {
        [self sendMessageToConversation:conversation];
        
        if (contactPicker.additionalTextToSend) {
            [messageSender sendTextMessageWithText:contactPicker.additionalTextToSend in:conversation quickReply:NO requestID:nil completion:nil];
        }
    }
    
    [contactPicker dismissViewControllerAnimated:YES completion:nil];
}

- (void)contactPickerDidCancel:(ContactGroupPickerViewController*)contactPicker {
    [contactPicker dismissViewControllerAnimated:YES completion:nil];
}

- (void)contactPicker:(ContactGroupPickerViewController *)contactPicker addText:(NSString *)text {
    
}

#pragma mark - ModalNavigationControllerDelegate

- (void)didDismissModalNavigationController {
    
}

@end
