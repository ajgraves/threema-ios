//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2012-2023 Threema GmbH
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

#import <Foundation/Foundation.h>
#import "BoxedMessage.h"
#import "ContactEntity.h"
#import "MyIdentityStore.h"
#import "LoggingDescriptionProtocol.h"
#import "ProtocolDefines.h"
#import "ObjcCspE2eFs_Version.h"

@protocol MyIdentityStoreProtocol;

@interface AbstractMessage : NSObject <NSSecureCoding, LoggingDescriptionProtocol>

@property (nonatomic, strong) NSString *fromIdentity;
@property (nonatomic, strong) NSString *toIdentity;
@property (nonatomic, strong) NSData *messageId NS_SWIFT_NAME(messageID);
@property (nonatomic, strong) NSString *pushFromName;
@property (nonatomic, strong) NSDate *date; // created at
@property (nonatomic, strong) NSDate *deliveryDate;
@property (nonatomic, strong) NSNumber *delivered;
@property (nonatomic, strong) NSNumber *userAck;
@property (nonatomic, strong) NSNumber *sendUserAck;
@property (nonatomic, strong) NSData *nonce;
@property (nonatomic, strong) NSNumber *flags;

@property (nonatomic) BOOL receivedAfterInitialQueueSend;
@property (readonly, nonnull) NSString *loggingDescription;
@property (nonatomic) ForwardSecurityMode forwardSecurityMode;

/**
 Make boxed message with end to end encrypted message.

 @param toContact: Receiver contact of the message
 @param myIdentityStore: Sender of the message, with secret key
 @param nonce: Nonce to encrypt message
 */
- (BoxedMessage* _Nullable)makeBox:(ContactEntity* _Nonnull)toContact myIdentityStore:(id<MyIdentityStoreProtocol>  _Nonnull)myIdentityStore nonce:(NSData* _Nonnull)nonce;

+ (NSData*)randomMessageId NS_SWIFT_NAME(randomMessageID());

/* Methods to be overridden by subclasses: */
- (uint8_t)type;
- (BOOL)flagShouldPush;
- (BOOL)flagDontQueue;
- (BOOL)flagDontAck;
- (BOOL)flagGroupMessage;
- (BOOL)flagImmediateDeliveryRequired;
- (BOOL)flagIsVoIP;
- (nullable NSData *)body;
- (BOOL)canCreateConversation;
- (BOOL)canUnarchiveConversation;
- (BOOL)needsConversation;
- (BOOL)canShowUserNotification;
- (ObjcCspE2eFs_Version)minimumRequiredForwardSecurityVersion;

- (BOOL)isContentValid;
- (NSString *)pushNotificationBody;

- (BOOL)allowSendingProfile;

- (NSString *)getMessageIdString NS_SWIFT_NAME(getMessageIDString());

- (BOOL)noDeliveryReceiptFlagSet;

@end
