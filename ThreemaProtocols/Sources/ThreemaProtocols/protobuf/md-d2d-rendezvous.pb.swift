// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: md-d2d-rendezvous.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

// ## Connection Rendezvous Protocol
//
// Some mechanisms may request a 1:1 connection between two devices in order to
// transmit data as direct as possible. Establishing such a connection should
// always require user interaction.
//
// The protocol runs an authentication **handshake** on multiple paths
// simultaneously and applies a heuristic to determine the best available path.
// One of the devices is eligible to **nominate** a path after which arbitrary
// encrypted payloads may be exchanged.
//
// ### Terminology
//
// - `RID`: Rendezvous Initiator Device
// - `RRD`: Rendezvous Responder Device
// - `AK`: Authentication Key
// - `ETK`: Ephemeral Transport Key
// - `STK`: Shared Transport Key
// - `PID`: Path ID
// - `RPH`: Rendevous Path Hash
// - `RIDAK`: RID's Authentication Key
// - `RRDAK`: RRD's Authentication Key
// - `RIDTK`: RID's Transport Key
// - `RRDTK`: RRD's Transport Key
// - `RIDSN`: RID's Sequence Number
// - `RRDSN`: RRD's Sequence Number
//
// ### General Information
//
// **Sequence number:** The sequence number starts with `1` and is counted
// separately for each direction (i.e. there is one sequence number counter for
// the client and one for the server). We will use `RIDSN+` and `RRDSN+` in this
// document to denote that the counter should be increased **after** the value
// has been inserted (i.e. semantically equivalent to `x++` in many languages).
//
// **Framing:** An `extra.transport.frame` is being used to frame all
// transmitted data even if the transport supports datagrams. This intentionally
// allows to fragment a frame across multiple datagrams (e.g. useful for limited
// APIs that cannot deliver data in a streamed fashion).
//
// ### Key Derivation
//
//     RIDAK = BLAKE2b(key=AK.secret, salt='rida', personal='3ma-rendezvous')
//     RRDAK = BLAKE2b(key=AK.secret, salt='rrda', personal='3ma-rendezvous')
//
//     STK = BLAKE2b(
//       key=
//           AK.secret
//        || X25519HSalsa20(<local.ETK>.secret, <remote.ETK>.public)
//       salt='st',
//       personal='3ma-rendezvous'
//     )
//
//     RIDTK = BLAKE2b(key=STK.secret, salt='ridt', personal='3ma-rendezvous')
//     RRDTK = BLAKE2b(key=STK.secret, salt='rrdt', personal='3ma-rendezvous')
//
// ### Encryption Schemes
//
// RID's encryption scheme is defined in the following way:
//
//     ChaCha20-Poly1305(
//       key=<RID*K.secret>,
//       nonce=u32-le(PID) || u32-le(RIDSN+) || <4 zero bytes>,
//     )
//
// RRD's encryption scheme is defined in the following way:
//
//     ChaCha20-Poly1305(
//       key=<RRD*K.secret>,
//       nonce=u32-le(PID) || u32-le(RRDSN+) || <4 zero bytes>,
//     )
//
// ### Rendezvous Path Hash Derivation
//
// A Rendezvous Path Hash (RPH) can be used to ensure that both parties are
// connected to each other and not to some other party who was able to intercept
// AK:
//
//     RPH = BLAKE2b(
//       out-length=32,
//       salt='ph',
//       personal='3ma-rendezvous',
//       input=STK.secret,
//     )
//
// ### Path Matrix
//
//     | Name              | Multiple Paths |
//     |-------------------|----------------|
//     | Direct TCP Server | Yes            |
//     | Relayed WebSocket | No             |
//
// ### Protocol Flow
//
// Connection paths are formed by transmitting a `rendezvous.RendezvousInit`
// from RID to RRD as defined in the description of that message.
//
// The connections are then simultaneously established in the background and
// each path must go through the handshake flow with its authentication
// challenges. While doing so, the peers measure the RTT between challenge and
// response in order to determine a good path candidate for nomination.
//
// One of the peers, defined by the upper-layer protocol, nominates one of the
// established paths. Once nominated, both peers close all other paths (WS:
// `1000`).
//
// Once a path has been nominated, that path will be handed to the upper-layer
// protocol for arbitrary data transmission. That data must be protected by
// continuing the respective encryption scheme of the associated role.
//
// ### Handshake Flow
//
// RRD and RID authenticate one another by the following flow:
//
//     RRD ---- Handshake.RrdToRid.Hello ---> RID
//     RRD <- Handshake.RidToRrd.AuthHello -- RID
//     RRD ---- Handshake.RrdToRid.Auth ----> RID
//
// Before the path can be used by the upper-layer protocol, the chosen path must
// be `Nominate`d by either side. The upper-layer protocol must define which
// side may `Nominate`.
//
//     R*D ------- Handshake.Nominate ------> R*D
//
// ### Path Nomination
//
// The following algorithm should be used to determine which path is to be
// nominated. The upper-layer protocol must clearly define whether RRD or RID
// does nomination.
//
// 1. Let `established` be the list of established connection paths.
// 2. Asynchronously, with each connection becoming established, update
//    `established` with the RTT that was measured during the handshake.
// 3. Wait for the first connection path to become established.
// 4. After a brief timeout (or on a specific user interaction), nominate the
//    connection path in the following way, highest priority first:
//    1. Path with the lowest RTT on a mutually unmetered, fast network
//    2. Path with the lowest RTT on a mutually unmetered, slow network
//    3. Path with the lowest RTT on any other network
//
// Note: It is recommended to warn the user if a metered connection path has
// been nominated in case large amounts of data are to be transmitted.
//
// ### WebSocket Close Codes
//
// When WebSocket is used as rendezvous transport, the following close codes
// should be used:
//
// - Normal (`1000`): The rendezvous connection was not nominated or the
//   upper-layer protocol exited successfully.
// - Rendezvous Protocol Error (`4000`): The rendezvous protocol was violated.
//   Possible examples: Invalid WebSocket path, session full. Error details may
//   be included in the WebSocket close _reason_.
// - Init Timeout (`4003`): The other device did not connect in time.
// - Other Device Disconnected (`4004`): The other device disconnected without a
//   reflectable close code.
// - Upper-Layer Protocol Error (`4100`): The rendezvous connection was
//   nominated but an upper-layer protocol error occurred.
//
// The device should log all other close codes but treat them as a _Rendezvous
// Protocol Error_ (`4000`).
//
// Close codes in the `41xx` range as well as `1000` are reflected by the
// rendezvous server to the other device.
//
// ### Security
//
// To prevent phishing attacks, the CORS `Access-Control-Allow-Origin` of any
// WebSocket rendezvous relay server should be set to the bare minimum required
// by the use case.
//
// ### Threat Model
//
// The security of the protocol relies on the security of the secure channel
// where the `RendezvousInit` is being exchanged.
//
// Arbitrary WebSocket URLs and arbitrary IPv4/IPv6 addresses can be provided by
// RID where RRD would connect to. It is therefore required that RRD can trust
// RID to not be malicious.
//
// AK must be exchanged over a sufficiently secure channel. Concretely, AK must
// be sufficiently protected to at least resist a brute-force attack for the
// time between AK being exchanged and the handshake being fulfilled.
//
// A PID must be unique and not be re-used for a specific AK.

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

