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

import CocoaLumberjackSwift
import CoreLocation
import Foundation

public final class MessageForwarder {

    private let businessInjector = BusinessInjector()
    private lazy var old_FileMessageSender = Old_FileMessageSender()

    // MARK: - Lifecycle

    public init() { }
    
    // MARK: - Forwarding

    /// Forwards a given base message to a conversation and adds additional text as caption or additional text message.
    /// - Parameters:
    ///   - message: Base message to be forwarded.
    ///   - conversation: Conversation which message should be forwarded to.
    ///   - additionalText: Additional text to be send as caption for file messages, or as normal text message for other
    ///                     types.
    public func forward(
        _ message: BaseMessage,
        to conversation: Conversation,
        sendAsFile: Bool,
        additionalText: String?
    ) {
        
        switch message {
        case let textMessage as TextMessage:
            businessInjector.messageSender.sendTextMessage(text: textMessage.text, in: conversation, quickReply: false)
            sendAdditionalText(additionalText, to: conversation)
            
        case let locationMessage as LocationMessage:
            let coordinates = CLLocationCoordinate2DMake(
                locationMessage.latitude.doubleValue,
                locationMessage.longitude.doubleValue
            )
            let accuracy = locationMessage.accuracy.doubleValue
            
            businessInjector.messageSender.sendLocationMessage(
                coordinates: coordinates,
                accuracy: accuracy,
                poiName: locationMessage.poiName,
                poiAddress: locationMessage.poiAddress,
                in: conversation
            )

            sendAdditionalText(additionalText, to: conversation)
            
        case let fileMessage as FileMessageEntity:
            
            guard let item = URLSenderItem(
                data: fileMessage.data?.data,
                fileName: fileMessage.fileName,
                type: fileMessage.blobUTTypeIdentifier,
                renderType: sendAsFile ? 0 : fileMessage.type,
                sendAsFile: sendAsFile
            ) else {
                DDLogError("[MessageForwarder] Could not create URLSenderItem.")
                return
            }
            
            if let caption = additionalText {
                item.caption = caption
            }
            
            Task {
                do {
                    try await businessInjector.messageSender.sendBlobMessage(for: item, in: conversation.objectID)
                }
                catch {
                    DDLogError("[MessageForwarder] Could not send sender item, error: \(error)")
                }
            }
            
        case let audioMessage as AudioMessageEntity:
            guard let audio = audioMessage.audio,
                  let data = audio.data,
                  let item = URLSenderItem(
                      data: data,
                      fileName: audio.getFilename(),
                      type: UTType.audio.identifier,
                      renderType: sendAsFile ? 0 : 1,
                      sendAsFile: sendAsFile
                  ) else {
                DDLogError("[MessageForwarder] Could not create URLSenderItem.")
                return
            }
            
            Task {
                do {
                    try await businessInjector.messageSender.sendBlobMessage(for: item, in: conversation.objectID)
                }
                catch {
                    DDLogError("[MessageForwarder] Could not send sender item, error: \(error)")
                }
            }
            sendAdditionalText(additionalText, to: conversation)
            
        case let imageMessage as ImageMessageEntity:
            guard let image = imageMessage.image,
                  let data = image.data,
                  let item = URLSenderItem(
                      data: data,
                      fileName: image.getFilename(),
                      type: imageMessage.blobUTTypeIdentifier,
                      renderType: sendAsFile ? 0 : 1,
                      sendAsFile: sendAsFile
                  ) else {
                DDLogError("[MessageForwarder] Could not create URLSenderItem.")
                return
            }
            
            if let caption = additionalText {
                item.caption = caption
            }
            
            Task {
                do {
                    try await businessInjector.messageSender.sendBlobMessage(for: item, in: conversation.objectID)
                }
                catch {
                    DDLogError("[MessageForwarder] Could not send sender item, error: \(error)")
                }
            }
            
        case let videoMessage as VideoMessageEntity:
            guard let video = videoMessage.video,
                  let data = video.data,
                  let item = URLSenderItem(
                      data: data,
                      fileName: video.getFilename(),
                      type: videoMessage.blobUTTypeIdentifier,
                      renderType: sendAsFile ? 0 : 1,
                      sendAsFile: sendAsFile
                  ) else {
                DDLogError("[MessageForwarder] Could not create URLSenderItem.")
                return
            }
            
            if let caption = additionalText {
                item.caption = caption
            }
            
            Task {
                do {
                    try await businessInjector.messageSender.sendBlobMessage(for: item, in: conversation.objectID)
                }
                catch {
                    DDLogError("[MessageForwarder] Could not send sender item, error: \(error)")
                }
            }
            
        default:
            DDLogError("[MessageForwarder] Unsupported message type received.")
        }
    }
    
    private func sendAdditionalText(_ text: String?, to conversation: Conversation) {
        guard let text else {
            return
        }
        
        businessInjector.messageSender.sendTextMessage(text: text, in: conversation, quickReply: false)
    }
}
