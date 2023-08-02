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
import CryptoKit
import Foundation
import ThreemaProtocols
import WebRTC

@GlobalGroupCallActor
/// Group Call Connection State
/// Starts the WebRTC connection to the SFU and hands it over to the `Connected` state once established
struct Connecting: GroupCallState {
    // MARK: - Internal Properties

    let groupCallActor: GroupCallActor
    let joinResponse: Groupcall_SfuHttpResponse.Join
    let certificate: RTCCertificate
    
    // MARK: - Private Properties

    private let connectionContext: ConnectionContext<PeerConnectionContext, RTCRtpTransceiver>
    private let groupCallContext: GroupCallContext<PeerConnectionContext, RTCRtpTransceiver>
    
    // MARK: - Lifecycle

    init(
        groupCallActor: GroupCallActor,
        joinResponse: Groupcall_SfuHttpResponse.Join,
        certificate: RTCCertificate
    ) throws {
        
        // TODO: (IOS-3857) Logging
        DDLogNotice("[GroupCall] Init Connecting \(groupCallActor.callID.bytes.hexEncodedString())")
        
        self.groupCallActor = groupCallActor
        self.joinResponse = joinResponse
        self.certificate = certificate
        
        let participantID = ParticipantID(id: joinResponse.participantID)
        let iceParameters = IceParameters(
            usernameFragment: joinResponse.iceUsernameFragment,
            password: joinResponse.icePassword
        )
        let dtlsParameters = DtlsParameters(fingerprint: Array(joinResponse.dtlsFingerprint))
        
        let sessionParameters = SessionParameters(
            participantID: participantID,
            iceParameters: iceParameters,
            dtlsParameters: dtlsParameters
        )
        
        let groupCallDescription = groupCallActor.groupCallDescriptionCopy
        
        self.connectionContext = try ConnectionContext(
            certificate: certificate,
            cryptoContext: groupCallDescription,
            sessionParameters: sessionParameters,
            dependencies: groupCallActor.dependencies
        )
        
        let localParticipantID = ParticipantID(id: joinResponse.participantID)
        
        // TODO: Actual contact
        let localContactModel = ContactModel(identity: "Test", nickname: "test")
        
        let localParticipant = LocalParticipant(
            id: localParticipantID,
            contactModel: localContactModel,
            localContext: LocalContext(),
            threemaID: groupCallActor.localIdentity,
            dependencies: self.groupCallActor.dependencies,
            localIdentity: groupCallActor.localIdentity
        )
        
        self.groupCallContext = try GroupCallContext(
            connectionContext: connectionContext,
            localParticipant: localParticipant,
            dependencies: groupCallActor.dependencies,
            groupCallDescription: groupCallDescription
        )
        
        Task {
            await groupCallActor.add(localParticipant)
        }
    }
    
    func next() async throws -> GroupCallState? {
        // TODO: (IOS-3857) Logging
        DDLogNotice("[GroupCall] State is Connecting \(groupCallActor.callID.bytes.hexEncodedString())")
        
        /// **Protocol Step: Group Call Join Steps** 5. Establish a WebRTC connection to the SFU with the information
        /// provided in the Join response. Wait until the SFU sent the initial SfuToParticipant.Hello message via the
        /// associated data channel. Let hello be that message.
        connectionContext.createLocalMediaSenders()
        
        try await connectionContext.createAndApplyInitialOfferAndAnswer()
        
        guard !Task.isCancelled else {
            return Ended(groupCallActor: groupCallActor)
        }
        
        try? await connectionContext.addIceCandidates(addresses: joinResponse.addresses)
        
        guard !Task.isCancelled else {
            return Ended(groupCallActor: groupCallActor)
        }
        
        var messageData: Data?
        
        for await message in connectionContext.messageStream {
            guard !Task.isCancelled else {
                return Ended(groupCallActor: groupCallActor)
            }
            messageData = message.data
            break
        }
        
        guard let messageData else {
            throw FatalStateError.FirstMessageNotReceived
        }
        
        guard let envelope = try? Groupcall_SfuToParticipant.Envelope(serializedData: messageData).hello else {
            throw FatalStateError.SerializationFailure
        }
        
        /// **Protocol Step: Group Call Join Steps** 6. If the hello.participants contains less than 4 items, set the
        /// initial capture state of the microphone to on.
        // TODO: (IOS-????) See above
        assert(envelope.unknownFields.data.isEmpty)
        
        // swiftformat:disable acronyms
        DDLogNotice("[GroupCall] Added participants \(envelope.participantIds)")
        // swiftformat:enable acronyms
        
        guard !Task.isCancelled else {
            return Ended(groupCallActor: groupCallActor)
        }
        
        return Connected(
            groupCallActor: groupCallActor,
            groupCallContext: groupCallContext,
            // swiftformat:disable acronyms
            participantIDs: envelope.participantIds
            // swiftformat:enable acronyms
        )
    }
    
    func localVideoTrack() -> RTCVideoTrack? {
        groupCallContext.localVideoTrack()
    }
}