/// Contains the data necessary to initialise a 1:1 connection between two
/// devices.
///
/// When creating this message, run the following sub-steps simultaneously and
/// wait for them to finish:
///
/// 1. If the device is able to create a TCP server socket:
///    1. Bind to _any_ IP address with a random port number. Silently ignore
///       failures.
///    2. If successful, let `addresses` be the list of available IP addresses on
///       network interfaces the server has been bound to.
///    3. Drop any loopback and duplicate IP addresses from `addresses`.
///    4. Drop link-local IPv6 addresses associated to interfaces that only
///       provide link-local IPv6 addresses.
///    5. Sort `addresses` in the following way, highest priority first:
///         1. IP addresses on unmetered, fast networks
///         2. IP addresses on unmetered, slow networks
///         3. IP addresses on metered, fast networks
///         4. Any other addresses
///    6. Complete the subroutine and provide `addresses` and other necessary
///       data in the `direct_tcp_server` field.
/// 2. Connect to a WebSocket relay server:
///    1. Generate a random 32 byte hex-encoded rendezvous path.
///    2. Connect to the WebSocket relay server URL as provided by the context
///       with the generated hex-encoded rendezvous path.
///    3. Once connected, complete the subroutine and provide the necessary data
///       in the `relayed_web_socket` field.
///
/// When receiving this message:
///
/// 1. If `version` is unsupported, abort these steps.
/// 2. If any `path_id` is not unique, abort these steps.
/// 3. If the device is able to create a TCP client connection:
///    1. Let `addresses` be the IP addresses of `direct_tcp_server`.
///    2. Filter `addresses` by discarding IPs with unsupported families (e.g. if
///       the device has no IPv6 address, drop any IPv6 addresses).
///    3. For each IP address in `addresses`:
///       1. Connect to the given IP address in the background.
///       2. Wait 100ms.
/// 4. Connect to the provided relayed WebSocket server in the background.
/// 5. On each successful direct or relayed connection made in the background,
///    forward an event to the upper-layer protocol in order for it to select one
///    of the paths for nomination.
public struct Rendezvous_RendezvousInit {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var version: Rendezvous_RendezvousInit.Version = .v10

