// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: csp-e2e.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

// ## End-to-End Encrypted Messages (Supplementary)
//
// This is a supplementary section to the corresponding structbuf section
// with newer messages that use protobuf instead of structbuf. All defined
// messages here follow the same logic.

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

/// Metadata sent within a CSP payload `message-with-meta` struct.
struct CspE2e_MessageMetadata {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// Padding that is ignored by the receiver.
  /// Recommended to be chosen such that the total length of padding + nickname
  /// is at least 16 bytes. May be empty if the nickname is long enough.
  var padding: Data = Data()

  /// The nickname associated to the sender's Threema ID. Recommended to not
  /// exceed 32 graphemes.
  var nickname: String = String()

  /// Unique message ID. Must match the message ID of the outer struct
  /// (i.e. `message-with-metadata-box.message-id`).
  var messageID: UInt64 = 0

  /// Unix-ish timestamp in milliseconds for when the message has been created
  var createdAt: UInt64 = 0

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

/// Request joining a group.
///
/// This message is sent to the administrator of a group. The required
/// information is provided by a `GroupInvite` URL payload.
///
/// When receiving this message:
///
/// 1. Look up the corresponding group invitation by the token.
/// 2. If the group invitation could not be found, discard the message and abort
///    these steps.
/// 3. If the sender is already part of the group, send an accept response and
///    then respond as if the sender had sent a `group-sync-request` (i.e. send
///    a `group-setup`, `group-name`, etc.). Finally, abort these steps.
/// 4. If the group name does not match the name in the originally sent group
///    invitation, discard the message and abort these steps.
/// 5. If the group invitation has expired, send the respective response and
///    abort these steps.
/// 6. If the group invitation requires the admin to accept the request, show
///    this information in the user interface and pause these steps until the
///    admin manually confirmed of rejected the request. Note that the date of
///    the decision is allowed to extend beyond the expiration date of the
///    group invitation. Continue with the following sub-steps once the admin
///    made a decision on the request:
///     1. If the admin manually rejected the request, send the respective
///        response and abort these steps.
/// 7. If the group is full, send the respective response and abort these steps.
/// 8. Send an accept response.
/// 9. Add the sender of the group invitation request to the group and follow
///    the group protocol from there.
struct CspE2e_GroupJoinRequest {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The group invite token, 16 bytes
  var token: Data = Data()

  /// The group name from the group invite URL
  var groupName: String = String()

  /// A message for the group administrator, e.g. for identification purposes
  ///
  /// The message helps the administrator to decide whether or not to accept a
  /// join request.
  ///
  /// Should be requested by the user interface for invitations that require
  /// manual confirmation by the administrator. Should not be requested in case
  /// the invitation will be automatically accepted.
  var message: String = String()

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}
}

/// Response sent by the admin of a group towards a sender of a valid group join request.
///
/// When receiving this message:
///
/// 1. Look up the corresponding group join request by the token and the
///    sender's Threema ID as the administrator's Threema ID.
/// 2. If the group join request could not be found, discard the message and
///    abort these steps.
/// 3. Mark the group join request as accepted or (automatically) rejected by
///    the given response type.
/// 4. If the group join request has been accepted, remember the group id in
///    order to be able to map an incoming `group-setup` to the group.
struct CspE2e_GroupJoinResponse {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// The group invite token, 16 bytes
  var token: Data = Data()

