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

import ThreemaProtocols
import XCTest
@testable import ThreemaFramework

class TaskQueueTests: XCTestCase {
    private var databaseMainCnx: DatabaseContext!
    private var databaseBackgroundCnx: DatabaseContext!
    private var databasePreparer: DatabasePreparer!
    private var ddLoggerMock: DDLoggerMock!
    private var frameworkInjectorMock: FrameworkInjectorProtocol!

    override func setUpWithError() throws {
        // Necessary for ValidationLogger
        AppGroup.setGroupID("group.ch.threema") // THREEMA_GROUP_IDENTIFIER @"group.ch.threema"

        let (_, mainCnx, backgroundCnx) = DatabasePersistentContext.devNullContext()
        databaseMainCnx = DatabaseContext(mainContext: mainCnx, backgroundContext: nil)
        databaseBackgroundCnx = DatabaseContext(mainContext: mainCnx, backgroundContext: backgroundCnx)
        databasePreparer = DatabasePreparer(context: mainCnx)

        ddLoggerMock = DDLoggerMock()
        DDTTYLogger.sharedInstance?.logFormatter = LogFormatterCustom()
        DDLog.add(ddLoggerMock)

        frameworkInjectorMock = BusinessInjectorMock(
            backgroundEntityManager: EntityManager(databaseContext: databaseBackgroundCnx),
            entityManager: EntityManager(databaseContext: databaseMainCnx)
        )
    }
    
    override func tearDownWithError() throws {
        DDLog.remove(ddLoggerMock)
    }
    
    func testInterrupt() {
        let msg = BoxTextMessage()
        msg.messageID = MockData.generateMessageID()

        let task = TaskDefinitionSendAbstractMessage(message: msg, isPersistent: false)

        let tq = TaskQueue(
            queueType: .outgoing,
            supportedTypes: [TaskDefinitionSendAbstractMessage.self],
            frameworkInjector: frameworkInjectorMock
        )

        try? tq.enqueue(task: task, completionHandler: nil)
        XCTAssertEqual(.pending, task.state)

        tq.interrupt()
        XCTAssertEqual(.pending, task.state, "Test interrupt on pending item")

        tq.list.first?.taskDefinition.state = .executing
        XCTAssertEqual(.executing, task.state, "Set state to executing for testing reason")

        tq.interrupt()
        XCTAssertEqual(.interrupted, task.state, "Test interrupt on executing item")
    }

    func testSpoolServerConnectorDisconnected() {
        let tq = TaskQueue(
            queueType: .outgoing,
            supportedTypes: [TaskDefinitionSendAbstractMessage.self],
            frameworkInjector: frameworkInjectorMock,
            renewFrameworkInjector: false
        )

        tq.spool()

        DDLog.flushLog()
        XCTAssertTrue(ddLoggerMock.exists(message: "Task queue spool interrupt, because not logged in to server"))
    }

    func testSpoolTaskDefinitionSendAbstractMessage() {
        let expectedReceiver = "ECHOECHO"

        databasePreparer.save {
            databasePreparer.createContact(
                publicKey: MockData.generatePublicKey(),
                identity: expectedReceiver,
                verificationLevel: 0
            )
        }

        let serverConnectorMock = ServerConnectorMock(connectionState: .loggedIn)
        let myIdentityStoreMock = MyIdentityStoreMock()
        let frameworkInjectorMock = BusinessInjectorMock(
            backgroundEntityManager: EntityManager(databaseContext: databaseBackgroundCnx),
            entityManager: EntityManager(databaseContext: databaseMainCnx),
            myIdentityStore: myIdentityStoreMock,
            serverConnector: serverConnectorMock
        )

        let tq = TaskQueue(
            queueType: .outgoing,
            supportedTypes: [TaskDefinitionSendAbstractMessage.self],
            frameworkInjector: frameworkInjectorMock,
            renewFrameworkInjector: false
        )

        let message = BoxTextMessage()
        message.fromIdentity = myIdentityStoreMock.identity
        message.toIdentity = expectedReceiver
        message.text = "test 123"

        let expec = expectation(description: "spool")

        let task = TaskDefinitionSendAbstractMessage(message: message, isPersistent: false)
        try? tq.enqueue(task: task) { _, error in
            XCTAssertNil(error)
            DDLog.flushLog()
            expec.fulfill()
        }
        
        tq.spool()

        waitForExpectations(timeout: 6) { error in
            XCTAssertNil(error)
            XCTAssertEqual(serverConnectorMock.sendMessageCalls.count, 1)
            XCTAssertTrue(
                self.ddLoggerMock
                    .exists(
                        message: "<TaskDefinitionSendAbstractMessage (type: text; id: \(message.messageID.hexString))> done"
                    )
            )
        }
    }

