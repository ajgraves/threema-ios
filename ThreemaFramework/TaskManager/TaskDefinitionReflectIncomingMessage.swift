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

final class TaskDefinitionReflectIncomingMessage: TaskDefinition, TaskDefinitionSendMessageNonceProtocol {
    override func create(
        frameworkInjector: FrameworkInjectorProtocol,
        taskContext: TaskContextProtocol
    ) -> TaskExecutionProtocol {
        TaskExecutionReflectIncomingMessage(
            taskContext: taskContext,
            taskDefinition: self,
            frameworkInjector: frameworkInjector
        )
    }

    override func create(frameworkInjector: FrameworkInjectorProtocol) -> TaskExecutionProtocol {
        create(
            frameworkInjector: frameworkInjector,
            taskContext: TaskContext(
                logReflectMessageToMediator: .reflectOutgoingMessageToMediator,
                logReceiveMessageAckFromMediator: .receiveOutgoingMessageAckFromMediator,
                logSendMessageToChat: .sendOutgoingMessageToChat,
                logReceiveMessageAckFromChat: .receiveOutgoingMessageAckFromChat
            )
        )
    }

    override var description: String {
        "<\(type(of: self)) \(message.loggingDescription)>"
    }

    let message: AbstractMessage
    var nonces = TaskReceiverNonce()

    private enum CodingKeys: String, CodingKey {
        case message, messageData
    }

    private enum CodingError: Error {
        case messageDataMissing
    }

    @objc init(message: AbstractMessage, isPersistent: Bool) {
        self.message = message
        super.init(isPersistent: isPersistent)
        self.retry = false
    }

    @objc convenience init(message: AbstractMessage) {
        self.init(message: message, isPersistent: false)
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let messageData = try container.decode(Data.self, forKey: .messageData)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: messageData)
        guard let decodedMessage = try unarchiver.decodeTopLevelObject(
            of: AbstractMessage.self,
            forKey: CodingKeys.message.rawValue
        ) else {
            throw CodingError.messageDataMissing
        }
        self.message = decodedMessage

        let superDecoder = try container.superDecoder()
        try super.init(from: superDecoder)
    }

    override func encode(to encoder: Encoder) throws {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.encode(message, forKey: CodingKeys.message.rawValue)
        archiver.finishEncoding()

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(archiver.encodedData, forKey: .messageData)

        let superEncoder = container.superEncoder()
        try super.encode(to: superEncoder)
    }
}
