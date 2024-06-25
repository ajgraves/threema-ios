//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2023-2024 Threema GmbH
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
import ThreemaEssentials
import XCTest

@testable import GroupCalls

final class JoiningTests: XCTestCase {
    
    fileprivate lazy var creatorIdentity = ThreemaIdentity("ECHOECHO")
    fileprivate lazy var groupIdentity = GroupIdentity(id: Data(repeating: 0x00, count: 8), creator: creatorIdentity)
    fileprivate lazy var localContactModel = ContactModel(identity: creatorIdentity, nickname: "ECHOECHO")
    fileprivate lazy var groupModel = GroupCallsThreemaGroupModel(groupIdentity: groupIdentity, groupName: "TESTGROUP")
    fileprivate lazy var sfuBaseURL = URL(string: "sfu.threema.test")!

    func testBasicInit() async {
        let gck = Data(count: 32)
        let dependencies = MockDependencies().create()
        
        let groupCallActor = try! GroupCallActor(
            localContactModel: localContactModel,
            groupModel: groupModel,
            sfuBaseURL: sfuBaseURL,
            gck: gck,
            dependencies: dependencies
        )
        
        let joining = Joining(groupCallActor: groupCallActor)
        
        guard let newState = try? await joining.next() else {
            XCTFail()
            return
        }
        
        XCTAssertTrue(newState is Connecting)
    }
    
    func testEndOn404() async {
        let gck = Data(repeating: 0x01, count: 32)
        
        let mockHTTPClient = MockHTTPClient(returnCode: 404)
        
        let dependencies = MockDependencies().with(mockHTTPClient).create()
        
        let groupCallActor = try! GroupCallActor(
            localContactModel: localContactModel,
            groupModel: groupModel,
            sfuBaseURL: sfuBaseURL,
            gck: gck,
            dependencies: dependencies
        )
        
        let joining = Joining(groupCallActor: groupCallActor)
        
        guard let newState = try? await joining.next() else {
            XCTFail()
            return
        }
        
        XCTAssertTrue(newState is Ending)
    }
}
