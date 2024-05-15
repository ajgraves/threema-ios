//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2020-2024 Threema GmbH
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
import TipKit
import UIKit

final class SingleDetailsViewController: ThemedCodeModernGroupedTableViewController {

    // MARK: - Private properties
    
    private let state: SingleDetails.State
    private weak var delegate: DetailsDelegate?
    
    private lazy var headerView: DetailsHeaderView = {
        
        var quickActions = quickActions(in: self)
        if displayStyle == .preview {
            // Don't show quick actions in preview style
            quickActions = []
        }

        return DetailsHeaderView(
            with: contact.contentConfiguration,
            avatarImageTapped: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                var avatarImageData: Data?
                if UserSettings.shared().showProfilePictures {
                    avatarImageData = strongSelf.contact.contactImage?.data
                }
                else {
                    avatarImageData = strongSelf.contact.imageData
                }
                
                guard let avatarData = avatarImageData,
                      let avatarImage = UIImage(data: avatarData) else {
                    return
                }
                
                strongSelf.presentFullscreen(image: avatarImage)
            },
            quickActions: quickActions,
            mediaAndPollsQuickActions: mediaStarredAndPollActions()
        )
    }()
    
    private lazy var dataSource = SingleDetailsDataSource(
        state: state,
        singleDetailsViewController: self,
        tableView: tableView,
        linkedContactManager: linkedContactManager
    )
    
    private let contact: ContactEntity
    private lazy var linkedContactManager = LinkedContactManager(for: contact)
    private lazy var publicKeyView = PublicKeyView(for: contact)
    
    private let displayStyle: DetailsDisplayStyle
    
    private lazy var entityManager = EntityManager()
    
    private var observers = [NSKeyValueObservation]()
    
    // Backwards compatibility
    
    @available(*, deprecated, message: "Only use this for old code to keep it working")
    @objc var _contact: ContactEntity {
        contact
    }
    
    // MARK: - Lifecycle
    
    /// Show details for a conversation with a contact
    /// - Precondition: This is not intended for groups
    /// - Parameters:
    ///   - conversation: Conversation linked to a contact
    ///   - displayStyle: Appearance of the details
    ///   - delegate: Details delegate that is called on certain actions
    init(
        for conversation: Conversation,
        displayStyle: DetailsDisplayStyle = .default,
        delegate: DetailsDelegate?
    ) {
        precondition(!conversation.isGroup(), "This is not intended for groups")
        
        guard let contact = conversation.contact else {
            fatalError("No linked contact for this conversations. This only supports single contacts conversations.")
        }
        
        self.state = .conversationDetails(contact: contact, conversation: conversation)
        self.contact = contact
        
        self.delegate = delegate
        self.displayStyle = displayStyle
        
        super.init()
    }
    
    /// Show details for a contact
    ///
    /// Conversations related information is not shown
    ///
    /// - Parameters:
    ///     - contact: Contact to show details for
    ///     - displayStyle: Appearance of the details
    @objc
    @available(*, deprecated, message: "Use init(for: Contact)")
    init(
        for contact: ContactEntity,
        displayStyle: DetailsDisplayStyle = .default
    ) {
        self.state = .contactDetails(contact: contact)
        self.contact = contact
        self.displayStyle = displayStyle
        
        super.init()
    }

    convenience init(
        for contact: Contact,
        displayStyle: DetailsDisplayStyle = .default
    ) {
        let em = EntityManager()
        self.init(for: em.entityFetcher.contact(for: contact.identity.string), displayStyle: displayStyle)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureTableView()
        
        // To never miss any data change we add the observers before configuration the header and
        // table view data
        addObservers()
        
        configureHeader()
        dataSource.configureData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Ensure that all the data is up to date when switching back to the view
        dataSource.refresh(sections: [.notifications])
        dataSource.reload(sections: [.groups, .privacySettings])
        
        // Call it here to ensure we have the correct constraints
        updateHeaderLayout(animated: false)
        
        if ThreemaUtility.supportsForwardSecurity {
            // Update feature mask for FS so that user can enable it if the contact has just updated the app
            FeatureMask.check(contacts: [contact], for: Int(FEATURE_MASK_FORWARD_SECURITY)) { _ in
                // Feature mask has been updated in DB, observer will take care of updating the UI
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Shows Threema type tip if it was never shown before
        headerView.showThreemaTypeTip()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        publicKeyView.close()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        delegate?.detailsDidDisappear()
    }
    
    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        
        if parent == nil {
            removeObservers()
        }
    }
    
    deinit {
        DDLogDebug("\(#function)")
    }
    
    // MARK: - Configuration
    
    private func addObservers() {
        // Dynamic type
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferredContentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )
        
        // Update title on display name change (e.g. when a new contact is linked)
        observeContact(\.displayName) { [weak self] in
            self?.navigationBarTitle = self?.contact.displayName
            self?.updateHeader(animated: false)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showProfilePictureDidChange),
            name: Notification.Name(kNotificationShowProfilePictureChanged),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(navigationBarColorShouldChange),
            name: Notification.Name(kNotificationNavigationBarColorShouldChange),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshDoNotDisturb),
            name: Notification.Name(kNotificationChangedPushSetting),
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name(kNotificationIncomingSettingsSynchronization),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.dataSource.refresh(sections: [.privacySettings])
            self?.dataSource.reload(sections: [.privacySettings])
        }

        observeContact(\.imageData) { [weak self] in
            self?.updateHeader(animated: false)
        }
        
        observeContact(\.contactImage) { [weak self] in
            self?.updateHeader(animated: false)
        }
        
        observeContact(\.verificationLevel) { [weak self] in
            self?.updateHeader(animated: false)
        }
        
        observeContact(\.publicNickname) { [weak self] in
            self?.dataSource.reload(sections: [.contactInfo])
        }
        
        observeContact(\.featureMask) { [weak self] in
            self?.dataSource.reload(sections: [.fsActions])
        }

        observeContact(\.readReceipt) { [weak self] in
            self?.dataSource.refresh(sections: [.privacySettings])
            self?.dataSource.reload(sections: [.privacySettings])
        }

        observeContact(\.typingIndicator) { [weak self] in
            self?.dataSource.refresh(sections: [.privacySettings])
            self?.dataSource.reload(sections: [.privacySettings])
        }

        // Is needed when willBeDeleted changed, to close this view
        observeContact(\.willBeDeleted) { }
    }

    private func removeObservers() {
        // Invalidate all observers
        for observer in observers {
            observer.invalidate()
        }
        
        // Remove them so we don't reference old observers
        observers.removeAll()

        NotificationCenter.default.removeObserver(self, name: UIContentSizeCategory.didChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name(kNotificationShowProfilePictureChanged),
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name(kNotificationNavigationBarColorShouldChange),
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name(kNotificationChangedPushSetting),
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name(kNotificationIncomingSettingsSynchronization),
            object: nil
        )
    }
    
    /// Helper to add observers to the `contact` property
    ///
    /// All observers are stored in the `observers` property.
    ///
    /// - Parameters:
    ///   - keyPath: Key path in `Contact` to observe
    ///   - changeHandler: Handler called on each observed change.
    ///                     Don't forget to capture `self` weakly! Dispatched on the main queue.
    private func observeContact(_ keyPath: KeyPath<ContactEntity, some Any>, changeHandler: @escaping () -> Void) {

        let observer = contact.observe(keyPath) { [weak self] _, _ in
            guard let strongSelf = self else {
                return
            }
            
            // Check if the observed contact is in the process to be deleted
            guard !strongSelf.contact.willBeDeleted else {
                // Invalidate and remove all observers
                strongSelf.removeObservers()

                // Hide myself
                if strongSelf.isPresentedInModalAndRootView {
                    strongSelf.dismiss(animated: true)
                }
                else {
                    strongSelf.navigationController?.popViewController(animated: true)
                }
                
                return
            }
            
            // Because `changeHandler` updates UI elements we need to ensure that it runs on the main queue
            DispatchQueue.main.async(execute: changeHandler)
        }
        
        observers.append(observer)
    }
    
    // MARK: - Updates
    
    override func updateColors() {
        super.updateColors()
        
        publicKeyView.updateColors()
    }
    
    private func updateHeader(animated: Bool = true) {
        headerView.profileContentConfiguration = contact.contentConfiguration
        updateHeaderLayout(animated: animated)
    }
    
    // MARK: - Actions
    
    @objc private func editButtonTapped() {
        linkedContactManager.editContact(in: self) { contact in
            let editContactViewController = EditContactViewController(for: contact)
            return ThemedNavigationController(rootViewController: editContactViewController)
        }
    }
    
    @objc private func doneButtonTapped() {
        dismiss(animated: true)
    }
    
    // MARK: - Notifications
    
    @objc private func preferredContentSizeCategoryDidChange() {
        updateHeaderLayout()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass {
            // This will be called on rotation
            updateHeaderLayout()
        }
    }
    
    @objc private func showProfilePictureDidChange() {
        updateHeader()
    }
    
    @objc private func navigationBarColorShouldChange() {
        if NavigationBarPromptHandler.shouldShowPrompt() {
            navigationBarTitleAppearanceOffset = 158
        }
        else {
            navigationBarTitleAppearanceOffset = 140
        }
    }

    @objc private func refreshDoNotDisturb(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let pushSetting = notification.object as? PushSetting,
                  pushSetting.identity == self.contact.threemaIdentity else {
                return
            }

            self.dataSource.refresh(sections: [.notifications])
            self.dataSource.reload(sections: [.notifications])
        }
    }
}