  /// 32 byte ephemeral secret Authentication Key (AK).
  public var ak: Data = Data()

  public var relayedWebSocket: Rendezvous_RendezvousInit.RelayedWebSocket {
    get {return _relayedWebSocket ?? Rendezvous_RendezvousInit.RelayedWebSocket()}
    set {_relayedWebSocket = newValue}
  }
  /// Returns true if `relayedWebSocket` has been explicitly set.
  public var hasRelayedWebSocket: Bool {return self._relayedWebSocket != nil}
  /// Clears the value of `relayedWebSocket`. Subsequent reads from it will return its default value.
  public mutating func clearRelayedWebSocket() {self._relayedWebSocket = nil}

  public var directTcpServer: Rendezvous_RendezvousInit.DirectTcpServer {
    get {return _directTcpServer ?? Rendezvous_RendezvousInit.DirectTcpServer()}
    set {_directTcpServer = newValue}
  }
  /// Returns true if `directTcpServer` has been explicitly set.
  public var hasDirectTcpServer: Bool {return self._directTcpServer != nil}
  /// Clears the value of `directTcpServer`. Subsequent reads from it will return its default value.
  public mutating func clearDirectTcpServer() {self._directTcpServer = nil}

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum Version: SwiftProtobuf.Enum {
    public typealias RawValue = Int

    /// Initial version.
    case v10 // = 0
    case UNRECOGNIZED(Int)

    public init() {
      self = .v10
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .v10
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .v10: return 0
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  /// Network cost of an interface
  public enum NetworkCost: SwiftProtobuf.Enum {
    public typealias RawValue = Int

    /// It is unknown whether the interface is metered or unmetered
    case unknown // = 0

    /// The interface is unmetered
    case unmetered // = 1

    /// The interface is metered
    case metered // = 2
    case UNRECOGNIZED(Int)

    public init() {
      self = .unknown
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .unmetered
      case 2: self = .metered
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .unmetered: return 1
      case .metered: return 2
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  /// Relayed WebSocket path
  public struct RelayedWebSocket {
    // SwiftProtobuf.Message conformance is added in an extension below. See the
    // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
    // methods supported on all messages.

    /// Unique Path ID (PID) of the path
    public var pathID: UInt32 = 0

    /// Network cost
    public var networkCost: Rendezvous_RendezvousInit.NetworkCost = .unknown

    /// Full URL to the WebSocket server with a random 32 byte hex-encoded
    /// rendezvous path. Must begin with `wss://``.
    public var url: String = String()

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    public init() {}
  }

  /// Direct path to a TCP server created by the initiator
  public struct DirectTcpServer {
    // SwiftProtobuf.Message conformance is added in an extension below. See the
    // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
    // methods supported on all messages.

    /// Random 16 bit port. Values greater than 65535 are invalid.
    public var port: UInt32 = 0

    /// List of associated IP addresses. Each IP address creates its own path.
    public var ipAddresses: [Rendezvous_RendezvousInit.DirectTcpServer.IpAddress] = []

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    /// An IP address
    public struct IpAddress {
      // SwiftProtobuf.Message conformance is added in an extension below. See the
      // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
      // methods supported on all messages.

      /// Unique Path ID (PID) of the path
      public var pathID: UInt32 = 0

      /// Network cost
      public var networkCost: Rendezvous_RendezvousInit.NetworkCost = .unknown

      /// IPv4 or IPv6 address
      public var ip: String = String()

      public var unknownFields = SwiftProtobuf.UnknownStorage()

      public init() {}
    }

    public init() {}
  }

  public init() {}

  fileprivate var _relayedWebSocket: Rendezvous_RendezvousInit.RelayedWebSocket? = nil
  fileprivate var _directTcpServer: Rendezvous_RendezvousInit.DirectTcpServer? = nil
}

#if swift(>=4.2)

extension Rendezvous_RendezvousInit.Version: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static let allCases: [Rendezvous_RendezvousInit.Version] = [
    .v10,
  ]
}

extension Rendezvous_RendezvousInit.NetworkCost: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static let allCases: [Rendezvous_RendezvousInit.NetworkCost] = [
    .unknown,
    .unmetered,
    .metered,
  ]
}

#endif  // swift(>=4.2)

/// Messages required for the initial lock-step handshake between RRD and RID.
public struct Rendezvous_Handshake {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  /// Handshake messages from RRD to RID.
  public struct RrdToRid {
    // SwiftProtobuf.Message conformance is added in an extension below. See the
    // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
    // methods supported on all messages.

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    /// Initial message from RRD containing its authentication challenge,
    /// encrypted by RRD's encryption scheme with RRDAK.
    public struct Hello {
      // SwiftProtobuf.Message conformance is added in an extension below. See the
      // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
      // methods supported on all messages.

      /// 16 byte random authentication challenge for RID.
      public var challenge: Data = Data()

      /// 32 byte ephemeral public key (`ETK.public`).
      public var etk: Data = Data()

      public var unknownFields = SwiftProtobuf.UnknownStorage()

      public init() {}
    }

    /// Final message from RRD responding to RID's authentication challenge,
    /// encrypted by RRD's encryption scheme with RRDAK.
    ///
    /// When receiving this message:
    ///
    /// 1. If the challenge `response` from RRD does not match the challenge sent
    ///    by RID, close the connection with a protocol error (WS: `4000`) and
    ///    abort these steps.
    public struct Auth {
      // SwiftProtobuf.Message conformance is added in an extension below. See the
      // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
      // methods supported on all messages.

      /// 16 byte repeated authentication challenge from RRD.
      public var response: Data = Data()

      public var unknownFields = SwiftProtobuf.UnknownStorage()

      public init() {}
    }

    public init() {}
  }

  /// Handshake messages from RID to RRD.
  public struct RidToRrd {
    // SwiftProtobuf.Message conformance is added in an extension below. See the
    // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
    // methods supported on all messages.

    public var unknownFields = SwiftProtobuf.UnknownStorage()

    /// Initial message from RID responding to RRD's authentication challenge and
    /// containing RID's authentication challenge, encrypted by RID's encryption
    /// scheme with RIDAK.
    ///
    /// When receiving this message:
    ///
    /// 1. If the challenge `response` from RID does not match the challenge sent
    ///    by RRD, close the connection with a protocol error (WS: `4000`) and
    ///    abort these steps.
    public struct AuthHello {
      // SwiftProtobuf.Message conformance is added in an extension below. See the
      // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
      // methods supported on all messages.

      /// 16 byte repeated authentication challenge from RRD.
      public var response: Data = Data()

      /// 16 byte random authentication challenge for RRD.
      public var challenge: Data = Data()

      /// 32 byte ephemeral public key (`ETK.public`).
      public var etk: Data = Data()

      public var unknownFields = SwiftProtobuf.UnknownStorage()

      public init() {}
    }

    public init() {}
  }

  public init() {}
}

/// Nominates the path. The upper-layer protocol defines whether RID or RRD may
/// nominate and is encrypted by the respective encryption scheme with RIDTK or
/// RRDTK.
///
/// When receiving this message:
///
/// 1. If the sender was not eligible to `Nominate`, close the connection with a
///    protocol error (WS: `4000`) and abort these steps.
/// 2. Close all other pending or established connection paths (WS: `1000`).¹
///
/// ¹: Closing other paths is only triggered by the receiver as it may otherwise
///    lead to a race between nomination and close detection.
public struct Rendezvous_Nominate {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public init() {}
}

#if swift(>=5.5) && canImport(_Concurrency)
extension Rendezvous_RendezvousInit: @unchecked Sendable {}
extension Rendezvous_RendezvousInit.Version: @unchecked Sendable {}
extension Rendezvous_RendezvousInit.NetworkCost: @unchecked Sendable {}
extension Rendezvous_RendezvousInit.RelayedWebSocket: @unchecked Sendable {}
extension Rendezvous_RendezvousInit.DirectTcpServer: @unchecked Sendable {}
extension Rendezvous_RendezvousInit.DirectTcpServer.IpAddress: @unchecked Sendable {}
extension Rendezvous_Handshake: @unchecked Sendable {}
extension Rendezvous_Handshake.RrdToRid: @unchecked Sendable {}
extension Rendezvous_Handshake.RrdToRid.Hello: @unchecked Sendable {}
extension Rendezvous_Handshake.RrdToRid.Auth: @unchecked Sendable {}
extension Rendezvous_Handshake.RidToRrd: @unchecked Sendable {}
extension Rendezvous_Handshake.RidToRrd.AuthHello: @unchecked Sendable {}
extension Rendezvous_Nominate: @unchecked Sendable {}
#endif  // swift(>=5.5) && canImport(_Concurrency)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "rendezvous"

extension Rendezvous_RendezvousInit: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".RendezvousInit"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "version"),
    2: .same(proto: "ak"),
    3: .standard(proto: "relayed_web_socket"),
    4: .standard(proto: "direct_tcp_server"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularEnumField(value: &self.version) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self.ak) }()
      case 3: try { try decoder.decodeSingularMessageField(value: &self._relayedWebSocket) }()
      case 4: try { try decoder.decodeSingularMessageField(value: &self._directTcpServer) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every if/case branch local when no optimizations
    // are enabled. https://github.com/apple/swift-protobuf/issues/1034 and
    // https://github.com/apple/swift-protobuf/issues/1182
    if self.version != .v10 {
      try visitor.visitSingularEnumField(value: self.version, fieldNumber: 1)
    }
    if !self.ak.isEmpty {
      try visitor.visitSingularBytesField(value: self.ak, fieldNumber: 2)
    }
    try { if let v = self._relayedWebSocket {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    } }()
    try { if let v = self._directTcpServer {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    } }()
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Rendezvous_RendezvousInit, rhs: Rendezvous_RendezvousInit) -> Bool {
    if lhs.version != rhs.version {return false}
    if lhs.ak != rhs.ak {return false}
    if lhs._relayedWebSocket != rhs._relayedWebSocket {return false}
    if lhs._directTcpServer != rhs._directTcpServer {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Rendezvous_RendezvousInit.Version: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "V1_0"),
  ]
}

