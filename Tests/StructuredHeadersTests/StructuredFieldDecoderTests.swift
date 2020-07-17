import CodableStructuredHeaders
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
import StructuredHeaders
import XCTest

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
        let expected = Int64(-999_999_999_999_999)

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

    func testDecodingTopLevelItemWithParameters() throws {
        struct IntWithParams: Codable, Equatable {
            var item: Int
            var parameters: [String: String]
        }

        let headerField = "5;bar=baz"
        let expected = IntWithParams(item: 5, parameters: ["bar": "baz"])
        XCTAssertEqual(expected, try StructuredFieldDecoder().decodeItemField(from: Array(headerField.utf8)))
    }

    func testDecodingTopLevelList() throws {
        let headerField = "foo, bar, baz"
        let expected = ["foo", "bar", "baz"]
        XCTAssertEqual(expected, try StructuredFieldDecoder().decodeListField(from: Array(headerField.utf8)))
        XCTAssertEqual(expected, try StructuredFieldDecoder().decode(from: Array(headerField.utf8)))
    }

    func testDecodingLowercaseKeyStrategy() throws {
        struct Camel: Codable, Equatable {
            var hasHump: Bool
        }

        let headerField = "hashump"
        let expected = Camel(hasHump: true)
        var decoder = StructuredFieldDecoder()
        decoder.keyDecodingStrategy = .lowercase

        XCTAssertEqual(expected, try decoder.decodeDictionaryField(from: Array(headerField.utf8)))
    }

    func testDecodingLowercaseKeyStrategyParameters() throws {
        struct CamelParameters: Codable, Equatable {
            var hasHump: Bool
        }

        struct Camel: Codable, Equatable {
            var item: String
            var parameters: CamelParameters
        }

        let headerField = "dromedary;hashump"
        let expected = Camel(item: "dromedary", parameters: .init(hasHump: true))
        var decoder = StructuredFieldDecoder()
        decoder.keyDecodingStrategy = .lowercase

        XCTAssertEqual(expected, try decoder.decodeItemField(from: Array(headerField.utf8)))
    }

    func testDecodingKeyMissingFromDictionary() throws {
        struct MissingKey: Codable {
            var foo: Int
        }

        let headerField = "bar=baz"
        XCTAssertThrowsError(try StructuredFieldDecoder().decodeDictionaryField(MissingKey.self, from: Array(headerField.utf8)))
    }

    func testDecodingKeyAsItemWantedInnerList() throws {
        struct MissingInnerList: Codable {
            var innerlist: [String]
        }

        let headerField = "innerlist=x"
        XCTAssertThrowsError(try StructuredFieldDecoder().decodeDictionaryField(MissingInnerList.self, from: Array(headerField.utf8)))
    }

    func testDecodingBinaryAsTopLevelData() throws {
        let headerField = ":AQIDBA==:"
        XCTAssertEqual(
            Data([1, 2, 3, 4]),
            try StructuredFieldDecoder().decodeItemField(Data.self, from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryAsParameterisedData() throws {
        struct Item: Codable, Equatable {
            var item: Data
            var parameters: [String: Float]
        }

        let headerFieldNoParameters = ":AQIDBA==:"
        let headerFieldParameters = ":AQIDBA==:;q=0.8"

        XCTAssertEqual(
            Item(item: Data([1, 2, 3, 4]), parameters: [:]),
            try StructuredFieldDecoder().decodeItemField(Item.self, from: Array(headerFieldNoParameters.utf8))
        )

        XCTAssertEqual(
            Item(item: Data([1, 2, 3, 4]), parameters: ["q": 0.8]),
            try StructuredFieldDecoder().decodeItemField(Item.self, from: Array(headerFieldParameters.utf8))
        )
    }

    func testDecodingBinaryInParameterField() throws {
        struct Item: Codable, Equatable {
            var item: Int
            var parameters: [String: Data]
        }

        let headerField = "1;q=:AQIDBA==:"
        XCTAssertEqual(
            Item(item: 1, parameters: ["q": Data([1, 2, 3, 4])]),
            try StructuredFieldDecoder().decodeItemField(Item.self, from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryInOuterListRaw() throws {
        let headerField = ":AQIDBA==:, :BQYHCA==:"
        XCTAssertEqual(
            [Data([1, 2, 3, 4]), Data([5, 6, 7, 8])],
            try StructuredFieldDecoder().decodeListField([Data].self, from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryInOuterListKeyed() throws {
        struct ListField: Codable, Equatable {
            var items: [Data]
        }
        let headerField = ":AQIDBA==:, :BQYHCA==:"
        XCTAssertEqual(
            [Data([1, 2, 3, 4]), Data([5, 6, 7, 8])],
            try StructuredFieldDecoder().decodeListField([Data].self, from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryInInnerListRaw() throws {
        let headerField = "(:AQIDBA==: :BQYHCA==:), (:AQIDBA==: :BQYHCA==:)"
        XCTAssertEqual(
            Array(repeating: [Data([1, 2, 3, 4]), Data([5, 6, 7, 8])], count: 2),
            try StructuredFieldDecoder().decodeListField([[Data]].self, from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryInInnerListKeyed() throws {
        struct ListField: Codable, Equatable {
            var items: [Data]
            var parameters: [String: Bool]
        }
        let headerField = "(:AQIDBA==: :BQYHCA==:);foo, (:AQIDBA==: :BQYHCA==:);foo"
        XCTAssertEqual(
            Array(repeating: ListField(items: [Data([1, 2, 3, 4]), Data([5, 6, 7, 8])], parameters: ["foo": true]), count: 2),
            try StructuredFieldDecoder().decodeListField([ListField].self, from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryInDictionaries() throws {
        struct DictionaryField: Codable, Equatable {
            var bin: Data
            var box: Data
        }

        let headerField = "bin=:AQIDBA==:, box=:AQIDBA==:"
        XCTAssertEqual(
            DictionaryField(bin: Data([1, 2, 3, 4]), box: Data([1, 2, 3, 4])),
            try StructuredFieldDecoder().decodeDictionaryField(DictionaryField.self, from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalAsTopLevelData() throws {
        let headerField = "987654321.123"
        XCTAssertEqual(
            Decimal(string: "987654321.123")!,
            try StructuredFieldDecoder().decodeItemField(Decimal.self, from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalAsParameterisedData() throws {
        struct Item: Codable, Equatable {
            var item: Decimal
            var parameters: [String: Float]
        }

        let headerFieldNoParameters = "987654321.123"
        let headerFieldParameters = "987654321.123;q=0.8"

        XCTAssertEqual(
            Item(item: Decimal(string: "987654321.123")!, parameters: [:]),
            try StructuredFieldDecoder().decodeItemField(Item.self, from: Array(headerFieldNoParameters.utf8))
        )

        XCTAssertEqual(
            Item(item: Decimal(string: "987654321.123")!, parameters: ["q": 0.8]),
            try StructuredFieldDecoder().decodeItemField(Item.self, from: Array(headerFieldParameters.utf8))
        )
    }

    func testDecodingDecimalInParameterField() throws {
        struct Item: Codable, Equatable {
            var item: Int
            var parameters: [String: Decimal]
        }

        let headerField = "1;q=987654321.123"
        XCTAssertEqual(
            Item(item: 1, parameters: ["q": Decimal(string: "987654321.123")!]),
            try StructuredFieldDecoder().decodeItemField(Item.self, from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalInOuterListRaw() throws {
        let headerField = "987654321.123, 123456789.321"
        XCTAssertEqual(
            [Decimal(string: "987654321.123")!, Decimal(string: "123456789.321")!],
            try StructuredFieldDecoder().decodeListField([Decimal].self, from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalInInnerListRaw() throws {
        let headerField = "(987654321.123 123456789.321), (987654321.123 123456789.321)"
        XCTAssertEqual(
            Array(repeating: [Decimal(string: "987654321.123")!, Decimal(string: "123456789.321")!], count: 2),
            try StructuredFieldDecoder().decodeListField([[Decimal]].self, from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalInInnerListKeyed() throws {
        struct ListField: Codable, Equatable {
            var items: [Decimal]
            var parameters: [String: Bool]
        }
        let headerField = "(987654321.123 123456789.321);foo, (987654321.123 123456789.321);foo"
        XCTAssertEqual(
            Array(repeating: ListField(items: [Decimal(string: "987654321.123")!, Decimal(string: "123456789.321")!], parameters: ["foo": true]), count: 2),
            try StructuredFieldDecoder().decodeListField([ListField].self, from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalInDictionaries() throws {
        struct DictionaryField: Codable, Equatable {
            var bin: Decimal
            var box: Decimal
        }

        let headerField = "bin=987654321.123, box=123456789.321"
        XCTAssertEqual(
            DictionaryField(bin: Decimal(string: "987654321.123")!, box: Decimal(string: "123456789.321")!),
            try StructuredFieldDecoder().decodeDictionaryField(DictionaryField.self, from: Array(headerField.utf8))
        )
    }
}