// MARK: - Table view

extension SingleDetailsViewController {
    private func configureTableView() {
        navigationBarTitle = contact.displayName
        
        // If this is not set to `self` the automatic (dis)appearance of the navigation bar doesn't
        // work, because it is applied in the `UIScrollViewDelegate` in our superclass.
        tableView.delegate = self
        transparentNavigationBarWhenOnTop = true
        
        tableView.cellLayoutMarginsFollowReadableWidth = true
        
        dataSource.registerHeaderAndCells()
        dataSource.defaultRowAnimation = .fade
    }
}

// MARK: - Header & Quick Actions

extension SingleDetailsViewController {
    
    private func configureHeader() {
        configureNavigationBar()
        configureHeaderView()
    }
    
    private func configureNavigationBar() {
        navigationItem.largeTitleDisplayMode = .never
        
        let editBarButton = UIBarButtonItem(
            barButtonSystemItem: .edit,
            target: self,
            action: #selector(editButtonTapped)
        )
        
        // Check if we are presented in a modal view and the root view controller
        if isPresentedInModalAndRootView {
            navigationItem.leftBarButtonItem = editBarButton
            
            // Only show done button when presented modally
            let doneButton = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(doneButtonTapped)
            )
            doneButton.accessibilityIdentifier = "SingleDetailsViewControllerDoneButton"
            navigationItem.rightBarButtonItem = doneButton
        }
        else {
            // Left bar button is most likely a back button
            navigationItem.rightBarButtonItem = editBarButton
        }
    }
    
    private func configureHeaderView() {
        // Initial header configuration
        headerView.profileContentConfiguration = contact.contentConfiguration
        
        tableView.tableHeaderView = headerView
        
        // Header layout
        
        // Set the header top layout margin to the same as the bottom when in preview mode
        if displayStyle == .preview {
            let currentMargins = headerView.directionalLayoutMargins
            headerView.directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: currentMargins.bottom,
                leading: currentMargins.leading,
                bottom: currentMargins.bottom,
                trailing: currentMargins.trailing
            )
        }
        
        headerView.translatesAutoresizingMaskIntoConstraints = false
        // To make these constraints work always call `updateHeaderLayout(animated:)` when the header
        // layout might have changed
        // WORKAROUND (Last tested: iOS 14.5):
        // The leading and trailing constraints should be constraint to `tableView.marginLayoutGuide`,
        // but this leads sometimes to jumps to the right and back when scrolling (often at the start).
        // This is fixed by using the `tableView.frameLayoutGuide` and then setting the correct
        // margins on the header in `viewLayoutMarginsDidChange()`
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: tableView.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: tableView.frameLayoutGuide.leadingAnchor),
            headerView.bottomAnchor.constraint(equalTo: tableView.bottomAnchor),
            headerView.trailingAnchor.constraint(equalTo: tableView.frameLayoutGuide.trailingAnchor),
        ])
    }
    
    // Always call when the header layout might have changed (e.g. rotation, dynamic type change)
    private func updateHeaderLayout(animated: Bool = true) {
        DispatchQueue.main.async {
            let updateHeight = {
                self.tableView.tableHeaderView = self.headerView
                self.headerView.layoutIfNeeded()
            }
            
            if animated {
                UIView.animate(withDuration: 0.6) {
                    updateHeight()
                }
            }
            else {
                updateHeight()
            }
        }
    }
    
    /// Reload Quick Actions and header layout
    func reloadHeader() {
        headerView.reloadQuickActions()
        updateHeaderLayout()
    }
    
    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        
        // WORKAROUND: See `configureHeaderView()` for details
        // The safe area is subtracted, because it is part of the layout margins. Top and bottom
        // margins are set in other places and don't need to be adjusted for this workaround.
        let currentMargins = headerView.layoutMargins
        headerView.layoutMargins = UIEdgeInsets(
            top: currentMargins.top,
            left: tableView.layoutMargins.left - tableView.safeAreaInsets.left,
            bottom: currentMargins.bottom,
            right: tableView.layoutMargins.right - tableView.safeAreaInsets.right
        )
    }
}