extension Rendezvous_RendezvousInit.NetworkCost: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "UNMETERED"),
    2: .same(proto: "METERED"),
  ]
}

extension Rendezvous_RendezvousInit.RelayedWebSocket: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = Rendezvous_RendezvousInit.protoMessageName + ".RelayedWebSocket"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "path_id"),
    2: .standard(proto: "network_cost"),
    3: .same(proto: "url"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularUInt32Field(value: &self.pathID) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self.networkCost) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.url) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.pathID != 0 {
      try visitor.visitSingularUInt32Field(value: self.pathID, fieldNumber: 1)
    }
    if self.networkCost != .unknown {
      try visitor.visitSingularEnumField(value: self.networkCost, fieldNumber: 2)
    }
    if !self.url.isEmpty {
      try visitor.visitSingularStringField(value: self.url, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Rendezvous_RendezvousInit.RelayedWebSocket, rhs: Rendezvous_RendezvousInit.RelayedWebSocket) -> Bool {
    if lhs.pathID != rhs.pathID {return false}
    if lhs.networkCost != rhs.networkCost {return false}
    if lhs.url != rhs.url {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Rendezvous_RendezvousInit.DirectTcpServer: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = Rendezvous_RendezvousInit.protoMessageName + ".DirectTcpServer"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "port"),
    2: .standard(proto: "ip_addresses"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularUInt32Field(value: &self.port) }()
      case 2: try { try decoder.decodeRepeatedMessageField(value: &self.ipAddresses) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.port != 0 {
      try visitor.visitSingularUInt32Field(value: self.port, fieldNumber: 1)
    }
    if !self.ipAddresses.isEmpty {
      try visitor.visitRepeatedMessageField(value: self.ipAddresses, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Rendezvous_RendezvousInit.DirectTcpServer, rhs: Rendezvous_RendezvousInit.DirectTcpServer) -> Bool {
    if lhs.port != rhs.port {return false}
    if lhs.ipAddresses != rhs.ipAddresses {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Rendezvous_RendezvousInit.DirectTcpServer.IpAddress: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = Rendezvous_RendezvousInit.DirectTcpServer.protoMessageName + ".IpAddress"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "path_id"),
    2: .standard(proto: "network_cost"),
    3: .same(proto: "ip"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularUInt32Field(value: &self.pathID) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self.networkCost) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.ip) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.pathID != 0 {
      try visitor.visitSingularUInt32Field(value: self.pathID, fieldNumber: 1)
    }
    if self.networkCost != .unknown {
      try visitor.visitSingularEnumField(value: self.networkCost, fieldNumber: 2)
    }
    if !self.ip.isEmpty {
      try visitor.visitSingularStringField(value: self.ip, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Rendezvous_RendezvousInit.DirectTcpServer.IpAddress, rhs: Rendezvous_RendezvousInit.DirectTcpServer.IpAddress) -> Bool {
    if lhs.pathID != rhs.pathID {return false}
    if lhs.networkCost != rhs.networkCost {return false}
    if lhs.ip != rhs.ip {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Rendezvous_Handshake: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".Handshake"
  public static let _protobuf_nameMap = SwiftProtobuf._NameMap()

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let _ = try decoder.nextFieldNumber() {
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Rendezvous_Handshake, rhs: Rendezvous_Handshake) -> Bool {
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Rendezvous_Handshake.RrdToRid: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = Rendezvous_Handshake.protoMessageName + ".RrdToRid"
  public static let _protobuf_nameMap = SwiftProtobuf._NameMap()

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let _ = try decoder.nextFieldNumber() {
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Rendezvous_Handshake.RrdToRid, rhs: Rendezvous_Handshake.RrdToRid) -> Bool {
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Rendezvous_Handshake.RrdToRid.Hello: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = Rendezvous_Handshake.RrdToRid.protoMessageName + ".Hello"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "challenge"),
    2: .same(proto: "etk"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self.challenge) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self.etk) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.challenge.isEmpty {
      try visitor.visitSingularBytesField(value: self.challenge, fieldNumber: 1)
    }
    if !self.etk.isEmpty {
      try visitor.visitSingularBytesField(value: self.etk, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Rendezvous_Handshake.RrdToRid.Hello, rhs: Rendezvous_Handshake.RrdToRid.Hello) -> Bool {
    if lhs.challenge != rhs.challenge {return false}
    if lhs.etk != rhs.etk {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Rendezvous_Handshake.RrdToRid.Auth: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = Rendezvous_Handshake.RrdToRid.protoMessageName + ".Auth"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "response"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self.response) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.response.isEmpty {
      try visitor.visitSingularBytesField(value: self.response, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Rendezvous_Handshake.RrdToRid.Auth, rhs: Rendezvous_Handshake.RrdToRid.Auth) -> Bool {
    if lhs.response != rhs.response {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Rendezvous_Handshake.RidToRrd: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = Rendezvous_Handshake.protoMessageName + ".RidToRrd"
  public static let _protobuf_nameMap = SwiftProtobuf._NameMap()

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let _ = try decoder.nextFieldNumber() {
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Rendezvous_Handshake.RidToRrd, rhs: Rendezvous_Handshake.RidToRrd) -> Bool {
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Rendezvous_Handshake.RidToRrd.AuthHello: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = Rendezvous_Handshake.RidToRrd.protoMessageName + ".AuthHello"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "response"),
    2: .same(proto: "challenge"),
    3: .same(proto: "etk"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self.response) }()
      case 2: try { try decoder.decodeSingularBytesField(value: &self.challenge) }()
      case 3: try { try decoder.decodeSingularBytesField(value: &self.etk) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.response.isEmpty {
      try visitor.visitSingularBytesField(value: self.response, fieldNumber: 1)
    }
    if !self.challenge.isEmpty {
      try visitor.visitSingularBytesField(value: self.challenge, fieldNumber: 2)
    }
    if !self.etk.isEmpty {
      try visitor.visitSingularBytesField(value: self.etk, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Rendezvous_Handshake.RidToRrd.AuthHello, rhs: Rendezvous_Handshake.RidToRrd.AuthHello) -> Bool {
    if lhs.response != rhs.response {return false}
    if lhs.challenge != rhs.challenge {return false}
    if lhs.etk != rhs.etk {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Rendezvous_Nominate: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".Nominate"
  public static let _protobuf_nameMap = SwiftProtobuf._NameMap()

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let _ = try decoder.nextFieldNumber() {
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Rendezvous_Nominate, rhs: Rendezvous_Nominate) -> Bool {
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
