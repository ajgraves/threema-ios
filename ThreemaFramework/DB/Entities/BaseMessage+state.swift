//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022-2023 Threema GmbH
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

import Foundation

extension BaseMessage {
    
    /// State of this message
    public enum State {
        // Common
        case read
        case userAcknowledged
        case userDeclined

        // Outgoing
        case sending
        case sent
        case delivered
        case failed
        
        // Incoming
        case received
    }
    
    /// Current state of this message
    ///
    /// This only considers acks and the state bools and doesn't differentiate between single chats, gateway ids and
    /// groups
    public var messageState: State {
        if isOwnMessage {
            return ownMessageState
        }
        else {
            return otherMessageState
        }
    }
    
    public var isUserAckEnabled: Bool {
        // single chats can't ack their own messages
        if isOwnMessage,
           !isGroupMessage {
            return false
        }
        
        // Group chats can only ack their own messages if it's sent
        if isOwnMessage,
           isGroupMessage,
           messageState == .failed || messageState == .sending {
            return false
        }
        
        return true
    }
    
    @objc public var showRetryAndCancelButton: Bool {
        messageState == .failed
    }

    /// Message can only be edited if it was sent no more than 6 hours ago
    public var wasSentMoreThanSixHoursAgo: Bool {
        guard let createdAt = date,
              let date = Calendar.current.date(byAdding: .hour, value: -6, to: .now)
        else {
            return true
        }
        return createdAt < date
    }

    public var isRemoteDeletable: Bool {
        self is AudioMessageEntity ||
            self is FileMessageEntity ||
            self is ImageMessageEntity ||
            self is VideoMessageEntity ||
            self is LocationMessage ||
            self is TextMessage
    }

    // MARK: - Private helper
    
    private var ownMessageState: State {
        if let userAckState {
            return userAckState
        }
                
        if let sendFailed = sendFailed?.boolValue, sendFailed {
            return .failed
        }
        else if read.boolValue {
            return .read
        }
        else if delivered.boolValue {
            return .delivered
        }
        else if sent.boolValue {
            return .sent
        }
        
        return .sending
    }
    
    private var otherMessageState: State {
        if let userAckState {
            return userAckState
        }
        
        if read.boolValue {
            return .read
        }
        
        return .received
    }
    
    private var userAckState: State? {
        guard userackDate != nil else {
            return nil
        }
        
        if userack.boolValue {
            return .userAcknowledged
        }
        else {
            return .userDeclined
        }
    }
}
