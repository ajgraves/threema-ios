//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2024 Threema GmbH
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
import ThreemaFramework

protocol AudioMediaManagerProtocol: AnyObject {
    associatedtype FileUtil: FileUtilityProtocol
    
    /// Removes the files at the specified URLs from the filesystem.
    /// This operation is performed on a background thread.
    /// - Parameter urls: An array of `URL` objects representing the files to be deleted.
    static func cleanupFiles(_ urls: [URL])
    
    /// Generates a temporary URL for an audio file with a unique name based on the current date and time.
    /// - Parameter namedFile: The base name for the audio file.
    /// - Returns: A `URL` object pointing to the temporary audio file location.
    static func tmpAudioURL(with namedFile: String) -> URL
    
    /// Concatenates multiple audio recordings and saves the result to a specified file.
    /// This function creates a composition of the provided audio URLs and then saves the composition
    /// to the destination URL.
    /// - Parameters:
    ///   - urls: An array of `URL` objects representing the audio files to be concatenated.
    ///   - audioFile: The destination `URL` where the final audio file will be saved.
    /// - Returns: A `Result` indicating the success or failure of the save operation.
    static func concatenateRecordingsAndSave(combine urls: [URL], to audioFile: URL) async
        -> Result<Void, VoiceMessageError>
    
    /// Saves an `AVAsset` to a specified URL.
    /// This function attempts to delete any existing file at the destination URL before initiating the export.
    /// It creates an `AVAssetExportSession` with the `AVAssetExportPresetAppleM4A` preset to export the asset.
    /// If the export session is not created or the export does not complete successfully, it returns a failure.
    /// - Parameters:
    ///   - asset: The `AVAsset` to be saved.
    ///   - url: The destination `URL` where the asset should be saved.
    /// - Returns: A `Result` indicating the success or failure of the save operation.
    static func save(_ asset: AVAsset, to url: URL) async -> Result<Void, VoiceMessageError>
    
    /// Moves a file from a given URL to the persistent directory (Documents).
    /// - Parameter url: The source URL of the file to be moved.
    /// - Returns: A result containing the new URL in the persistent directory on success, or a VoiceMessageError on
    /// failure.
    @discardableResult
    static func moveToPersistentDir(from url: URL) -> Result<URL, VoiceMessageError>
    
    /// Copies  a file from a given URL to the destination
    /// - Parameter source: The source URL of the file to be copied.
    /// - Parameter destination: The destination URL of the file to be copied.
    /// - Returns: A `Result` indicating the success or failure of the copy operation.
    @discardableResult
    static func copy(source: URL, destination: URL) -> Result<Void, VoiceMessageError>
}

extension AudioMediaManager {
    static func cleanupFiles(_ urls: [URL]) {
        DispatchQueue.global(qos: .background).async {
            urls.forEach(FileUtil.shared.delete)
        }
    }
    
    static func tmpAudioURL(with namedFile: String) -> URL {
        let fullFileName = "\(namedFile)-\(DateFormatter.getDateForExport(.now))"
        let url = FileUtil.shared.appTemporaryDirectory
            .appendingPathComponent(fullFileName)
            .appendingPathExtension(MEDIA_EXTENSION_AUDIO)

        DDLogInfo("new Tmp fileURL: \(url)")
        return url
    }
    
    static func copy(source: URL, destination: URL) -> Result<Void, VoiceMessageError> {
        FileUtil.shared.copy(source: source, destination: destination)
            ? .success(())
            : .failure(.fileOperationFailed)
    }
    
    static func moveToPersistentDir(from url: URL) -> Result<URL, VoiceMessageError> {
        guard let persistentDir = FileUtil.shared.appDocumentsDirectory
        else {
            return .failure(.fileOperationFailed)
        }
        return moveFile(
            from: url,
            to: persistentDir
                .appendingPathComponent(url.lastPathComponent)
        )
    }
    
    private static func moveFile(from url: URL, to newURL: URL) -> Result<URL, VoiceMessageError> {
        guard !FileUtil.shared.isExists(fileURL: newURL) else {
            return .success(newURL)
        }
        
        return FileUtil.shared.move(source: url, destination: newURL)
            ? .success(newURL)
            : .failure(.fileOperationFailed)
    }
}