    func testSpoolTaskDefinitionReceiveMessageProcessingFailedWithRetry() {
        let expectedReceiver = "ECHOECHO"
        let expectedError = NSError(domain: "Test domain", code: 1, userInfo: nil)

        databasePreparer.createContact(
            publicKey: MockData.generatePublicKey(),
            identity: expectedReceiver,
            verificationLevel: 0
        )

        let serverConnectorMock = ServerConnectorMock(connectionState: .loggedIn)
        let messageProcessorMock = MessageProcessorMock()
        messageProcessorMock.error = expectedError
        let frameworkInjectorMock = BusinessInjectorMock(
            backgroundEntityManager: EntityManager(databaseContext: databaseBackgroundCnx),
            entityManager: EntityManager(databaseContext: databaseMainCnx),
            serverConnector: serverConnectorMock,
            messageProcessor: messageProcessorMock
        )

        // 2 tests with: retry / processIncomingMessageCalls / completedProcessingMessageCalls / retryCount
        for test in [[false, 1, 0, 0], [true, 2, 0, 1]] {
            // Reset mocks first
            ddLoggerMock.logMessages.removeAll()
            messageProcessorMock.processIncomingMessageCalls.removeAll()
            serverConnectorMock.completedProcessingMessageCalls.removeAll()

            let tq = TaskQueue(
                queueType: .incoming,
                supportedTypes: [TaskDefinitionReceiveMessage.self],
                frameworkInjector: frameworkInjectorMock,
                renewFrameworkInjector: false
            )

            let message = BoxedMessage()
            message.messageID = MockData.generateMessageID()
            message.fromIdentity = "TESTER01"
            message.toIdentity = expectedReceiver

            let expec = expectation(description: "spool")

            let task = TaskDefinitionReceiveMessage(
                message: message,
                receivedAfterInitialQueueSend: true,
                maxBytesToDecrypt: 0,
                timeoutDownloadThumbnail: 0
            )
            task.retry = test[0] as! Bool

            try? tq.enqueue(task: task) { _, error in
                XCTAssertNotNil(error)
                DDLog.flushLog()
                expec.fulfill()
            }
            
            tq.spool()

            waitForExpectations(timeout: 6) { error in
                XCTAssertNil(error)
                XCTAssertEqual(tq.list.count, 0, "Task must be removed from incoming queue, if it failed")
                XCTAssertEqual(messageProcessorMock.processIncomingMessageCalls.count, test[1] as! Int)
                XCTAssertEqual(serverConnectorMock.completedProcessingMessageCalls.count, test[2] as! Int)
                XCTAssertEqual(task.retryCount, test[3] as! Int)
                XCTAssertTrue(
                    self.ddLoggerMock
                        .exists(
                            message: "<TaskDefinitionReceiveMessage (type: BoxedMessage; id: \(message.messageID.hexString))> failed Error Domain=\(expectedError.domain) Code=\(expectedError.code) \"(null)\""
                        )
                )
                if task.retry {
                    XCTAssertTrue(
                        self.ddLoggerMock
                            .exists(
                                message: "Retry of <TaskDefinitionReceiveMessage (type: BoxedMessage; id: \(message.messageID.hexString))> after execution failing"
                            )
                    )
                }
                else {
                    XCTAssertFalse(
                        self.ddLoggerMock
                            .exists(
                                message: "Retry of <TaskDefinitionReceiveMessage (type: BoxedMessage; id: \(message.messageID.hexString))> after execution failing"
                            )
                    )
                }
            }
        }
    }
    
    func testSpoolTaskDefinitionSendAbstractMessageReflectFailedWithRetry() {
        let expectedReceiver = "ECHOECHO"

        let serverConnectorMock = ServerConnectorMock(connectionState: .loggedIn)
        let frameworkInjectorMock = BusinessInjectorMock(
            backgroundEntityManager: EntityManager(databaseContext: databaseBackgroundCnx),
            entityManager: EntityManager(databaseContext: databaseMainCnx),
            serverConnector: serverConnectorMock
        )

        // 2 tests with: retry / sendMessageCalls / retryCount
        for test in [[false, 0, 0], [true, 0, 1]] {
            // Reset mocks first
            ddLoggerMock.logMessages.removeAll()
            serverConnectorMock.sendMessageCalls.removeAll()

            let tq = TaskQueue(
                queueType: .outgoing,
                supportedTypes: [TaskDefinitionSendAbstractMessage.self],
                frameworkInjector: frameworkInjectorMock,
                renewFrameworkInjector: false
            )

            let message = BoxTextMessage()
            message.fromIdentity = "TESTER01"
            message.toIdentity = expectedReceiver
            message.text = "test 123"

            let expec = expectation(description: "spool")

            let task = TaskDefinitionSendAbstractMessage(message: message, isPersistent: false)
            task.retry = test[0] as! Bool

            try? tq.enqueue(task: task) { _, error in
                XCTAssertNotNil(error)
                DDLog.flushLog()
                expec.fulfill()
            }
            
            tq.spool()

            waitForExpectations(timeout: 6) { error in
                XCTAssertNil(error)
                XCTAssertEqual(tq.list.count, 1, "Task must not removed from outgoing queue, if it failed")
                XCTAssertEqual(serverConnectorMock.sendMessageCalls.count, test[1] as! Int)
                XCTAssertEqual(task.retryCount, test[2] as! Int)
                XCTAssertTrue(
                    self.ddLoggerMock
                        .exists(
                            message: "<TaskDefinitionSendAbstractMessage (type: text; id: \(message.messageID.hexString))> failed sendMessageFailed(message: \"Contact not found for identity Optional(\\\"\(expectedReceiver)\\\") ((type: text; id: \(message.messageID.hexString)))\")"
                        )
                )
                if task.retry {
                    XCTAssertTrue(
                        self.ddLoggerMock
                            .exists(
                                message: "Retry of <TaskDefinitionSendAbstractMessage (type: text; id: \(message.messageID.hexString))> after execution failing"
                            )
                    )
                }
                else {
                    XCTAssertFalse(
                        self.ddLoggerMock
                            .exists(
                                message: "Retry of <TaskDefinitionSendAbstractMessage> after execution failing"
                            )
                    )
                }
            }
        }
    }
    
