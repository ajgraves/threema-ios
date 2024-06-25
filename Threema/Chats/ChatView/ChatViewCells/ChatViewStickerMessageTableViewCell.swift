//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022-2024 Threema GmbH
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
import ThreemaFramework
import UIKit

/// Display sticker messages
final class ChatViewStickerMessageTableViewCell: ChatViewBaseTableViewCell, MeasurableCell {

    static var sizingCell = ChatViewStickerMessageTableViewCell()
    
    override var bubbleBackgroundColor: UIColor {
        .clear
    }
    
    override var selectedBubbleBackgroundColor: UIColor {
        .clear
    }
    
    override var nameLabelBottomInset: Double {
        0.0
    }
    
    override var bubbleWidthRatio: Double {
        0.7
    }

    /// Sticker message to display
    ///
    /// Reset it when the message had any changes to update data shown in the views (e.g. date or status symbol).
    var stickerMessageAndNeighbors: (message: StickerMessage, neighbors: ChatViewDataSource.MessageNeighbors)? {
        didSet {
            let block = {
                self.updateCell(for: self.stickerMessageAndNeighbors?.message)
                
                super.setMessage(
                    to: self.stickerMessageAndNeighbors?.message,
                    with: self.stickerMessageAndNeighbors?.neighbors
                )
            }
            
            if let oldValue, oldValue.message.objectID == stickerMessageAndNeighbors?.message.objectID {
                UIView.animate(
                    withDuration: ChatViewConfiguration.ChatBubble.bubbleSizeChangeAnimationDurationInSeconds,
                    delay: 0.0,
                    options: .curveEaseInOut
                ) {
                    block()
                    self.layoutIfNeeded()
                }
            }
            else {
                block()
            }
        }
    }
    
    // MARK: - Views & constraints

    private lazy var thumbnailTapView = MessageThumbnailTapView { [weak self] in
        self?.chatViewTableViewCellDelegate?.didTap(message: self?.stickerMessageAndNeighbors?.message, in: self)
    }
    
    private lazy var rootView = UIView()

    // MARK: - Configuration
    
    override func configureCell() {
        super.configureCell()
        
        rootView.addSubview(thumbnailTapView)
        
        thumbnailTapView.translatesAutoresizingMaskIntoConstraints = false
        
        // This adds the margin to the chat bubble border
        rootView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: -ChatViewConfiguration.Thumbnail.defaultMargin,
            leading: -ChatViewConfiguration.Thumbnail.defaultMargin,
            bottom: -ChatViewConfiguration.Thumbnail.defaultMargin,
            trailing: -ChatViewConfiguration.Thumbnail.defaultMargin
        )
        
        NSLayoutConstraint.activate([
            thumbnailTapView.layoutMarginsGuide.topAnchor.constraint(equalTo: rootView.topAnchor),
            thumbnailTapView.layoutMarginsGuide.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            thumbnailTapView.layoutMarginsGuide.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            thumbnailTapView.layoutMarginsGuide
                .bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
        
        super.addContent(rootView: rootView)
    }
    
    // MARK: - Updates
    
    private func updateCell(for stickerMessage: StickerMessage?) {
        // By accepting an optional the data is automatically reset when the text message is set to `nil`
        thumbnailTapView.thumbnailDisplayMessage = stickerMessage
    }
    
    override func updateColors() {
        super.updateColors()
        thumbnailTapView.updateColors()
    }
    
    override func highlightTappableAreasOfCell(_ highlight: Bool) {
        // Do nothing
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)

        thumbnailTapView.isUserInteractionEnabled = !editing
    }
}

// MARK: - ChatViewMessageAction

extension ChatViewStickerMessageTableViewCell: ChatViewMessageAction {
    
