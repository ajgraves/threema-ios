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

import Foundation
import XCTest
@testable import GroupCalls

final class GroupCallViewModelTests: XCTestCase {
    fileprivate var navigationTitle = ""
    
    fileprivate var closed = false
    
    func testBasicInit() async throws {
        let dependencies = MockDependencies().create()

        let groupCallActor = try! GroupCallActor(
            localIdentity: try! ThreemaID(id: "ECHOECHO"),
            groupModel: GroupCallsThreemaGroupModel(
                creator: try! ThreemaID(id: "ECHOECHO"),
                groupID: Data(),
                groupName: "ECHOECHO",
                members: Set([])
            ),
            sfuBaseURL: "",
            gck: Data(repeating: 0x01, count: 32),
            dependencies: dependencies
        )
        
        let viewModel = GroupCallViewModel(groupCallActor: groupCallActor)
        
        viewModel.viewDelegate = self
        
        await groupCallActor.uiContinuation.yield(.connected)
        
        await Task.yield()
        
        // This isn't great since our tests will either succeed or fail by timing out
        // we never quickly discover that our tests fail. But otherwise we might not wait long enough for the state to
        // converge.
        while navigationTitle != "Connected" {
            await Task.yield()
        }
        
        XCTAssertEqual("Connected", navigationTitle)
    }
    
    func testBasicAddRemoveParticipant() async throws {
        let dependencies = MockDependencies().create()
        
        let gck = Data(repeating: 0x01, count: 32)
        
        let groupCallActor = try! GroupCallActor(
            localIdentity: try! ThreemaID(id: "ECHOECHO"),
            groupModel: GroupCallsThreemaGroupModel(
                creator: try! ThreemaID(id: "ECHOECHO"),
                groupID: Data(),
                groupName: "ECHOECHO",
                members: Set([])
            ),
            sfuBaseURL: "",
            gck: gck,
            dependencies: dependencies
        )
        let groupCallDescription = try GroupCallBaseState(
            group: GroupCallsThreemaGroupModel(
                creator: try! ThreemaID(id: "ECHOECHO"),
                groupID: Data(),
                groupName: "ECHOECHO",
                members: Set([])
            ),
            startedAt: Date(),
            maxParticipants: 100,
            dependencies: dependencies,
            groupCallStartData: GroupCallStartData(protocolVersion: 0, gck: gck, sfuBaseURL: "")
        )
        
        let viewModel = GroupCallViewModel(groupCallActor: groupCallActor)
        
        viewModel.viewDelegate = self
        let participantID = ParticipantID(id: 0)
        let remoteParticipant = await RemoteParticipant(
            participant: participantID,
            dependencies: dependencies,
            groupCallCrypto: groupCallDescription,
            isExistingParticipant: false
        )
        await remoteParticipant.setIdentityRemote(id: try! ThreemaID(id: "ECHOECHO"))
        let viewModelParticipant = await ViewModelParticipant(
            remoteParticipant: remoteParticipant,
            name: "ECHOECHO",
            avatar: nil,
            idColor: .red
        )
        
        await groupCallActor.uiContinuation
            .yield(.add(viewModelParticipant))
        
        while viewModel.snapshotPublisher.numberOfItems != 1 {
            await Task.yield()
            try! await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        XCTAssertEqual(viewModel.snapshotPublisher.numberOfItems, 1)
        
        await groupCallActor.uiContinuation.yield(.remove(ParticipantID(id: 1)))
        await groupCallActor.uiContinuation.yield(.remove(ParticipantID(id: 1)))
        
        await Task.yield()
        try! await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(viewModel.snapshotPublisher.numberOfItems, 1)
        
        await groupCallActor.uiContinuation.yield(.remove(participantID))
        
        await Task.yield()
        try! await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertEqual(viewModel.snapshotPublisher.numberOfItems, 0)
    }
}

// MARK: - GroupCallViewProtocol

extension GroupCallViewModelTests: GroupCallViewProtocol {
    func updateNavigationContent(_ contentUpdate: GroupCalls.GroupCallNavigationBarContentUpdate) async { }
        
    func updateLayout() { }
    
    func close() async {
        closed = true
    }
}
