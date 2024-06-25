//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2020-2023 Threema GmbH
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

// swiftformat:disable acronyms

import Foundation

enum OnPremConfigError: Int, Error {
    case badInputOppfData
    case unsupportedVersion
    case badSignature
    case signatureKeyMismatch
    case configurationMissing
    case invalidConfigUrl
    case unauthorized
    case missingWorkConfig
    case missingAvatarConfig
    case missingSafeConfig
    case missingMediatorConfig
    case missingRendezvousConfig
    case missingDomainsConfig
    case noDomainSpkis
    case unsupportedDomainMatchMode
    case unsupportedDomainSpkisAlgorithm
    case licenseExpired
}

// MARK: - LocalizedError

extension OnPremConfigError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .badInputOppfData, .missingRendezvousConfig, .missingMediatorConfig, .missingSafeConfig,
             .missingAvatarConfig, .missingWorkConfig, .invalidConfigUrl, .configurationMissing, .signatureKeyMismatch,
             .badSignature, .missingDomainsConfig, .noDomainSpkis, .unsupportedDomainMatchMode,
             .unsupportedDomainSpkisAlgorithm:
            String.localizedStringWithFormat("enter_license_onprem_error_config".localized, rawValue)
       
        case .unsupportedVersion:
            String.localizedStringWithFormat("enter_license_onprem_error_version".localized, rawValue)

        case .unauthorized, .licenseExpired:
            String.localizedStringWithFormat("enter_license_onprem_error_credentials".localized, rawValue)
        }
    }
}
