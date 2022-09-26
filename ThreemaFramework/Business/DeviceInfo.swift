//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2021-2022 Threema GmbH
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

public enum Platform: Int {
    case unspecified = 0
    case android = 1
    case ios = 2
    case desktop = 3
    case web = 4

    public init?(rawValue: Int) {
        switch rawValue {
        case 0: self = .unspecified
        case 1: self = .android
        case 2: self = .ios
        case 3: self = .desktop
        case 4: self = .web
        default: self = .unspecified
        }
    }

    public var rawValue: Int {
        switch self {
        case .unspecified: return 0
        case .android: return 1
        case .ios: return 2
        case .desktop: return 3
        case .web: return 4
        }
    }
}

public struct DeviceInfo {
    let deviceID: UInt64
    public let label: String
    public let lastLoginAt: Date
    public let badge: String?
    public let platform: Platform
    public let platformDetails: String?
}