// MARK: - LegacyUIActionProvider

extension SingleDetailsViewController: LegacyUIActionProvider {
    func quickActions(in viewController: UIViewController) -> [QuickAction] {
        dataSource.quickActions(in: viewController)
    }
    
    func mediaStarredAndPollActions() -> [QuickAction] {
        dataSource.mediaStarredAndPollsQuickActions
    }
    
    @objc func uiActions(in viewController: UIViewController) -> NSArray {
        let actions = quickActions(in: viewController).map(\.asUIAction)
        return actions as NSArray
    }
}

// MARK: - Search

extension SingleDetailsViewController {
    /// Tell delegate to start a search in the chat who these details belong to
    ///
    /// This is a workaround so a quick action can talk to the parent. If we end up with more of these we should
    /// consider if there is a better way to communication actions from the details to the chat.
    func startChatSearch(forStarred: Bool = false) {
        // To not have a delay from when the details disappear and the search field appears we show the search
        // field before we dismiss ourself and then active the search after the dismissal.
        delegate?.showChatSearch(forStarred: forStarred)
        dismiss(animated: true)
    }
}

// MARK: - Deleting messages

extension SingleDetailsViewController {
    func willDeleteMessages(with objectIDs: [NSManagedObjectID]) {
        delegate?.willDeleteMessages(with: objectIDs)
    }
    