    func testSpoolMultiDeviceNotActivated() {
        let serverConnectorMock = ServerConnectorMock(connectionState: .loggedIn)
        let frameworkInjectorMock = BusinessInjectorMock(
            backgroundEntityManager: EntityManager(databaseContext: databaseBackgroundCnx),
            entityManager: EntityManager(databaseContext: databaseMainCnx),
            serverConnector: serverConnectorMock
        )

        let tq = TaskQueue(
            queueType: .outgoing,
            supportedTypes: [TaskDefinitionDeleteContactSync.self],
            frameworkInjector: frameworkInjectorMock,
            renewFrameworkInjector: false
        )

        let expec = expectation(description: "spool")

        let task = TaskDefinitionDeleteContactSync(contacts: ["ECHOECHO"])

        try? tq.enqueue(task: task) { _, error in
            XCTAssertNotNil(error)
            expec.fulfill()
        }

        tq.spool()

        waitForExpectations(timeout: 6) { error in
            XCTAssertNil(error)
            XCTAssertEqual(tq.list.count, 1)
            XCTAssertEqual(task.retryCount, 1)
            XCTAssertTrue(
                self.ddLoggerMock
                    .exists(
                        message: "<TaskDefinitionDeleteContactSync> failed \(TaskExecutionError.multiDeviceNotRegistered)"
                    )
            )
        }
    }

    func testSpoolTaskDefinitionDeleteContactSyncReflectFailedWithRetry() {
        let serverConnectorMock = ServerConnectorMock(
            connectionState: .loggedIn,
            deviceID: MockData.deviceID,
            deviceGroupKeys: MockData.deviceGroupKeys
        )
        let frameworkInjectorMock = BusinessInjectorMock(
            backgroundEntityManager: EntityManager(databaseContext: databaseBackgroundCnx),
            entityManager: EntityManager(databaseContext: databaseMainCnx),
            userSettings: UserSettingsMock(enableMultiDevice: true),
            serverConnector: serverConnectorMock
        )

        // 2 tests with: retry / reflectMessageCalls / retryCount
        for test in [[false, 1, 0], [true, 2, 1]] {
            // Reset mocks first
            ddLoggerMock.logMessages.removeAll()
            serverConnectorMock.reflectMessageCalls.removeAll()

            let tq = TaskQueue(
                queueType: .outgoing,
                supportedTypes: [TaskDefinitionDeleteContactSync.self],
                frameworkInjector: frameworkInjectorMock,
                renewFrameworkInjector: false
            )

            let expec = expectation(description: "spool")

            let task = TaskDefinitionDeleteContactSync(contacts: ["ECHOECHO"])
            task.retry = test[0] as! Bool

            try? tq.enqueue(task: task) { _, error in
                XCTAssertNotNil(error)
                DDLog.flushLog()
                expec.fulfill()
            }
            
            tq.spool()

            waitForExpectations(timeout: 10) { error in
                XCTAssertNil(error)
                XCTAssertEqual(tq.list.count, 1)
                XCTAssertEqual(serverConnectorMock.reflectMessageCalls.count, test[1] as! Int)
                XCTAssertEqual(task.retryCount, test[2] as! Int)
                XCTAssertTrue(
                    self.ddLoggerMock
                        .exists(
                            message: "<TaskDefinitionDeleteContactSync> failed reflectMessageFailed(message: Optional(\"type: lock\"))"
                        )
                )
                if task.retry {
                    XCTAssertTrue(
                        self.ddLoggerMock
                            .exists(message: "Retry of <TaskDefinitionDeleteContactSync> after execution failing")
                    )
                }
                else {
                    XCTAssertFalse(
                        self.ddLoggerMock
                            .exists(message: "Retry of task <TaskDefinitionDeleteContactSync> after execution failing")
                    )
                }
            }
        }
    }