    func messageActions()
        -> (
            primaryActions: [ChatViewMessageActionProvider.MessageAction],
            generalActions: [ChatViewMessageActionProvider.MessageAction]
        )? {

        guard let message = stickerMessageAndNeighbors?.message as? StickerMessage else {
            return nil
        }

        typealias Provider = ChatViewMessageActionProvider
        var generalMenuItems = [ChatViewMessageActionProvider.MessageAction]()
        
        // Speak
        var speakText = message.fileMessageType.localizedDescription
        if let caption = message.caption {
            speakText += ", " + caption
        }
        
        // Share
        let shareItems = [MessageActivityItem(for: message)]
        
        // Copy
        // In the new chat view we always copy the data, regardless if it has a caption because the text can be selected
        // itself.
        let copyHandler = {
            guard !MDMSetup(setup: false).disableShareMedia() else {
                DDLogWarn(
                    "[ChatViewStickerMessageTableViewCell] Tried to copy media, even if MDM disabled it."
                )
                return
            }
            
            switch message.fileMessageType {
            case .sticker, .animatedSticker:
                guard let data = message.blobData,
                      let image = UIImage(data: data) else {
                    DDLogError("[CV CxtMenu] Could not copy sticker")
                    NotificationPresenterWrapper.shared.present(type: .copyError)
                    return
                }
                UIPasteboard.general.image = image
                NotificationPresenterWrapper.shared.present(type: .copySuccess)

            default:
                DDLogError("[CV CxtMenu] Message has invalid type.")
            }
        }
        
        // Quote
        let quoteHandler = {
            guard let chatViewTableViewCellDelegate = self.chatViewTableViewCellDelegate else {
                DDLogError("[CV CxtMenu] Could not show quote view because the delegate was nil.")
                return
            }
            
            guard let message = message as? QuoteMessage else {
                DDLogError("[CV CxtMenu] Could not show quote view because the message is not a quote message.")
                return
            }
            
            chatViewTableViewCellDelegate.showQuoteView(message: message)
        }
        
        // Details
        let detailsHandler = {
            self.chatViewTableViewCellDelegate?.showDetails(for: message.objectID)
        }
        
        // Select
        let selectHandler = {
            self.chatViewTableViewCellDelegate?.startMultiselect(with: message.objectID)
        }
        
        // Delete
        let willDelete = {
            self.chatViewTableViewCellDelegate?.willDeleteMessage(with: message.objectID)
        }
        
        let didDelete = {
            self.chatViewTableViewCellDelegate?.didDeleteMessages()
        }
        
        // Ack
        let ackHandler = { (message: BaseMessage, ack: Bool) in
            self.chatViewTableViewCellDelegate?.sendAck(for: message, ack: ack)
        }
            
        // MessageMarkers
        let markStarHandler = { (message: BaseMessage) in
            self.chatViewTableViewCellDelegate?.toggleMessageMarkerStar(message: message)
        }
            
        let (primaryMenuItems, generalActions) = Provider.defaultActions(
            message: message,
            speakText: speakText,
            shareItems: shareItems,
            activityViewAnchor: contentView,
            popOverSource: chatBubbleView,
            copyHandler: copyHandler,
            quoteHandler: quoteHandler,
            detailsHandler: detailsHandler,
            selectHandler: selectHandler,
            willDelete: willDelete,
            didDelete: didDelete,
            ackHandler: ackHandler,
            markStarHandler: markStarHandler
        )
        
        // Build menu
        generalMenuItems.append(contentsOf: generalActions)
        
        if message.isDataAvailable {
            let saveAction = Provider.saveAction {
                guard !MDMSetup(setup: false).disableShareMedia() else {
                    DDLogWarn(
                        "[ChatViewStickerMessageTableViewCell] Tried to save media, even if MDM disabled it."
                    )
                    return
                }
                
                if let saveMediaItem = message.createSaveMediaItem() {
                    AlbumManager.shared.save(saveMediaItem)
                }
            }
            
            // Save action is inserted before default action, depending if ack/dec is possible at a different position
            if !MDMSetup(setup: false).disableShareMedia() {
                if #unavailable(iOS 16), message.isUserAckEnabled {
                    generalMenuItems.insert(saveAction, at: 2)
                }
                else {
                    generalMenuItems.insert(saveAction, at: 0)
                }
            }
        }
        else if message.blobDisplayState == .remote {
            let downloadAction = Provider.downloadAction {
                Task {
                    await BlobManager.shared.syncBlobs(for: message.objectID)
                }
            }
            // Download action is inserted before default action, depending if ack/dec is possible at a different
            // position
            if #unavailable(iOS 16), message.isUserAckEnabled {
                generalMenuItems.insert(downloadAction, at: 2)
            }
            else {
                generalMenuItems.insert(downloadAction, at: 0)
            }
        }
        
        // Retry
        if message.showRetryAndCancelButton {
            let retryHandler = Provider.retryAction { [weak self] in
                guard let self else {
                    return
                }
                
                chatViewTableViewCellDelegate?.retryOrCancelSendingMessage(withID: message.objectID, from: rootView)
            }
            
            // Retry action position analogously to download
            if #unavailable(iOS 16), message.isUserAckEnabled {
                generalMenuItems.insert(retryHandler, at: 2)
            }
            else {
                generalMenuItems.insert(retryHandler, at: 0)
            }
        }
        
        return (primaryMenuItems, generalMenuItems)
    }
    
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            buildAccessibilityCustomActions()
        }
        set {
            // No-op
        }
    }
}

// MARK: - Reusable

extension ChatViewStickerMessageTableViewCell: Reusable { }
