//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import Foundation
import XCTest
import StructuredHeaders

struct ListyDictionaryFieldParameters: Codable, Equatable {
    var q: Double?
    var fallback: String?
}

struct ListyDictionaryParameterisedString: Codable, Equatable {
    var item: String
    var parameters: ListyDictionaryFieldParameters
}

struct ListyDictionaryParameterisedList: Codable, Equatable {
    var items: [ListyDictionaryParameterisedString]
    var parameters: ListyDictionaryFieldParameters
}


/// An example ListyDictionary structured header field.
///
/// An example of this field is: 'primary=bar;q=1.0, secondary=baz;q=0.5;fallback=last, acceptablejurisdictions=(AU;q=1.0 GB;q=0.9 FR);fallback=primary'
struct ListyDictionaryField: Codable, Equatable {
    var primary: ListyDictionaryParameterisedString
    var secondary: ListyDictionaryParameterisedString
    var acceptablejurisdictions: ListyDictionaryParameterisedList
}

final class StructuredFieldDecoderTests: XCTestCase {
    func testSimpleCodableDecode() throws {
        let headerField = "primary=bar;q=1.0, secondary=baz;q=0.5;fallback=last, acceptablejurisdictions=(AU;q=1.0 GB;q=0.9 FR);fallback=\"primary\""
        let parsed = try StructuredFieldDecoder().decode(ListyDictionaryField.self, from: Array(headerField.utf8))
        let expected = ListyDictionaryField(
            primary: .init(item: "bar", parameters: .init(q: 1, fallback: nil)),
            secondary: .init(item: "baz", parameters: .init(q: 0.5, fallback: "last")),
            acceptablejurisdictions: .init(items: [.init(item: "AU", parameters: .init(q: 1, fallback: nil)), .init(item: "GB", parameters: .init(q: 0.9, fallback: nil)), .init(item: "FR", parameters: .init(q: nil, fallback: nil))], parameters: .init(q: nil, fallback: "primary"))
        )
        XCTAssertEqual(parsed, expected)
    }

    func testCanDecodeParameterisedItemsWithoutParameters() throws {
        struct ListyDictionaryNoParams: Codable, Equatable {
            var primary: String
            var secondary: String
            var acceptablejurisdictions: [String]
        }
        let headerField = "primary=bar;q=1.0, secondary=baz;q=0.5;fallback=last, acceptablejurisdictions=(AU;q=1.0 GB;q=0.9 FR);fallback=\"primary\""
        let parsed = try StructuredFieldDecoder().decode(ListyDictionaryNoParams.self, from: Array(headerField.utf8))
        let expected = ListyDictionaryNoParams(primary: "bar", secondary: "baz", acceptablejurisdictions: ["AU", "GB", "FR"])
        XCTAssertEqual(parsed, expected)
    }

    func testCanDecodeIntegersInVariousWays() throws {
        let headerField = "5;bar=baz"

        XCTAssertEqual(UInt8(5), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(Int8(5), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(UInt16(5), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(Int16(5), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(UInt32(5), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(Int32(5), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(UInt64(5), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(Int64(5), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(UInt(5), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(Int(5), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
    }

    func testOutOfRangeNumbersAreReported() throws {
        // Most-negative supported integer value is -999,999,999,999,999. This will fit into a
        // 64-bit integer, but no other integer type. Let's validate that this throws errors
        // rather than crashing for all non-Int64 types. (Ignoring Int/UInt due to their platform
        // dependence)
        let headerField = "-999999999999999;bar=baz"
        let expected = Int64(-999999999999999)

        XCTAssertThrowsError(try StructuredFieldDecoder().decode(Int8.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(UInt8.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(Int16.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(UInt16.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(Int32.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(UInt32.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(UInt64.self, from: Array(headerField.utf8)))
        XCTAssertEqual(expected, try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
    }

    func testDoubleAndFloatInterchangeable() throws {
        let headerField = "5.0;bar=baz"

        XCTAssertEqual(Float(5.0), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(Double(5.0), try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
    }

    func testAskingForTheWrongType() throws {
        let headerField = "gzip"
        let intField = "5"

        XCTAssertThrowsError(try StructuredFieldDecoder().decode(Int8.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(UInt8.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(Int16.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(UInt16.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(Int32.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(UInt32.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(Int64.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(UInt64.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(Double.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(Float.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(Bool.self, from: Array(headerField.utf8)))
        XCTAssertThrowsError(try StructuredFieldDecoder().decode(String.self, from: Array(intField.utf8)))
    }
}
