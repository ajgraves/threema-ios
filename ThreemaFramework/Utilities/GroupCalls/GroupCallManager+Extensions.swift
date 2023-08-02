//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2023 Threema GmbH
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
import Foundation
import GroupCalls

extension GroupCallManager {
    // TODO: IOS-3745 This needs to be cleaned up
    public func joinCall(in groupConversationManagedObjectID: NSManagedObjectID) async -> Bool {
        guard ThreemaEnvironment.groupCalls else {
            DDLogVerbose("[GroupCall] GroupCalls are not yet enabled. Skip.")
            return false
        }
        
        guard let groupModel = await getGroupModel(for: groupConversationManagedObjectID) else {
            return false
        }
        
        return await joinCall(in: groupModel, intent: .join).0
    }
    
    public func getGroupModel(for groupConversationManagedObjectID: NSManagedObjectID) async
        -> GroupCallsThreemaGroupModel? {
        guard ThreemaEnvironment.groupCalls else {
            DDLogVerbose("[GroupCall] GroupCalls are not yet enabled. Skip.")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let businessInjector = BusinessInjector()
            
            businessInjector.entityManager.performBlockAndWait {
                guard let conversation = businessInjector.entityManager.entityFetcher
                    .getManagedObject(by: groupConversationManagedObjectID) as? Conversation else {
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let group = GroupManager().getGroup(conversation: conversation) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let groupCreatorID: String = group.groupCreatorIdentity
                let groupCreatorNickname: String? = group.groupCreatorNickname
                let groupID = group.groupID
                let members = group.members.compactMap { try? ThreemaID(id: $0.identity, nickname: $0.publicNickname) }
                
                let groupModel = GroupCallsThreemaGroupModel(
                    creator: try! ThreemaID(id: groupCreatorID, nickname: groupCreatorNickname),
                    groupID: groupID,
                    groupName: group.name ?? "",
                    members: Set(members)
                )
                
                continuation.resume(returning: groupModel)
            }
        }
    }
}
