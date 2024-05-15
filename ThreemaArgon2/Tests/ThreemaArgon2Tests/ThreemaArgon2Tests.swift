//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2023-2024 Threema GmbH
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

import argon2
import XCTest
@testable import ThreemaArgon2

/// Tests based on `test.c` of the reference implementation
final class ThreemaArgon2Tests: XCTestCase {
        
    func testVariantIDAndCurrentVersion() throws {
        try hashWithIDTest(
            "password",
            with: "somesalt",
            iterations: 2,
            memory: 1 << 16,
            threads: 1,
            expectedHex: "09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7"
        )
        
        try hashWithIDTest(
            "password",
            with: "somesalt",
            iterations: 2,
            memory: 1 << 18,
            threads: 1,
            expectedHex: "78fe1ec91fb3aa5657d72e710854e4c3d9b9198c742f9616c2f085bed95b2e8c"
        )
        
        try hashWithIDTest(
            "password",
            with: "somesalt",
            iterations: 2,
            memory: 1 << 8,
            threads: 1,
            expectedHex: "9dfeb910e80bad0311fee20f9c0e2b12c17987b4cac90c2ef54d5b3021c68bfe"
        )
        
        try hashWithIDTest(
            "password",
            with: "somesalt",
            iterations: 2,
            memory: 1 << 8,
            threads: 2,
            expectedHex: "6d093c501fd5999645e0ea3bf620d7b8be7fd2db59c20d9fff9539da2bf57037"
        )
        
        try hashWithIDTest(
            "password",
            with: "somesalt",
            iterations: 1,
            memory: 1 << 16,
            threads: 1,
            expectedHex: "f6a5adc1ba723dddef9b5ac1d464e180fcd9dffc9d1cbf76cca2fed795d9ca98"
        )
        
        try hashWithIDTest(
            "password",
            with: "somesalt",
            iterations: 4,
            memory: 1 << 16,
            threads: 1,
            expectedHex: "9025d48e68ef7395cca9079da4c4ec3affb3c8911fe4f86d1a2520856f63172c"
        )
        
        try hashWithIDTest(
            "differentpassword",
            with: "somesalt",
            iterations: 2,
            memory: 1 << 16,
            threads: 1,
            expectedHex: "0b84d652cf6b0c4beaef0dfe278ba6a80df6696281d7e0d2891b817d8c458fde"
        )
        
        try hashWithIDTest(
            "password",
            with: "diffsalt",
            iterations: 2,
            memory: 1 << 16,
            threads: 1,
            expectedHex: "bdf32b05ccc42eb15d58fd19b1f856b113da1e9a5874fdcc544308565aa8141c"
        )
    }
    
    func testCommonErrorStates() {
        XCTAssertThrowsExpectedError(
            try ThreemaArgon2.hashWithID(
                Data("password".utf8),
                with: Data("diffsalt".utf8),
                iterations: 2,
                memoryInKiB: 1,
                threads: 1,
                desiredLength: .b32
            ),
            ThreemaArgon2.Error.memoryTooLittle
        )

        XCTAssertThrowsExpectedError(
            try ThreemaArgon2.hashWithID(
                Data("password".utf8),
                with: Data("s".utf8),
                iterations: 2,
                memoryInKiB: 1 ^ 12,
                threads: 1,
                desiredLength: .b32
            ),
            ThreemaArgon2.Error.saltTooShort
        )
    }
    
    private func hashWithIDTest(
        _ password: String,
        with salt: String,
        iterations: UInt32,
        memory: UInt32,
        threads: UInt32,
        expectedHex: String
    ) throws {
        let actualRaw = try ThreemaArgon2.hashWithID(
            Data(password.utf8),
            with: Data(salt.utf8),
            iterations: iterations,
            memoryInKiB: memory,
            threads: threads,
            desiredLength: .b32
        )
        
        let actualRawHex = actualRaw.map { String(format: "%02hhx", $0) }.joined()
        XCTAssertEqual(expectedHex, actualRawHex)
    }
    
    private func XCTAssertThrowsExpectedError<E: Error & Equatable>(
        _ expression: @autoclosure () throws -> some Any,
        _ expectedError: E,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), message, file: file, line: line) { error in
            XCTAssertNotNil(error as? E)
            XCTAssertEqual(error as? E, expectedError)
        }
    }
}
