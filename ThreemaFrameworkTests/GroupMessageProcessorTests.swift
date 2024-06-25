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

import ThreemaEssentials
import XCTest

@testable import ThreemaFramework

class GroupMessageProcessorTests: XCTestCase {
    private var databaseCnx: DatabaseContext!
    private var databasePreparer: DatabasePreparer!

    private var ddLoggerMock: DDLoggerMock!
    
    override func setUpWithError() throws {
        // necessary for ValidationLogger
        AppGroup.setGroupID("group.ch.threema") // THREEMA_GROUP_IDENTIFIER @"group.ch.threema"

        let (_, mainCnx, _) = DatabasePersistentContext.devNullContext()
        databaseCnx = DatabaseContext(mainContext: mainCnx, backgroundContext: nil)
        databasePreparer = DatabasePreparer(context: mainCnx)

        ddLoggerMock = DDLoggerMock()
        DDTTYLogger.sharedInstance?.logFormatter = LogFormatterCustom()
        DDLog.add(ddLoggerMock)
    }

    override func tearDownWithError() throws {
        DDLog.remove(ddLoggerMock)
    }
    
    func testHandleMessageGroupNotExists() throws {
        let myIdentityStoreMock = MyIdentityStoreMock()

        // 0: test description
        // test config:
        // 1: group message type
        // 2: group creator
        // 3: message sender
        // expected results:
        // 4: sync request calls
        let tests = [
            [
                "Send GroupRequestSyncMessage and add to pending messages, because group not found for regular group message (creator=sender)",
                GroupTextMessage(),
                "CREATOR1",
                "CREATOR1",
                1,
            ],
            [
                "Send GroupRequestSyncMessage and add to pending messages, because group not found for regular group message",
                GroupTextMessage(),
                "CREATOR1",
                "JAMES007",
                1,
            ],
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-sync-request
            // Section: When receiving this message: 1.
            [
                "Do nothing, because no group found for incoming GroupRequestSyncMessage (creator=sender)",
                GroupRequestSyncMessage(),
                "CREATOR1",
                "CREATOR1",
                0,
            ],
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-sync-request
            // Section: When receiving this message: 2.
            [
                "Do nothing, because no group found for incoming GroupRequestSyncMessage",
                GroupRequestSyncMessage(),
                "CREATOR1",
                "JAMES007",
                0,
            ],
            
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp-e2e/#m:e2e:group-leave
            // Section: When receiving this message: 1.
            [
                "Do nothing, because no group found for incoming GroupLeaveMessage from creator",
                GroupLeaveMessage(),
                "CREATOR1",
                "CREATOR1",
                0,
            ],
            
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp-e2e/#m:e2e:group-leave
            // Section: When receiving this message: 3. / 1.
            [
                "Do nothing, because no group found for incoming GroupLeaveMessage from member and i'm creator",
                GroupLeaveMessage(),
                myIdentityStoreMock.identity,
                "JAMES007",
                0,
            ],
            
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp-e2e/#m:e2e:group-leave
            // Section: When receiving this message: 3. / 2.
            [
                "Send GroupRequestSyncMessage and add do pending messages, because no group found for regular GroupLeaveMessage from member",
                GroupLeaveMessage(),
                "CREATOR1",
                "JAMES007",
                1,
            ],
        ]

        // run tests
        
        for test in tests {
            let testDescription = test[0] as! String

            let userSettingsMock = UserSettingsMock()
            let groupManagerMock: GroupManagerProtocolObjc = GroupManagerMock()

            (test[1] as! AbstractGroupMessage).nonce = MockData.generateMessageNonce()
            (test[1] as! AbstractGroupMessage).groupID = MockData.generateGroupID()
            (test[1] as! AbstractGroupMessage).groupCreator = test[2] as? String
            (test[1] as! AbstractGroupMessage).fromIdentity = test[3] as? String

            let groupMessageProcessor = GroupMessageProcessor(
                message: test[1] as! AbstractGroupMessage,
                myIdentityStore: myIdentityStoreMock,
                userSettings: userSettingsMock,
                groupManager: groupManagerMock as! NSObject,
                entityManager: EntityManager(databaseContext: databaseCnx),
                nonceGuard: NonceGuardMock()
            )

            let expec = expectation(description: "Group message processed")
            
            var resultDidHandleMessage: Bool?
            var resultError: Error?
            
            groupMessageProcessor.handleMessage(onCompletion: { didHandleMessage in
                resultDidHandleMessage = didHandleMessage
                expec.fulfill()
            }, onError: { error in
                resultError = error
                expec.fulfill()
            })

            wait(for: [expec], timeout: 2)
            
            XCTAssertNil(resultError, testDescription)
            XCTAssertTrue(try XCTUnwrap(resultDidHandleMessage), testDescription)
            XCTAssertEqual(
                test[4] as! Int,
                (groupManagerMock as! GroupManagerMock).sendSyncRequestCalls.count,
                testDescription
            )
        }
    }