    func testEncodeDecodeWithAllTaskTypes() throws {
        var expectedContact: ContactEntity!
        var expectedConversation: Conversation!
        databasePreparer.save {
            expectedContact = databasePreparer.createContact(
                publicKey: MockData.generatePublicKey(),
                identity: "ECHOECHO",
                verificationLevel: 0
            )
            expectedConversation = databasePreparer.createConversation(
                typing: false,
                unreadMessageCount: 0,
                visibility: .default
            ) { conversation in
                conversation.contact = expectedContact
            }
        }

        let tq = TaskQueue(
            queueType: .outgoing,
            supportedTypes: [
                TaskDefinitionGroupDissolve.self,
                TaskDefinitionSendAbstractMessage.self,
                TaskDefinitionSendBallotVoteMessage.self,
                TaskDefinitionSendBaseMessage.self,
                TaskDefinitionSendDeliveryReceiptsMessage.self,
                TaskDefinitionSendLocationMessage.self,
                TaskDefinitionSendVideoMessage.self,
                TaskDefinitionSendGroupCreateMessage.self,
                TaskDefinitionSendGroupDeletePhotoMessage.self,
                TaskDefinitionSendGroupLeaveMessage.self,
                TaskDefinitionSendGroupRenameMessage.self,
                TaskDefinitionSendGroupSetPhotoMessage.self,
                TaskDefinitionSendGroupDeliveryReceiptsMessage.self,
                TaskDefinitionDeleteContactSync.self,
                TaskDefinitionProfileSync.self,
                TaskDefinitionUpdateContactSync.self,
                TaskDefinitionSettingsSync.self,
                TaskDefinitionReceiveMessage.self,
                TaskDefinitionReceiveReflectedMessage.self,
            ],
            frameworkInjector: frameworkInjectorMock,
            renewFrameworkInjector: false
        )

        // Add TaskDefinitionGroupDissolve
        let expectedGroupDissolveGroupID = MockData.generateGroupID()
        let expectedGroupDissolveGroupCreator = "CREATOR01"
        let expectedGroupDissolveToMember = "MEMBER07"

        var groupEntity: GroupEntity!
        var conversation: Conversation!
        databasePreparer.save {
            groupEntity = databasePreparer.createGroupEntity(
                groupID: expectedGroupDissolveGroupID,
                groupCreator: expectedGroupDissolveGroupCreator
            )
            conversation = databasePreparer.createConversation(
                typing: false,
                unreadMessageCount: 0,
                visibility: .default,
                complete: nil
            )
            conversation.contact = databasePreparer.createContact(
                publicKey: MockData.generatePublicKey(),
                identity: expectedGroupDissolveGroupCreator,
                verificationLevel: 0
            )
        }

        let group = Group(
            myIdentityStore: frameworkInjectorMock.myIdentityStore,
            userSettings: frameworkInjectorMock.userSettings,
            groupEntity: groupEntity,
            conversation: conversation,
            lastSyncRequest: nil
        )

        let taskGroupDissolve = TaskDefinitionGroupDissolve(group: group)
        taskGroupDissolve.toMembers = [expectedGroupDissolveToMember]
        try! tq.enqueue(task: taskGroupDissolve, completionHandler: nil)

        // Add TaskDefinitionSendAbstractMessage
        let expectedAbstractMessageID = MockData.generateMessageID()
        let expectedAbstractText = "test 123!!!"

        let expectedAbstractMessage = BoxTextMessage()
        expectedAbstractMessage.messageID = expectedAbstractMessageID
        expectedAbstractMessage.text = expectedAbstractText
        expectedAbstractMessage.toIdentity = "TESTERID"

        let taskAbstract = TaskDefinitionSendAbstractMessage(message: expectedAbstractMessage)
        try! tq.enqueue(task: taskAbstract, completionHandler: nil)

        // Add TaskDefinitionSendBallotVoteMessage
        let expectedBallotVoteBallotID = MockData.generateBallotID()
        var expectedBallotVoteBallot: Ballot!
        databasePreparer.save {
            expectedBallotVoteBallot = databasePreparer.createBallotMessage(
                conversation: expectedConversation,
                ballotID: expectedBallotVoteBallotID
            )
        }

        let taskBallotVote = TaskDefinitionSendBallotVoteMessage(
            ballot: expectedBallotVoteBallot,
            group: nil,
            sendContactProfilePicture: false
        )
        try! tq.enqueue(task: taskBallotVote, completionHandler: nil)

        // Add TaskDefinitionSendBaseMessage
        let expectedBaseGroupID = MockData.generateGroupID()
        let expectedBaseGroupCreatorIdentity = "ADMIN007"
        let expectedBaseGroupName = "Test group name"
        let expectedBaseAllGroupMembers: Set<String> = ["MEMBER01", "MEMBER01", "MEMBER01"]
        let expectedBaseIsNoteGroup = false
        let expectedBaseMessageID = MockData.generateMessageID()
        var expectedBaseMessage: TextMessage!
        databasePreparer.save {
            expectedBaseMessage = databasePreparer.createTextMessage(
                conversation: expectedConversation,
                text: "nil",
                date: Date(),
                delivered: false,
                id: expectedBaseMessageID,
                isOwn: true,
                read: false,
                sent: false,
                userack: false,
                sender: expectedContact,
                remoteSentDate: nil
            )
        }

        let taskBase = TaskDefinitionSendBaseMessage(
            message: expectedBaseMessage,
            group: nil,
            sendContactProfilePicture: false
        )
        taskBase.groupID = expectedBaseGroupID
        taskBase.groupCreatorIdentity = expectedBaseGroupCreatorIdentity
        taskBase.groupName = expectedBaseGroupName
        taskBase.allGroupMembers = expectedBaseAllGroupMembers
        taskBase.isNoteGroup = expectedBaseIsNoteGroup
        try! tq.enqueue(task: taskBase, completionHandler: nil)

        // Add TaskDefinitionSendGroupDeliveryReceiptMessage
        let expectedReceiptFromIdentity = "CONTACT1"
        let expectedReceiptToIdentity = "CONTACT2"
        let expectedReceiptType: ReceiptType = .read
        let expectedReceiptMessageIDs = [
            MockData.generateMessageID(),
            MockData.generateMessageID(),
        ]
        let expectedReceiptReadDates = [
            Date(),
            Date(),
        ]

        let taskDeliveryReceipt = TaskDefinitionSendDeliveryReceiptsMessage(
            fromIdentity: expectedReceiptFromIdentity,
            toIdentity: expectedReceiptToIdentity,
            receiptType: expectedReceiptType,
            receiptMessageIDs: expectedReceiptMessageIDs,
            receiptReadDates: expectedReceiptReadDates,
            excludeFromSending: [Data]()
        )

        try! tq.enqueue(task: taskDeliveryReceipt, completionHandler: nil)

        // Add TaskDefinitionSendLocationMessage
        let expectedLocationMessageID = MockData.generateMessageID()
        let expectedLocationPoiAddress = "poi address"
        var expectedLocationMessage: LocationMessage!
        databasePreparer.save {
            expectedLocationMessage = databasePreparer.createLocationMessage(
                conversation: expectedConversation,
                accuracy: 0.1,
                latitude: 0.1,
                longitude: 0.1,
                poiName: "poi name",
                id: expectedLocationMessageID,
                sender: expectedContact
            )
        }

        let taskLocation = TaskDefinitionSendLocationMessage(
            poiAddress: expectedLocationPoiAddress,
            message: expectedLocationMessage,
            sendContactProfilePicture: false
        )
        try! tq.enqueue(task: taskLocation, completionHandler: nil)

        // Add TaskDefinitionSendVideoMessage
        let expectedVideoMessageID = MockData.generateMessageID()
        var expectedVideoMessage: VideoMessageEntity!
        databasePreparer.save {
            let imageData = databasePreparer.createImageData(data: Data([1]), height: 1, width: 1)
            let videoData = databasePreparer.createVideoData(data: Data([2]))
            expectedVideoMessage = databasePreparer.createVideoMessageEntity(
                conversation: expectedConversation,
                thumbnail: imageData,
                videoData: videoData,
                date: Date(),
                complete: { msg in
                    msg.delivered = 1
                    msg.id = expectedVideoMessageID
                    msg.isOwn = true
                    msg.read = true
                    msg.sent = true
                    msg.userack = false
                    msg.duration = 10
                    msg.remoteSentDate = Date()
                }
            )
        }

        let taskVideo = TaskDefinitionSendVideoMessage(
            thumbnailBlobID: nil,
            thumbnailSize: nil,
            message: expectedVideoMessage,
            sendContactProfilePicture: false
        )
        try! tq.enqueue(task: taskVideo, completionHandler: nil)

        // Add TaskDefinitionSendGroupCreateMessage
        let expectedMembers = ["TESTER01", "TESTER03"]

        let taskGroupCreate = TaskDefinitionSendGroupCreateMessage(
            group: nil,
            to: expectedMembers,
            members: Set(expectedMembers),
            sendContactProfilePicture: false
        )

        try! tq.enqueue(task: taskGroupCreate, completionHandler: nil)

        // Add TaskDefinitionSendGroupLeaveMessage
        let expectedFromMember = "TESTER01"
        let expectedToMembers = ["TESTER02", "TESTER03"]

        let taskGroupLeave = TaskDefinitionSendGroupLeaveMessage(sendContactProfilePicture: false)
        taskGroupLeave.fromMember = expectedFromMember
        taskGroupLeave.toMembers = expectedToMembers
        try! tq.enqueue(task: taskGroupLeave, completionHandler: nil)

        // Add TaskDefinitionSendGroupRenameMessage
        let expectedGroupRenameName = "group name 123!!!"

        let taskGroupRename = TaskDefinitionSendGroupRenameMessage(
            group: nil,
            from: expectedFromMember,
            to: expectedToMembers,
            newName: expectedGroupRenameName,
            sendContactProfilePicture: false
        )

        try! tq.enqueue(task: taskGroupRename, completionHandler: nil)
        
        // Add TaskDefinitionSendGroupSetPhotoMessage
        let expectedGroupSetPhotoSize: UInt32 = 10
        let expectedGroupSetPhotoBlobID = MockData.generateBlobID()
        let expectedGroupSetPhotoEncryptionKey = MockData.generateBlobEncryptionKey()
        
        let taskGroupSetPhoto = TaskDefinitionSendGroupSetPhotoMessage(
            group: nil,
            from: expectedFromMember,
            to: expectedToMembers,
            size: expectedGroupSetPhotoSize,
            blobID: expectedGroupSetPhotoBlobID,
            encryptionKey: expectedGroupSetPhotoEncryptionKey,
            sendContactProfilePicture: false
        )
        
        try! tq.enqueue(task: taskGroupSetPhoto, completionHandler: nil)
        
        // Add TaskDefinitionSendGroupDeletePhotoMessage
        let taskGroupDeletePhoto = TaskDefinitionSendGroupDeletePhotoMessage(
            group: nil,
            from: expectedFromMember,
            to: expectedToMembers,
            sendContactProfilePicture: false
        )

        try! tq.enqueue(task: taskGroupDeletePhoto, completionHandler: nil)
        
        // Add TaskDefinitionSendGroupDeliveryReceiptMessage
        let expectedGroupReceiptType: ReceiptType = .ack
        let expectedGroupReceiptMessageIDs = [
            MockData.generateMessageID(),
            MockData.generateMessageID(),
        ]
        
        let taskGroupDeliveryReceipt = TaskDefinitionSendGroupDeliveryReceiptsMessage(
            group: nil,
            from: expectedFromMember,
            to: expectedToMembers,
            receiptType: expectedGroupReceiptType,
            receiptMessageIDs: expectedGroupReceiptMessageIDs,
            receiptReadDates: [Date]()
        )
        
        try! tq.enqueue(task: taskGroupDeliveryReceipt, completionHandler: nil)

        // Add TaskDefintionDeleteContactSync
        let deleteableContacts = ["ECHOECHO"]
        let taskDeleteContactSync = TaskDefinitionDeleteContactSync(contacts: deleteableContacts)
        try! tq.enqueue(task: taskDeleteContactSync, completionHandler: nil)
        
        // Add TaskDefinitionProfileSync
        var syncUserProfile = Sync_UserProfile()
        syncUserProfile.profilePicture.updated = Common_Image()
        syncUserProfile.nickname = "Test Case"
        var contacts = Common_Identities()
        contacts.identities = ["ECHOECHO", "*SUPPORT"]
        syncUserProfile.profilePictureShareWith.policy = .allowList(contacts)
        var linkPhoneNumber = Sync_UserProfile.IdentityLinks.IdentityLink()
        linkPhoneNumber.phoneNumber = "+41 000 00 00"
        syncUserProfile.identityLinks.links.append(linkPhoneNumber)
        var linkEmail = Sync_UserProfile.IdentityLinks.IdentityLink()
        linkEmail.email = "test@test.test"
        syncUserProfile.identityLinks.links.append(linkEmail)

        let profileImage = BytesUtility.generateRandomBytes(length: 512)!

        let taskProfileSync = TaskDefinitionProfileSync(
            syncUserProfile: syncUserProfile,
            profileImage: profileImage,
            linkMobileNoPending: false,
            linkEmailPending: false
        )
        try! tq.enqueue(task: taskProfileSync, completionHandler: nil)

        // Add TaskDefinitionUpdateContactSync
        var syncContact1 = Sync_Contact()
        syncContact1.identity = "ECHOECHO"
        let contact1 = DeltaSyncContact(syncContact: syncContact1, syncAction: .update)

        var syncContact2 = Sync_Contact()
        syncContact2.identity = "ECHOECHO"
        var contact2 = DeltaSyncContact(syncContact: syncContact1, syncAction: .update)
        contact2.image = Data([1])

        let updateableContacts = [contact1, contact2, contact1]

        let taskUpdateContactSync = TaskDefinitionUpdateContactSync(deltaSyncContacts: updateableContacts)
        try! tq.enqueue(task: taskUpdateContactSync, completionHandler: nil)

        // Add TaskDefinitionSettingsSync
        var syncSettings = Sync_Settings()
        syncSettings.contactSyncPolicy = .sync
        syncSettings.readReceiptPolicy = .sendReadReceipt
        syncSettings.unknownContactPolicy = .blockUnknown
        syncSettings.typingIndicatorPolicy = .sendTypingIndicator
        syncSettings.callPolicy = .allowCall
        syncSettings.callConnectionPolicy = .requireRelay
        syncSettings.blockedIdentities.identities = ["ECHOECHO"]
        syncSettings.excludeFromSyncIdentities.identities = ["ECHOECHO"]

        let taskSettingsSync = TaskDefinitionSettingsSync(syncSettings: syncSettings)
        try! tq.enqueue(task: taskSettingsSync, completionHandler: nil)
        
        // Add TaskDefinitionReceiveMessage
        let taskReceiveMessage = TaskDefinitionReceiveMessage(
            message: BoxedMessage(),
            receivedAfterInitialQueueSend: true,
            maxBytesToDecrypt: 0,
            timeoutDownloadThumbnail: 0
        )
        try! tq.enqueue(task: taskReceiveMessage, completionHandler: nil)

        // Add TaskDefinitionReceiveReflectedMessage
        let expectedReflectedAt = Date()
        let taskReceiveReflectedMessage = TaskDefinitionReceiveReflectedMessage(
            reflectID: MockData.generateReflectID(),
            reflectedEnvelope: D2d_Envelope(),
            reflectedAt: expectedReflectedAt,
            receivedAfterInitialQueueSend: false,
            maxBytesToDecrypt: 20,
            timeoutDownloadThumbnail: 30
        )
        try! tq.enqueue(task: taskReceiveReflectedMessage, completionHandler: nil)
        
        let expectedItemCount = 19
        guard tq.list.count == expectedItemCount else {
            XCTFail("TaskList has wrong number of items. Expected \(expectedItemCount) but was \(tq.list.count)")
            return
        }

        // Check none-persistent tasks
        if let task = tq.list[14].taskDefinition as? TaskDefinitionProfileSync {
            XCTAssertEqual(TaskExecutionState.pending, task.state)
            XCTAssertEqual(task.scope, .userProfileSync)
            XCTAssertEqual(task.profileImage, profileImage)
            XCTAssertEqual(task.syncUserProfile.nickname, syncUserProfile.nickname)
            XCTAssertEqual(task.syncUserProfile.profilePictureShareWith.policy, .allowList(contacts))
            XCTAssertEqual(task.syncUserProfile.identityLinks.links, syncUserProfile.identityLinks.links)
            XCTAssertEqual(task.linkMobileNoPending, false)
            XCTAssertEqual(task.linkEmailPending, false)
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[16].taskDefinition as? TaskDefinitionSettingsSync {
            XCTAssertEqual(TaskExecutionState.pending, task.state)
            XCTAssertEqual(task.scope, .settingsSync)
            XCTAssertEqual(task.syncSettings.contactSyncPolicy, .sync)
            XCTAssertEqual(task.syncSettings.readReceiptPolicy, .sendReadReceipt)
            XCTAssertEqual(task.syncSettings.unknownContactPolicy, .blockUnknown)
            XCTAssertEqual(task.syncSettings.typingIndicatorPolicy, .sendTypingIndicator)
            XCTAssertEqual(task.syncSettings.callPolicy, .allowCall)
            XCTAssertEqual(task.syncSettings.callConnectionPolicy, .requireRelay)
            XCTAssertEqual(task.syncSettings.blockedIdentities.identities, ["ECHOECHO"])
            XCTAssertEqual(task.syncSettings.excludeFromSyncIdentities.identities, ["ECHOECHO"])
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[17].taskDefinition as? TaskDefinitionReceiveMessage {
            XCTAssertEqual(TaskExecutionState.pending, task.state)
            XCTAssertNotNil(task.message)
            XCTAssertEqual(task.receivedAfterInitialQueueSend, true)
            XCTAssertEqual(task.maxBytesToDecrypt, 0)
            XCTAssertEqual(task.timeoutDownloadThumbnail, 0)
            XCTAssertFalse(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[18].taskDefinition as? TaskDefinitionReceiveReflectedMessage {
            XCTAssertEqual(TaskExecutionState.pending, task.state)
            XCTAssertNotNil(task.reflectedEnvelope)
            XCTAssertEqual(task.receivedAfterInitialQueueSend, false)
            XCTAssertEqual(task.reflectedAt, expectedReflectedAt)
            XCTAssertEqual(task.maxBytesToDecrypt, 20)
            XCTAssertEqual(task.timeoutDownloadThumbnail, 30)
            XCTAssertFalse(task.retry)
        }
        else {
            XCTFail()
        }

        // Encode queue
        guard let data = tq.encode() else {
            XCTFail("Could not encode queue")
            return
        }
        
        // Remove all items
        tq.removeAll()

        // Decode queue
        tq.decode(data)

        // Check persistent tasks
        let expectedItemCountAfterDecode = 15
        guard tq.list.count == expectedItemCountAfterDecode else {
            XCTFail(
                "TaskList has wrong number of items. Expected \(expectedItemCountAfterDecode) but was \(tq.list.count)"
            )
            return
        }

        if let task = tq.list[0].taskDefinition as? TaskDefinitionGroupDissolve {
            XCTAssertEqual(expectedGroupDissolveGroupID, task.groupID)
            XCTAssertEqual(expectedGroupDissolveGroupCreator, task.groupCreatorIdentity)
            XCTAssertEqual(1, task.toMembers.count)
            XCTAssertTrue(task.toMembers.contains(expectedGroupDissolveToMember))
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[1].taskDefinition as? TaskDefinitionSendAbstractMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertTrue(expectedAbstractMessageID.elementsEqual(task.message.messageID))
            XCTAssertEqual(expectedAbstractText, (task.message as! BoxTextMessage).text)
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[2].taskDefinition as? TaskDefinitionSendBallotVoteMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertTrue(expectedBallotVoteBallotID.elementsEqual(task.ballotID))
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[3].taskDefinition as? TaskDefinitionSendBaseMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertEqual(expectedBaseGroupID, try XCTUnwrap(task.groupID))
            XCTAssertEqual(expectedBaseGroupCreatorIdentity, task.groupCreatorIdentity)
            XCTAssertEqual(expectedBaseGroupName, task.groupName)
            XCTAssertEqual(expectedBaseAllGroupMembers, try XCTUnwrap(task.allGroupMembers))
            XCTAssertEqual(expectedBaseIsNoteGroup, task.isNoteGroup)
            XCTAssertTrue(expectedBaseMessageID.elementsEqual(task.messageID))
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[4].taskDefinition as? TaskDefinitionSendDeliveryReceiptsMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertEqual(expectedReceiptFromIdentity, task.fromIdentity)
            XCTAssertEqual(expectedReceiptToIdentity, task.toIdentity)
            XCTAssertEqual(expectedReceiptType, task.receiptType)
            XCTAssertEqual(expectedReceiptMessageIDs, task.receiptMessageIDs)
            XCTAssertEqual(expectedReceiptReadDates, task.receiptReadDates)
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[5].taskDefinition as? TaskDefinitionSendLocationMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertTrue(expectedLocationMessageID.elementsEqual(task.messageID))
            XCTAssertEqual(expectedLocationPoiAddress, task.poiAddress)
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[6].taskDefinition as? TaskDefinitionSendVideoMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertTrue(expectedVideoMessageID.elementsEqual(task.messageID))
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[7].taskDefinition as? TaskDefinitionSendGroupCreateMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertEqual(Set(expectedMembers), task.members)
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[8].taskDefinition as? TaskDefinitionSendGroupLeaveMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertEqual(expectedFromMember, task.fromMember)
            XCTAssertEqual(expectedToMembers, task.toMembers)
            XCTAssertEqual(0, task.hiddenContacts.count)
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[9].taskDefinition as? TaskDefinitionSendGroupRenameMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertEqual(expectedFromMember, task.fromMember)
            XCTAssertEqual(expectedToMembers, task.toMembers)
            XCTAssertEqual(expectedGroupRenameName, task.name)
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[10].taskDefinition as? TaskDefinitionSendGroupSetPhotoMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertEqual(expectedFromMember, task.fromMember)
            XCTAssertEqual(expectedToMembers, task.toMembers)
            XCTAssertEqual(expectedGroupSetPhotoSize, task.size)
            XCTAssertTrue(expectedGroupSetPhotoBlobID.elementsEqual(taskGroupSetPhoto.blobID))
            XCTAssertTrue(expectedGroupSetPhotoEncryptionKey.elementsEqual(taskGroupSetPhoto.encryptionKey))
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }
        
        if let task = tq.list[11].taskDefinition as? TaskDefinitionSendGroupDeletePhotoMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertEqual(expectedFromMember, task.fromMember)
            XCTAssertEqual(expectedToMembers, task.toMembers)
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }
        
        if let task = tq.list[12].taskDefinition as? TaskDefinitionSendGroupDeliveryReceiptsMessage {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertEqual(expectedFromMember, task.fromMember)
            XCTAssertEqual(expectedToMembers, task.toMembers)
            XCTAssertEqual(expectedGroupReceiptType, task.receiptType)
            XCTAssertEqual(expectedGroupReceiptMessageIDs, task.receiptMessageIDs)
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[13].taskDefinition as? TaskDefinitionDeleteContactSync {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertEqual(task.scope, .contactSync)
            XCTAssertEqual(task.contacts, deleteableContacts)
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }

        if let task = tq.list[14].taskDefinition as? TaskDefinitionUpdateContactSync {
            XCTAssertEqual(.interrupted, task.state)
            XCTAssertEqual(task.scope, .contactSync)
            XCTAssertEqual(task.deltaSyncContacts.count, updateableContacts.count)
            XCTAssertEqual(
                task.deltaSyncContacts[0].syncContact.identity,
                updateableContacts[0].syncContact.identity
            )
            XCTAssertEqual(
                task.deltaSyncContacts[0].image,
                updateableContacts[0].image
            )
            XCTAssertEqual(
                task.deltaSyncContacts[1].syncContact.identity,
                updateableContacts[1].syncContact.identity
            )
            XCTAssertEqual(
                task.deltaSyncContacts[1].image,
                updateableContacts[1].image
            )
            XCTAssertEqual(
                task.deltaSyncContacts[2].syncContact.identity,
                updateableContacts[2].syncContact.identity
            )
            XCTAssertEqual(
                task.deltaSyncContacts[2].image,
                updateableContacts[2].image
            )
            XCTAssertTrue(task.retry)
        }
        else {
            XCTFail()
        }
    }
}
