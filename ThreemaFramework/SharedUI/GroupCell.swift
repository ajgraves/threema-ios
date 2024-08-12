//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2021-2023 Threema GmbH
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

import UIKit

/// Show a group in a list
///
/// Whenever there is a list of groups use this cell for a consistent appearance
public final class GroupCell: ThemedCodeTableViewCell {
    
    // MARK: - Private configuration
    
    private lazy var configuration = CellConfiguration(size: size)
    
    // MARK: - Public properties
    
    public var size = CellConfiguration.Size.small {
        didSet {
            guard size != oldValue else {
                return
            }
            
            configuration = CellConfiguration(size: size)
            sizeDidChange()
        }
    }
    
    /// Group to show
    @objc public var group: Group? {
        didSet {
            guard let group else {
                return
            }
            
            if let groupName = group.name,
               UserSettings.shared().blacklist.contains(group.groupCreatorIdentity) {
                let blockedGroupName = "🚫 " + groupName
                nameLabel.attributedText = NSAttributedString(string: blockedGroupName)
            }
            else if !group.isSelfMember {
                let strokeEffect: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ]
                nameLabel.attributedText = NSAttributedString(string: group.name ?? "", attributes: strokeEffect)
            }
            else {
                nameLabel.attributedText = NSAttributedString(string: group.name ?? "")
            }
            
            topMetadataLabel.text = group.membersTitleSummary
            membersListLabel.text = group.membersList

            let entityManager = EntityManager()
            entityManager.performAndWait {
                if let conversation = entityManager.entityFetcher.conversation(
                    for: group.groupID,
                    creator: group.groupCreatorIdentity
                ) {
                    self.updateAvatar(for: conversation)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    // Always use max height as possible
    private lazy var avatarSizeConstraint: NSLayoutConstraint = avatarImageView.heightAnchor.constraint(
        lessThanOrEqualToConstant: configuration.maxAvatarSize
    )
    
    private lazy var avatarImageView: UIImageView = {
        let imageView = UIImageView(image: configuration.loadingAvatarImage)
        
        imageView.contentMode = .scaleAspectFit
        
        // Always use max height as possible and set the width with aspect ratio 1:1
        avatarSizeConstraint = imageView.heightAnchor.constraint(lessThanOrEqualToConstant: configuration.maxAvatarSize)
        avatarSizeConstraint.isActive = true
        imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor).isActive = true
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        imageView.accessibilityIgnoresInvertColors = true
        
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            imageView.isHidden = true
        }
        
        return imageView
    }()
    
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
            
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            label.numberOfLines = 2
        }
        
        return label
    }()
    
    private lazy var topMetadataLabel: UILabel = {
        let label = UILabel()
    
        label.textAlignment = .right
        label.font = .preferredFont(forTextStyle: .footnote)
        
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        
        return label
    }()
    
    private lazy var membersListLabel: UILabel = {
        let label = UILabel()
        
        label.font = .preferredFont(forTextStyle: .footnote)

        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            label.numberOfLines = 2
        }
        
        return label
    }()
    
    // MARK: Layout stacks
    
    private lazy var firstLineStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [nameLabel, topMetadataLabel])
        
        stackView.axis = .horizontal
        stackView.alignment = .firstBaseline
        stackView.spacing = 8
        stackView.distribution = .equalSpacing
        
        // As view cells are recreated for each content size change so we can just set this here
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            stackView.axis = .vertical
            stackView.alignment = .leading
        }
        
        return stackView
    }()
    
    private lazy var textStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [firstLineStack, membersListLabel])

        stackView.spacing = configuration.verticalSpacing
        stackView.axis = .vertical
        stackView.distribution = .equalSpacing
        stackView.alignment = .fill

        return stackView
    }()
    
    private lazy var containerStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [avatarImageView, textStack])
        
        stackView.axis = .horizontal
        stackView.distribution = .fill
        stackView.alignment = .center
        
        return stackView
    }()
    
    // MARK: - Lifecycle
    
    override public func configureCell() {
        super.configureCell()
        
        sizeDidChange()
        
        contentView.addSubview(containerStack)
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            avatarSizeConstraint,
            containerStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            containerStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            containerStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            containerStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
        ])
    }
    
    override public func updateColors() {
        super.updateColors()
        
        Colors.setTextColor(Colors.textLight, label: topMetadataLabel)
        Colors.setTextColor(Colors.textLight, label: membersListLabel)
    }
    
    // MARK: - Updates
    
    private func updateAvatar(for conversation: Conversation) {
        avatarSizeConstraint.constant = configuration.maxAvatarSize
        
        AvatarMaker.shared()
            .avatar(for: conversation, size: configuration.maxAvatarSize, masked: true) { avatarImage, objectID in
                guard conversation.objectID == objectID else {
                    return
                }

                guard let avatarImage else {
                    // Show placeholder
                    self.avatarImageView.image = AvatarMaker.shared().unknownGroupImage()
                    return
                }

                DispatchQueue.main.async {
                    self.avatarImageView.image = avatarImage
                }
            }
    }
    
    private func sizeDidChange() {
        nameLabel.font = configuration.nameLabelFont
        containerStack.spacing = configuration.horizontalSpacing
        
        if let group {
            updateAvatar(for: group.conversation)
        }
        
        updateSeparatorInset()
    }
    
    private func updateSeparatorInset() {
        guard !traitCollection.preferredContentSizeCategory.isAccessibilityCategory else {
            separatorInset = .zero
            return
        }
        
        // Note: This will be off when the avatar is smaller than `maxAvatarSize`.
        let leftSeparatorInset = configuration.maxAvatarSize + configuration.horizontalSpacing
        separatorInset = UIEdgeInsets(top: 0, left: leftSeparatorInset, bottom: 0, right: 0)
    }
    
    // MARK: - Accessibility
    
    override public var accessibilityLabel: String? {
        get {
            nameLabel.accessibilityLabel
        }
        set { }
    }
    
    override public var accessibilityValue: String? {
        get {
            [
                topMetadataLabel.accessibilityLabel,
                membersListLabel.accessibilityLabel,
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        }
        set { }
    }
}

// MARK: - Reusable

extension GroupCell: Reusable { }