  var response: CspE2e_GroupJoinResponse.Response {
    get {return _response ?? CspE2e_GroupJoinResponse.Response()}
    set {_response = newValue}
  }
  /// Returns true if `response` has been explicitly set.
  var hasResponse: Bool {return self._response != nil}
  /// Clears the value of `response`. Subsequent reads from it will return its default value.
  mutating func clearResponse() {self._response = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  /// Response of the admin
  struct Response {
    // SwiftProtobuf.Message conformance is added in an extension below. See the
    // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
    // methods supported on all messages.

    var response: CspE2e_GroupJoinResponse.Response.OneOf_Response? = nil

    /// Accept a group invite request
    var accept: CspE2e_GroupJoinResponse.Response.Accept {
      get {
        if case .accept(let v)? = response {return v}
        return CspE2e_GroupJoinResponse.Response.Accept()
      }
      set {response = .accept(newValue)}
    }

    /// Token of a group invitation expired
    var expired: Common_Unit {
      get {
        if case .expired(let v)? = response {return v}
        return Common_Unit()
      }
      set {response = .expired(newValue)}
    }

    /// Group invitation cannot be accepted due to the group being full
    var groupFull: Common_Unit {
      get {
        if case .groupFull(let v)? = response {return v}
        return Common_Unit()
      }
      set {response = .groupFull(newValue)}
    }

    /// The administrator explicitly rejects the invitation request
    var reject: Common_Unit {
      get {
        if case .reject(let v)? = response {return v}
        return Common_Unit()
      }
      set {response = .reject(newValue)}
    }

    var unknownFields = SwiftProtobuf.UnknownStorage()

    enum OneOf_Response: Equatable {
      /// Accept a group invite request
      case accept(CspE2e_GroupJoinResponse.Response.Accept)
      /// Token of a group invitation expired
      case expired(Common_Unit)
      /// Group invitation cannot be accepted due to the group being full
      case groupFull(Common_Unit)
      /// The administrator explicitly rejects the invitation request
      case reject(Common_Unit)

    #if !swift(>=4.1)
      static func ==(lhs: CspE2e_GroupJoinResponse.Response.OneOf_Response, rhs: CspE2e_GroupJoinResponse.Response.OneOf_Response) -> Bool {
        // The use of inline closures is to circumvent an issue where the compiler
        // allocates stack space for every case branch when no optimizations are
        // enabled. https://github.com/apple/swift-protobuf/issues/1034
        switch (lhs, rhs) {
        case (.accept, .accept): return {
          guard case .accept(let l) = lhs, case .accept(let r) = rhs else { preconditionFailure() }
          return l == r
        }()
        case (.expired, .expired): return {
          guard case .expired(let l) = lhs, case .expired(let r) = rhs else { preconditionFailure() }
          return l == r
        }()
        case (.groupFull, .groupFull): return {
          guard case .groupFull(let l) = lhs, case .groupFull(let r) = rhs else { preconditionFailure() }
          return l == r
        }()
        case (.reject, .reject): return {
          guard case .reject(let l) = lhs, case .reject(let r) = rhs else { preconditionFailure() }
          return l == r
        }()
        default: return false
        }
      }
    #endif
    }

    /// Accept a group invite request
    struct Accept {
      // SwiftProtobuf.Message conformance is added in an extension below. See the
      // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
      // methods supported on all messages.

      /// Group ID (little-endian) as chosen by the group creator
      /// Note: Combined with the Threema ID of the administrator, this forms
      ///       the `GroupIdentity`.
      var groupID: UInt64 = 0

      var unknownFields = SwiftProtobuf.UnknownStorage()

      init() {}
    }

    init() {}
  }

  init() {}

  fileprivate var _response: CspE2e_GroupJoinResponse.Response? = nil
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "csp_e2e"

extension CspE2e_MessageMetadata: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".MessageMetadata"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "padding"),
    2: .same(proto: "nickname"),
    3: .standard(proto: "message_id"),
    4: .standard(proto: "created_at"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self.padding) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.nickname) }()
      case 3: try { try decoder.decodeSingularFixed64Field(value: &self.messageID) }()
      case 4: try { try decoder.decodeSingularUInt64Field(value: &self.createdAt) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.padding.isEmpty {
      try visitor.visitSingularBytesField(value: self.padding, fieldNumber: 1)
    }
    if !self.nickname.isEmpty {
      try visitor.visitSingularStringField(value: self.nickname, fieldNumber: 2)
    }
    if self.messageID != 0 {
      try visitor.visitSingularFixed64Field(value: self.messageID, fieldNumber: 3)
    }
    if self.createdAt != 0 {
      try visitor.visitSingularUInt64Field(value: self.createdAt, fieldNumber: 4)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: CspE2e_MessageMetadata, rhs: CspE2e_MessageMetadata) -> Bool {
    if lhs.padding != rhs.padding {return false}
    if lhs.nickname != rhs.nickname {return false}
    if lhs.messageID != rhs.messageID {return false}
    if lhs.createdAt != rhs.createdAt {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension CspE2e_GroupJoinRequest: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".GroupJoinRequest"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "token"),
    2: .standard(proto: "group_name"),
    3: .same(proto: "message"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self.token) }()
      case 2: try { try decoder.decodeSingularStringField(value: &self.groupName) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.message) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.token.isEmpty {
      try visitor.visitSingularBytesField(value: self.token, fieldNumber: 1)
    }
    if !self.groupName.isEmpty {
      try visitor.visitSingularStringField(value: self.groupName, fieldNumber: 2)
    }
    if !self.message.isEmpty {
      try visitor.visitSingularStringField(value: self.message, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: CspE2e_GroupJoinRequest, rhs: CspE2e_GroupJoinRequest) -> Bool {
    if lhs.token != rhs.token {return false}
    if lhs.groupName != rhs.groupName {return false}
    if lhs.message != rhs.message {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension CspE2e_GroupJoinResponse: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".GroupJoinResponse"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "token"),
    2: .same(proto: "response"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularBytesField(value: &self.token) }()
      case 2: try { try decoder.decodeSingularMessageField(value: &self._response) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.token.isEmpty {
      try visitor.visitSingularBytesField(value: self.token, fieldNumber: 1)
    }
    if let v = self._response {
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: CspE2e_GroupJoinResponse, rhs: CspE2e_GroupJoinResponse) -> Bool {
    if lhs.token != rhs.token {return false}
    if lhs._response != rhs._response {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension CspE2e_GroupJoinResponse.Response: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = CspE2e_GroupJoinResponse.protoMessageName + ".Response"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "accept"),
    2: .same(proto: "expired"),
    3: .standard(proto: "group_full"),
    4: .same(proto: "reject"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try {
        var v: CspE2e_GroupJoinResponse.Response.Accept?
        var hadOneofValue = false
        if let current = self.response {
          hadOneofValue = true
          if case .accept(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.response = .accept(v)
        }
      }()
      case 2: try {
        var v: Common_Unit?
        var hadOneofValue = false
        if let current = self.response {
          hadOneofValue = true
          if case .expired(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.response = .expired(v)
        }
      }()
      case 3: try {
        var v: Common_Unit?
        var hadOneofValue = false
        if let current = self.response {
          hadOneofValue = true
          if case .groupFull(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.response = .groupFull(v)
        }
      }()
      case 4: try {
        var v: Common_Unit?
        var hadOneofValue = false
        if let current = self.response {
          hadOneofValue = true
          if case .reject(let m) = current {v = m}
        }
        try decoder.decodeSingularMessageField(value: &v)
        if let v = v {
          if hadOneofValue {try decoder.handleConflictingOneOf()}
          self.response = .reject(v)
        }
      }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    // The use of inline closures is to circumvent an issue where the compiler
    // allocates stack space for every case branch when no optimizations are
    // enabled. https://github.com/apple/swift-protobuf/issues/1034
    switch self.response {
    case .accept?: try {
      guard case .accept(let v)? = self.response else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 1)
    }()
    case .expired?: try {
      guard case .expired(let v)? = self.response else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 2)
    }()
    case .groupFull?: try {
      guard case .groupFull(let v)? = self.response else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 3)
    }()
    case .reject?: try {
      guard case .reject(let v)? = self.response else { preconditionFailure() }
      try visitor.visitSingularMessageField(value: v, fieldNumber: 4)
    }()
    case nil: break
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: CspE2e_GroupJoinResponse.Response, rhs: CspE2e_GroupJoinResponse.Response) -> Bool {
    if lhs.response != rhs.response {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension CspE2e_GroupJoinResponse.Response.Accept: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = CspE2e_GroupJoinResponse.Response.protoMessageName + ".Accept"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "group_id"),
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeSingularFixed64Field(value: &self.groupID) }()
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if self.groupID != 0 {
      try visitor.visitSingularFixed64Field(value: self.groupID, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: CspE2e_GroupJoinResponse.Response.Accept, rhs: CspE2e_GroupJoinResponse.Response.Accept) -> Bool {
    if lhs.groupID != rhs.groupID {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
