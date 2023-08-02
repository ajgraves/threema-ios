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
#import <PromiseKit/PromiseKit.h>
#import "AbstractMessage.h"
#import "MessageProcessorDelegate.h"
    
@class BoxedMessage;
@class Conversation;
@class ContactEntity;

@protocol MessageProcessorProtocol <NSObject>

/**
 Process incoming message.

 @param boxmsg: Incoming Boxed Message
 @param receivedAfterInitialQueueSend: True indicates the message was received before chat server message queue is dry (abstract message will be marked with this flag, to control in app notification)
 @param maxBytesToDecrypt: Max. size in bytes of message to decrypt (will be used is not enough memory available), 0 for no limit
 @param timeoutDownloadThumbnail: Timeout in seconds for downloading thumbnail, set to zero for no timeout
 @return Processed message, if message is null it's NOT processed
*/
- (AnyPromise *)processIncomingMessage:(BoxedMessage*)boxmsg receivedAfterInitialQueueSend:(BOOL)receivedAfterInitialQueueSend maxBytesToDecrypt:(int)maxBytesToDecrypt timeoutDownloadThumbnail:(int)timeoutDownloadThumbnail;

@end

@interface MessageProcessor : NSObject<MessageProcessorProtocol>

- (instancetype)init NS_UNAVAILABLE;

/**
 @param messageProcessorDelegate: Progress information of message processing
 @param entityManager: Must be an EntityManager, is NSObject because EntityManager is implemented in Swift (circularity #import not possible)
 @param fsmp: Must be an ForwardSecurityMessageProcessor, is NSObject because ForwardSecurityMessageProcessor is implemented in Swift (circularity #import not possible)
 @param nonceGuard: Must be an id<NonceGuardProtocolObjc>, is NSObject because NonceGuard is implemented in Swift (circularity #import not
*/
- (instancetype)initWith:(id<MessageProcessorDelegate>)messageProcessorDelegate entityManager:(NSObject *)entityManagerObject fsmp:(NSObject *)fsmp nonceGuard:(NSObject *)nonceGuardObject;

@end
