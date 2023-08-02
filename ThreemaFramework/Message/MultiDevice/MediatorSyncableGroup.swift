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
import ThreemaProtocols

actor MediatorSyncableGroup {
    private let userSettings: UserSettingsProtocol
    private let taskManager: TaskManagerProtocol
    private let groupManager: GroupManagerProtocol

    private var task: TaskDefinitionGroupSync?

    init(
        _ userSettings: UserSettingsProtocol,
        _ taskManager: TaskManagerProtocol,
        _ groupManager: GroupManagerProtocol
    ) {
        self.userSettings = userSettings
        self.taskManager = taskManager
        self.groupManager = groupManager
    }

    init() {
        self.init(
            UserSettings.shared(),
            TaskManager(),
            GroupManager()
        )
    }

    func updateAll(identity: GroupIdentity) {
        guard userSettings.enableMultiDevice else {
            return
        }

        guard let group = groupManager.getGroup(identity.id, creator: identity.creator) else {
            return
        }

        update(identity: identity, members: Set(group.allActiveMemberIdentitiesWithoutCreator), state: group.state)

        update(identity: identity, name: group.name)

        update(identity: identity, profilePicture: group.profilePicture)

        update(identity: identity, conversationCategory: group.conversationCategory)

        update(identity: identity, conversationVisibility: group.conversationVisibility)

        // TODO: IOS-2825
//        Sync_Group.createdAt
//        Sync_Group.notificationSoundPolicyOverride
//        Sync_Group.notificationTriggerPolicyOverride
    }

    func update(identity: GroupIdentity, members: Set<String>, state: GroupState) {
        guard userSettings.enableMultiDevice else {
            return
        }

        var sGroup = getSyncGroup(identity: identity)

        sGroup.memberIdentities.identities = Array(members)

        switch state {
        case .active:
            sGroup.userState = .member
        case .forcedLeft:
            sGroup.userState = .kicked
        case .left:
            sGroup.userState = .left
        case .requestedSync:
            sGroup.clearUserState()
        }
        setSyncGroup(syncGroup: sGroup)
    }

    func update(identity: GroupIdentity, name: String?) {
        guard userSettings.enableMultiDevice else {
            return
        }

        var sGroup = getSyncGroup(identity: identity)
        if let name {
            sGroup.name = name
        }
        else {
            sGroup.clearName()
        }
        setSyncGroup(syncGroup: sGroup)
    }

    func update(identity: GroupIdentity, profilePicture: Data?) {
        guard userSettings.enableMultiDevice else {
            return
        }

        let sGroup = getSyncGroup(identity: identity)
        setSyncGroup(syncGroup: sGroup)
        task?.profilePicture = profilePicture != nil ? .updated : .removed
        task?.image = profilePicture
    }

    func update(identity: GroupIdentity, conversationCategory: ConversationCategory?) {
        guard userSettings.enableMultiDevice else {
            return
        }

        var sGroup = getSyncGroup(identity: identity)
        if let conversationCategory,
           let category = Sync_ConversationCategory(rawValue: conversationCategory.rawValue) {
            sGroup.conversationCategory = category
        }
        else {
            sGroup.clearConversationCategory()
        }
        setSyncGroup(syncGroup: sGroup)
    }

    func update(identity: GroupIdentity, conversationVisibility: ConversationVisibility?) {
        guard userSettings.enableMultiDevice else {
            return
        }

        var sGroup = getSyncGroup(identity: identity)
        if let conversationVisibility,
           let visibility = Sync_ConversationVisibility(rawValue: conversationVisibility.rawValue) {
            sGroup.conversationVisibility = visibility
        }
        else {
            sGroup.clearConversationVisibility()
        }
        setSyncGroup(syncGroup: sGroup)
    }

    func deleteAndSync(identity: GroupIdentity) {
        guard userSettings.enableMultiDevice else {
            return
        }

        let sGroup = getSyncGroup(identity: identity)
        setSyncGroup(syncGroup: sGroup)

        sync(syncAction: .delete)
    }

    func sync(syncAction: TaskDefinitionGroupSync.SyncAction) {
        if let task {
            task.syncAction = syncAction
            taskManager.add(taskDefinition: task)
        }
    }

    // MARK: Private functions

    private func getSyncGroup(identity: GroupIdentity) -> Sync_Group {
        if let task,
           task.syncGroup.groupIdentity.groupID == identity.id.paddedLittleEndian(),
           task.syncGroup.groupIdentity.creatorIdentity == identity.creator {
            return task.syncGroup
        }
        else {
            var sGroup = Sync_Group()
            sGroup.groupIdentity = Common_GroupIdentity.from(identity)
            return sGroup
        }
    }

    private func setSyncGroup(syncGroup: Sync_Group) {
        if task == nil {
            task = TaskDefinitionGroupSync(syncGroup: syncGroup, syncAction: .update)
        }
        task?.syncGroup = syncGroup
    }
}