    func testHandleMessageGroupExistsIamMember() async throws {
        let expectedMember01 = ThreemaIdentity("MEMBER01")
        let expectedMember02 = ThreemaIdentity("MEMBER02")
        let expectedMember03 = ThreemaIdentity("MEMBER03")

        // prepare test db

        [expectedMember01, expectedMember02, expectedMember03].forEach { member in
            databasePreparer.createContact(identity: member.string)
        }

        // 0: test description
        // incoming message:
        // 1: message
        // 2: sender
        // expected results:
        // 3: request sync
        // 4: left the group
        // 5: sync add member
        // 6: sync remove member
        // 7: did handle message
        let tests = [
            [
                "Group found all good, group chat message can be processed",
                GroupTextMessage(),
                expectedMember01.string,
                false,
                false,
                false,
                false,
                false,
            ],
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#n:e2e:groups
            // Section: Receiving 4.
            [
                "Send GroupRequestSyncMessage, because the member of this message is not in group and i'm NOT creator",
                GroupTextMessage(),
                "MEMBER04",
                false,
                false,
                false,
                false,
                true,
            ],
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-sync-request
            // Section: 1.
            [
                "Do nothing, sender is creator of the group",
                GroupRequestSyncMessage(),
                expectedMember01.string,
                false,
                false,
                false,
                false,
                true,
            ],
            [
                "Do nothing, because received GroupRequestSyncMessage form member but i'm not creator",
                GroupRequestSyncMessage(),
                expectedMember02.string,
                false,
                false,
                false,
                false,
                true,
            ],
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp-e2e/#m:e2e:group-leave
            // Section: When receiving this message: 4.
            [
                "Member left the group",
                GroupLeaveMessage(),
                expectedMember02.string,
                false,
                true,
                false,
                false,
                true,
            ],
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp-e2e/#m:e2e:group-leave
            // Section: When receiving this message: 4.
            [
                "Creator left the group",
                GroupLeaveMessage(),
                expectedMember01.string,
                false,
                true,
                false,
                false,
                true,
            ],
        ]

        // run tests

        for test in tests {
            let testDescription = test[0] as! String

            let myIdentityStoreMock = MyIdentityStoreMock()
            let userSettingsMock = UserSettingsMock()
            let taskManagerMock = TaskManagerMock()
            let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)

            let groupManager = GroupManager(
                myIdentityStoreMock,
                ContactStoreMock(callOnCompletion: true),
                taskManagerMock,
                UserSettingsMock(),
                entityManager,
                GroupPhotoSenderMock()
            )

            let expectedGroupIdentity = GroupIdentity(id: MockData.generateGroupID(), creator: expectedMember01)

            guard let group = try await groupManager.createOrUpdateDB(
                for: expectedGroupIdentity,
                members: Set<String>([
                    myIdentityStoreMock.identity,
                    expectedMember01.string,
                    expectedMember02.string,
                    expectedMember03.string,
                ]),
                systemMessageDate: Date(),
                sourceCaller: .local
            ) else {
                XCTFail("Creating group failed")
                return
            }

            let message: AbstractGroupMessage = (test[1] as! AbstractGroupMessage)
            message.nonce = BytesUtility.generateRandomBytes(length: Int(kNonceLen))
            message.groupID = expectedGroupIdentity.id
            message.groupCreator = expectedGroupIdentity.creator.string
            message.fromIdentity = test[2] as? String
            message.toIdentity = myIdentityStoreMock.identity

            let groupMessageProcessor = GroupMessageProcessor(
                message: message,
                myIdentityStore: myIdentityStoreMock,
                userSettings: userSettingsMock,
                groupManager: groupManager,
                entityManager: entityManager,
                nonceGuard: NonceGuardMock()
            )

            let expec = expectation(description: "Group message processed")

            var resultDidHandleMessage: Bool?
            var resultError: Error?

            groupMessageProcessor.handleMessage(onCompletion: { didHandleMessage in
                resultDidHandleMessage = didHandleMessage
                expec.fulfill()
            }, onError: { error in
                resultError = error
                expec.fulfill()
            })

            await fulfillment(of: [expec])

            DDLog.flushLog()

            XCTAssertNil(resultError, testDescription)
            XCTAssertEqual(
                test[3] as! Bool,
                ddLoggerMock
                    .exists(
                        message: "\(message.fromIdentity!) is not member of group \(message.groupID.hexString), add to pending messages and request group sync"
                    ),
                testDescription
            )
            XCTAssertEqual(
                test[4] as! Bool,
                ddLoggerMock
                    .exists(
                        message: "Member \(message.fromIdentity!) left the group \(message.groupID.hexString) \(message.groupCreator!)"
                    ),
                testDescription
            )
            XCTAssertEqual(
                test[5] as! Bool,
                (taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupCreateMessage)?
                    .toMembers
                    .filter { $0 == (test[2] as! String) }.count ?? 0 == 1,
                testDescription
            )
            XCTAssertEqual(
                test[6] as! Bool,
                (taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupCreateMessage)?
                    .removedMembers?
                    .filter { $0 == "MEMBER04" }.count ?? 0 == 1,
                testDescription
            )
            XCTAssertEqual(test[7] as! Bool, try XCTUnwrap(resultDidHandleMessage), testDescription)
        }
    }

    func testHandleMessageGroupExistsIamCreator() async throws {
        let myIdentityStoreMock = MyIdentityStoreMock()

        let expectedMember01 = ThreemaIdentity("MEMBER01")
        let expectedMember02 = ThreemaIdentity("MEMBER02")
        let expectedMember03 = ThreemaIdentity("MEMBER03")
        let expectedCreator = ThreemaIdentity(myIdentityStoreMock.identity)

        // prepare test db

        [expectedMember01, expectedMember02, expectedMember03].forEach { member in
            databasePreparer.createContact(identity: member.string)
        }

        // 0: test description
        // test config:
        // 1: message
        // 2: sender
        // expected results:
        // 3: request sync
        // 4: left the group
        // 5: sync add member
        // 6: sync remove member
        // 7: did handle message
        let tests = [
            [
                "Group found all good, process group message",
                GroupTextMessage(),
                expectedMember01.string,
                false,
                false,
                false,
                false,
                false,
            ],
            [
                "Sync this group (remove member), because member is not in group and i'm creator",
                GroupTextMessage(),
                "MEMBER04",
                false,
                false,
                false,
                true,
                true,
            ],
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-sync-request
            // Section: 1.
            [
                "Do nothing, sender is creator of the group",
                GroupRequestSyncMessage(),
                expectedCreator.string,
                false,
                false,
                false,
                false,
                true,
            ],
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-sync-request
            // Section: When receiving this message: 4.
            [
                "Sync this group, because answer regular GroupRequestSyncMessage from member",
                GroupRequestSyncMessage(),
                "MEMBER04",
                false,
                false,
                false,
                true,
                true,
            ],
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp/#m:e2e:group-sync-request
            // Section: When receiving this message: 5.
            [
                "Sync this group, because answer regular GroupRequestSyncMessage from member",
                GroupRequestSyncMessage(),
                expectedMember02.string,
                false,
                false,
                true,
                false,
                true,
            ],
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp-e2e/#m:e2e:group-leave
            // Section: When receiving this message: 4.
            [
                "Member left the group",
                GroupLeaveMessage(),
                expectedMember02.string,
                false,
                true,
                false,
                false,
                true,
            ],
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp-e2e/#m:e2e:group-leave
            // Section: When receiving this message: 4.
            [
                "Creator left the group",
                GroupLeaveMessage(),
                expectedCreator.string,
                false,
                true,
                false,
                false,
                true,
            ],
        ]

        // run tests

        for test in tests {
            let testDescription = test[0] as! String

            let userSettingsMock = UserSettingsMock()
            let taskManagerMock = TaskManagerMock()
            let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)

            let groupManager = GroupManager(
                myIdentityStoreMock,
                ContactStoreMock(callOnCompletion: true),
                taskManagerMock,
                UserSettingsMock(),
                entityManager,
                GroupPhotoSenderMock()
            )

            let expectedGroupIdentity = GroupIdentity(id: MockData.generateGroupID(), creator: expectedCreator)

            guard let group = try await groupManager.createOrUpdateDB(
                for: expectedGroupIdentity,
                members: Set<String>([expectedMember01.string, expectedMember02.string, expectedMember03.string]),
                systemMessageDate: Date(),
                sourceCaller: .local
            ) else {
                XCTFail("Creating group failed")
                return
            }

            let message: AbstractGroupMessage = (test[1] as! AbstractGroupMessage)
            message.nonce = BytesUtility.generateRandomBytes(length: Int(kNonceLen))
            message.groupID = expectedGroupIdentity.id
            message.groupCreator = expectedGroupIdentity.creator.string
            message.fromIdentity = test[2] as? String
            message.toIdentity = myIdentityStoreMock.identity

            let groupMessageProcessor = GroupMessageProcessor(
                message: message,
                myIdentityStore: myIdentityStoreMock,
                userSettings: userSettingsMock,
                groupManager: groupManager,
                entityManager: entityManager,
                nonceGuard: NonceGuardMock()
            )

            let expec = expectation(description: "Group message processed")

            var resultDidHandleMessage: Bool?
            var resultError: Error?

            groupMessageProcessor.handleMessage(onCompletion: { didHandleMessage in
                resultDidHandleMessage = didHandleMessage
                expec.fulfill()
            }, onError: { error in
                resultError = error
                expec.fulfill()
            })

            await fulfillment(of: [expec])

            DDLog.flushLog()

            XCTAssertNil(resultError, testDescription)
            XCTAssertEqual(
                test[3] as! Bool,
                ddLoggerMock
                    .exists(
                        message: "\(message.fromIdentity!) is not member of group \(message.groupID.hexString), add to pending messages and request group sync"
                    ),
                testDescription
            )
            XCTAssertEqual(
                test[4] as! Bool,
                ddLoggerMock
                    .exists(
                        message: "Member \(message.fromIdentity!) left the group \(message.groupID.hexString) \(message.groupCreator!)"
                    ),
                testDescription
            )
            XCTAssertEqual(
                test[5] as! Bool,
                (taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupCreateMessage)?
                    .toMembers
                    .filter { $0 == "MEMBER02" }.count == 1,
                testDescription
            )
            XCTAssertEqual(
                test[6] as? Bool,
                (taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupCreateMessage)?
                    .removedMembers?
                    .filter { $0 == "MEMBER04" }.count ?? 0 == 1,
                testDescription
            )
            XCTAssertEqual(test[7] as! Bool, try XCTUnwrap(resultDidHandleMessage), testDescription)
        }
    }

    func testHandleMessageGroupExistsILeftTheGroup() async throws {
        let expectedMember01 = "MEMBER01"
        let expectedMember02 = "MEMBER02"
        let expectedMember03 = "MEMBER03"

        [expectedMember01, expectedMember02, expectedMember03].forEach { member in
            databasePreparer.createContact(identity: member)
        }

        let myIdentityStoreMock = MyIdentityStoreMock()

        // 0: test description
        // test config:
        // 1: message
        // 2: sender
        // 3: group creator
        // 4: group members before leaving
        // expected results:
        // 4: dissolve group
        // 5: sent leave group
        let tests = [
            // Spec: https://clients.pages.threema.dev/protocols/threema-protocols/structbuf/csp.struct/index.html#n:e2e:receiving
            // Section: 3.
            [
                "Dissolve group to sender, because I'm creator but left the group",
                GroupTextMessage(),
                expectedMember01,
                myIdentityStoreMock.identity,
                [expectedMember01, expectedMember02, expectedMember03],
                true,
                false,
            ],
            [
                "Send leave group to sender, because I left the group",
                GroupRequestSyncMessage(),
                expectedMember02,
                expectedMember01,
                [myIdentityStoreMock.identity, expectedMember02, expectedMember03],
                false,
                true,
            ],
        ]

        // run tests

        for test in tests {
            let testDescription = test[0] as! String

            let userSettingsMock = UserSettingsMock()
            let taskManagerMock = TaskManagerMock()
            let entityManager = EntityManager(databaseContext: databaseCnx, myIdentityStore: myIdentityStoreMock)

            let groupManager = GroupManager(
                myIdentityStoreMock,
                ContactStoreMock(callOnCompletion: true),
                taskManagerMock,
                userSettingsMock,
                entityManager,
                GroupPhotoSenderMock()
            )

            let expectedGroupIdentity = GroupIdentity(
                id: MockData.generateGroupID(),
                creator: ThreemaIdentity(test[3] as! String)
            )

            guard let group = try await groupManager.createOrUpdateDB(
                for: expectedGroupIdentity,
                members: Set<String>(test[4] as! [String]),
                systemMessageDate: Date(),
                sourceCaller: .local
            ) else {
                XCTFail("Creating group failed")
                return
            }

            XCTAssertEqual(.active, group.state)

            groupManager.leaveDB(
                groupID: expectedGroupIdentity.id,
                creator: expectedGroupIdentity.creator.string,
                member: myIdentityStoreMock.identity,
                systemMessageDate: Date()
            )

            XCTAssertEqual(.left, group.state)

            let message: AbstractGroupMessage = (test[1] as! AbstractGroupMessage)
            message.nonce = BytesUtility.generateRandomBytes(length: Int(kNonceLen))
            message.groupID = expectedGroupIdentity.id
            message.groupCreator = expectedGroupIdentity.creator.string
            message.fromIdentity = (test[2] as! String)
            message.toIdentity = myIdentityStoreMock.identity

            let groupMessageProcessor = GroupMessageProcessor(
                message: message,
                myIdentityStore: myIdentityStoreMock,
                userSettings: userSettingsMock,
                groupManager: groupManager,
                entityManager: entityManager,
                nonceGuard: NonceGuardMock()
            )

            let expec = expectation(description: "Group message processed")

            var resultDidHandleMessage: Bool?
            var resultError: Error?

            groupMessageProcessor.handleMessage(onCompletion: { didHandleMessage in
                resultDidHandleMessage = didHandleMessage
                expec.fulfill()
            }, onError: { error in
                resultError = error
                expec.fulfill()
            })

            await fulfillment(of: [expec])

            DDLog.flushLog()

            XCTAssertNil(resultError, testDescription)
            XCTAssertTrue(try XCTUnwrap(resultDidHandleMessage), testDescription)
            XCTAssertEqual(
                test[5] as! Bool,
                (taskManagerMock.addedTasks.first as? TaskDefinitionGroupDissolve)?
                    .toMembers.contains(where: { $0 == (test[2] as! String) }) ?? false,
                testDescription
            )
            XCTAssertEqual(
                test[6] as! Bool,
                (taskManagerMock.addedTasks.first as? TaskDefinitionSendGroupLeaveMessage)?
                    .toMembers.contains(where: { $0 == (test[2] as! String) }) ?? false,
                testDescription
            )
        }
    }
}