    func willDeleteAllMessages() {
        delegate?.willDeleteAllMessages()
    }
}

// MARK: - UITableViewDelegate

// The delegate is here instead of `SingleDetailsDataSource`, because otherwise
// the `transparentNavigationBarWhenOnTop` using `UIScrollViewDelegate` would not work correctly.
extension SingleDetailsViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sectionIdentifiers = dataSource.snapshot().sectionIdentifiers
        
        // This should always be true, but just to be safe
        guard sectionIdentifiers.count > section else {
            return nil
        }
        
        let section = sectionIdentifiers[section]
        
        // Figure out title and maybe action
        
        var title: String?
        var action: Details.Action?
        
        switch section {
        case .groups:
            title = String.localizedStringWithFormat(
                BundleUtil.localizedString(forKey: "groups_header"),
                dataSource.numberOfGroups
            )
            
            if dataSource.hasMoreGroupsToShow {
                let localizedShowAllTitle = BundleUtil.localizedString(forKey: "show_all_button")
                
                action = Details.Action(title: localizedShowAllTitle) { [weak self] _ in
                    guard let strongSelf = self else {
                        return
                    }
                    
                    strongSelf.dataSource.showAllGroups(in: strongSelf)
                }
            }
            
        case .notifications:
            title = BundleUtil.localizedString(forKey: "pushSetting_header")
            
        case .privacySettings:
            title = BundleUtil.localizedString(forKey: "privacySetting_header")
            
        default:
            title = nil
        }
        
        // Only show section title if we have any title
        guard title != nil else {
            return nil
        }
        
        let headerView: DetailsSectionHeaderView? = tableView.dequeueHeaderFooter()
        headerView?.title = title
        headerView?.action = action
        
        return headerView
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let row = dataSource.itemIdentifier(for: indexPath) else {
            DDLogDebug("No item identifier found for \(indexPath)")
            return
        }
        
        switch row {
        case let .action(action),
             let .doNotDisturb(action: action, contact: _):
            guard let cell = tableView.cellForRow(at: indexPath) else {
                fatalError("We should have a cell that was tapped for an action.")
            }
            
            action.run(cell)
            
        case .verificationLevel(contact: _):
            let verificationLevelInfoVC = VerificationLevelInfoViewController()
            show(verificationLevelInfoVC, sender: self)
            
        case .publicKey:
            publicKeyView.show()
            
        case .value(label: _, value: contact.identity):
            dataSource.showDebugInfoTapCounter += 1
            
        case .linkedContact:
            guard let cell = tableView.cellForRow(at: indexPath) else {
                fatalError("We should have a cell that was tapped for linking a contact.")
            }
            
            linkedContactManager.linkContact(in: cell, of: self)
            
        case let .group(group):
            let groupDetailsViewController = GroupDetailsViewController(for: group, displayMode: .default)
            show(groupDetailsViewController, sender: self)
            
        case let .privacySettings(action: action, contact: _):
            guard let cell = tableView.cellForRow(at: indexPath) else {
                fatalError("We should have a cell that was tapped for an action.")
            }
            
            action.run(cell)
            
        case let .wallpaper(action: action, isDefault: _):
            guard let cell = tableView.cellForRow(at: indexPath) else {
                fatalError("We should have a cell that was tapped for an action.")
            }
            
            action.run(cell)
            
        case let .booleanAction(action):
            if action.title == "notification_sound_title".localized {
                dataSource.showDebugInfoTapCounter += 1
            }
            
        default:
            // No action possible
            break
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Peak & pop actions support

// Used for iOS 12 support
extension SingleDetailsViewController {
    override var previewActionItems: [UIPreviewActionItem] {
        guard let presentingViewController else {
            return []
        }
        
        // In theory the view controller where the peak interaction starts is what we
        // want there, but it also works with the presenting VC which is the
        // `MainTabBarController`.
        return quickActions(in: presentingViewController).map(\.asUIPreviewAction)
    }
}

extension ContactEntity {
    /// Get a content configuration base on this `Contact`
    fileprivate var contentConfiguration: DetailsHeaderProfileView.ContentConfiguration {
        DetailsHeaderProfileView.ContentConfiguration(
            avatarImageProvider: avatarImageProvider(completion:),
            hideThreemaTypeIcon: !showOtherThreemaTypeIcon,
            name: displayName,
            verificationLevelImage: verificationLevelImage(),
            verificationLevelAccessibilityLabel: verificationLevelAccessibilityLabel()
        )
    }
    
    private func avatarImageProvider(completion: @escaping (UIImage?) -> Void) {
        AvatarMaker.shared().avatar(
            for: self,
            size: DetailsHeaderProfileView.avatarImageSize,
            masked: true
        ) { avatarImage, _ in
            DispatchQueue.main.async {
                completion(avatarImage)
            }
        }
    }
}
