//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022 Threema GmbH
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

import XCTest
@testable import ThreemaFramework

class BlobDataStateTests: XCTestCase {
    
    private var databasePreparer: DatabasePreparer!
    private var conversation: Conversation!

    override func setUpWithError() throws {
        AppGroup.setGroupID("group.ch.threema")
        
        let (_, managedObjectContext, _) = DatabasePersistentContext.devNullContext()
        
        databasePreparer = DatabasePreparer(context: managedObjectContext)
        databasePreparer.save {
            conversation = databasePreparer.createConversation(
                marked: false,
                typing: false,
                unreadMessageCount: 0,
                complete: nil
            )
        }
    }
    
    // MARK: - thumbnailState
    
    private func thumbnailTestImageData() -> ImageData {
        let testBundle = Bundle(for: BlobDataStateTests.self)
        let testImageURL = testBundle.url(forResource: "Bild-1-1-thumbnail", withExtension: "jpg")!
        let testImageData = try! Data(contentsOf: testImageURL)
        
        return databasePreparer.createImageData(
            data: testImageData,
            height: 512,
            width: 384
        )
    }
    
    // MARK: Incoming

    func testFileMessageThumbnailIncomingStateRemote() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                encryptionKey: BytesUtility.generateRandomBytes(length: Int(kBlobKeyLen))!,
                blobThumbnailID: BytesUtility.generateRandomBytes(length: ThreemaProtocol.blobIDLength)!,
                isOwn: false
            )
        }
        
        XCTAssertEqual(.incoming(.remote(error: nil)), fileMessageEntity.thumbnailState)
    }
    
    func testFileMessageThumbnailIncomingStateProcessed() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(conversation: conversation)
            fileMessageEntity.thumbnail = thumbnailTestImageData()
        }
        
        XCTAssertEqual(.incoming(.processed), fileMessageEntity.thumbnailState)
    }
    
    func testFileMessageThumbnailIncomingStateNoThumbnail() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(conversation: conversation)
        }
        
        XCTAssertEqual(.incoming(.noData(.noThumbnail)), fileMessageEntity.thumbnailState)
    }
    
    func testFileMessageThumbnailIncomingStateNoKeyFatalError() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                blobThumbnailID: BytesUtility.generateRandomBytes(length: ThreemaProtocol.blobIDLength)!
            )
        }
        
        XCTAssertEqual(.incoming(.fatalError(.noEncryptionKey)), fileMessageEntity.thumbnailState)
    }
    
    // MARK: Outgoing
    
    func testFileMessageThumbnailOutgoingStatePendingUploadNoError() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                progress: NSNumber(floatLiteral: 0),
                thumbnail: thumbnailTestImageData(),
                isOwn: true
            )
        }
        
        XCTAssertEqual(.outgoing(.pendingUpload(error: nil)), fileMessageEntity.thumbnailState)
    }
    
    func testFileMessageThumbnailOutgoingStatePendingUploadFailed() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                thumbnail: thumbnailTestImageData(),
                isOwn: true
            )
            fileMessageEntity.sendFailed = NSNumber(booleanLiteral: true)
        }
        
        XCTAssertEqual(.outgoing(.pendingUpload(error: .uploadFailed)), fileMessageEntity.thumbnailState)
    }
    
    func testFileMessageThumbnailOutgoingStatePendingUploadFailedWithExistingProgess() {
        var fileMessageEntity: FileMessageEntity!

        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                progress: NSNumber(floatLiteral: 0),
                thumbnail: thumbnailTestImageData(),
                isOwn: true
            )
            fileMessageEntity.sendFailed = NSNumber(booleanLiteral: true)
        }

        XCTAssertEqual(.outgoing(.pendingUpload(error: .uploadFailed)), fileMessageEntity.thumbnailState)
    }
    
    func testFileMessageThumbnailOutgoingStatePendingUploadNotUploading() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                thumbnail: thumbnailTestImageData(),
                isOwn: true
            )
        }
        
        XCTAssertEqual(.outgoing(.pendingUpload(error: .uploadFailed)), fileMessageEntity.thumbnailState)
    }

    func testFileMessageThumbnailOutgoingStateUploading() {
        var fileMessageEntity: FileMessageEntity!

        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                progress: NSNumber(floatLiteral: 0.8),
                thumbnail: thumbnailTestImageData(),
                isOwn: true
            )
        }

        XCTAssertEqual(.outgoing(.uploading), fileMessageEntity.thumbnailState)
    }
    
    func testFileMessageThumbnailOutgoingStateRemote() {
        var fileMessageEntity: FileMessageEntity!

        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                blobThumbnailID: BytesUtility.generateRandomBytes(length: ThreemaProtocol.blobIDLength)!,
                isOwn: true
            )
        }

        XCTAssertEqual(.outgoing(.remote), fileMessageEntity.thumbnailState)
    }
    
    func testFileMessageThumbnailOutgoingStateNoThumbnail() {
        var fileMessageEntity: FileMessageEntity!

        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                isOwn: true
            )
        }

        XCTAssertEqual(.outgoing(.noData(.noThumbnail)), fileMessageEntity.thumbnailState)
    }
    
    // MARK: - dataState
    
    // MARK: Incoming
    
    func testFileMessageDataIncomingStateRemote() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                encryptionKey: BytesUtility.generateRandomBytes(length: Int(kBlobKeyLen))!,
                blobID: BytesUtility.generateRandomBytes(length: ThreemaProtocol.blobIDLength)!
            )
        }
        
        XCTAssertEqual(.incoming(.remote(error: nil)), fileMessageEntity.dataState)
    }
    
    func testFileMessageDataIncomingStateRemoteWithError() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                encryptionKey: BytesUtility.generateRandomBytes(length: Int(kBlobKeyLen))!,
                blobID: BytesUtility.generateRandomBytes(length: ThreemaProtocol.blobIDLength)!
            )
            fileMessageEntity.sendFailed = NSNumber(booleanLiteral: true)
        }
        
        XCTAssertEqual(.incoming(.remote(error: .downloadFailed)), fileMessageEntity.dataState)
    }
    
    func testFileMessageDataIncomingStateDownloading() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                encryptionKey: BytesUtility.generateRandomBytes(length: Int(kBlobKeyLen))!,
                blobID: BytesUtility.generateRandomBytes(length: ThreemaProtocol.blobIDLength)!,
                progress: NSNumber(floatLiteral: 0.4)
            )
        }
        
        XCTAssertEqual(.incoming(.downloading), fileMessageEntity.dataState)
    }
    
    func testFileMessageDataIncomingStateProcessing() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                progress: NSNumber(floatLiteral: 1)
            )
        }
        
        XCTAssertEqual(.incoming(.processing), fileMessageEntity.dataState)
    }
    
    func testFileMessageDataIncomingStateProcessed() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            let fileData = databasePreparer.createFileData(data: Data(count: 10))
            
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                data: fileData
            )
        }
        
        XCTAssertEqual(.incoming(.processed), fileMessageEntity.dataState)
    }
    
    func testFileMessageDataIncomingStateFatalErrorNoEncryptionKey() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                blobID: BytesUtility.generateRandomBytes(length: ThreemaProtocol.blobIDLength)!
            )
        }
        
        XCTAssertEqual(.incoming(.fatalError(.noEncryptionKey)), fileMessageEntity.dataState)
    }
    
    func testFileMessageDataIncomingStateDeleted() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                encryptionKey: BytesUtility.generateRandomBytes(length: Int(kBlobKeyLen))!,
                blobThumbnailID: BytesUtility.generateRandomBytes(length: ThreemaProtocol.blobIDLength)!
            )
        }
        
        XCTAssertEqual(.incoming(.noData(.deleted)), fileMessageEntity.dataState)
    }
    
    // MARK: Outgoing
    
    func testFileMessageDataOutgoingPendingUpload() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            let fileData = databasePreparer.createFileData(data: Data(count: 10))

            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                progress: NSNumber(floatLiteral: 0),
                data: fileData,
                isOwn: true
            )
        }
        
        XCTAssertEqual(.outgoing(.pendingUpload(error: nil)), fileMessageEntity.dataState)
    }
    
    func testFileMessageDataOutgoingPendingUploadNotUploading() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            let fileData = databasePreparer.createFileData(data: Data(count: 10))

            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                data: fileData,
                isOwn: true
            )
        }
        
        XCTAssertEqual(.outgoing(.pendingUpload(error: .uploadFailed)), fileMessageEntity.dataState)
    }
    
    func testFileMessageDataOutgoingPendingUploadFailed() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            let fileData = databasePreparer.createFileData(data: Data(count: 10))

            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                progress: NSNumber(floatLiteral: 0),
                data: fileData,
                isOwn: true
            )
            fileMessageEntity.sendFailed = NSNumber(booleanLiteral: true)
        }
        
        XCTAssertEqual(.outgoing(.pendingUpload(error: .uploadFailed)), fileMessageEntity.dataState)
    }
    
    func testFileMessageDataOutgoingUploading() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            let fileData = databasePreparer.createFileData(data: Data(count: 10))

            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                progress: NSNumber(floatLiteral: 0.8),
                data: fileData,
                isOwn: true
            )
        }
        
        XCTAssertEqual(.outgoing(.uploading), fileMessageEntity.dataState)
    }
    
    func testFileMessageDataOutgoingStateRemote() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                encryptionKey: BytesUtility.generateRandomBytes(length: Int(kBlobKeyLen))!,
                blobID: BytesUtility.generateRandomBytes(length: ThreemaProtocol.blobIDLength)!,
                isOwn: true
            )
        }
        
        XCTAssertEqual(.outgoing(.remote), fileMessageEntity.dataState)
    }
    
    func testFileMessageDataOutgoingDeleted() {
        var fileMessageEntity: FileMessageEntity!
        
        databasePreparer.save {
            fileMessageEntity = databasePreparer.createFileMessageEntity(
                conversation: conversation,
                isOwn: true
            )
        }
        
        XCTAssertEqual(.outgoing(.noData(.deleted)), fileMessageEntity.dataState)
    }
}
