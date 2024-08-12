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

import CocoaLumberjackSwift
import Foundation
import PromiseKit

class TaskExecutionBlobTransaction: TaskExecutionTransaction {
    typealias BlobUpload = (uploadID: String, blob: Data)
    typealias BlobUploaded = (uploadID: String, blob: Data, blobID: Data)

    func uploadBlobs(blobs: [BlobUpload]) -> Promise<[BlobUploaded]> {
        let uploadBlobItems = blobs.compactMap { blob in
            UploadBlobItem(blobUploader: frameworkInjector.blobUploader, uploadID: blob.uploadID, blob: blob.blob)
        }

        return when(
            fulfilled: uploadBlobItems.compactMap { item in
                item.upload()
            }
        )
        .then { _ -> Promise<[BlobUploaded]> in
            // Return uploaded blob data with corresponding blob ID
            var result = [BlobUploaded]()

            for item in uploadBlobItems {
                if let blobID = item.blobID {
                    result.append((item.uploadID, item.blob, blobID))
                }
            }

            return Promise { seal in seal.fulfill(result) }
        }
    }

    private class UploadBlobItem {
        private let blobUploader: BlobUploaderProtocol
        let uploadID: String
        let blob: Data
        var blobID: Data?

        init(blobUploader: BlobUploaderProtocol, uploadID: String, blob: Data) {
            self.blobUploader = blobUploader
            self.uploadID = uploadID
            self.blob = blob
        }

        func upload() -> Promise<Void> {
            blobUploader.upload(data: blob, origin: .local)
                .then { blobID in
                    self.blobID = blobID
                    return Promise()
                }
        }
    }
}
