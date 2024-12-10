//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import Foundation
import RawStructuredFieldValues
import StructuredFieldValues
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

struct ItemField<Base: Codable & Equatable>: StructuredFieldValue, Equatable {
    static var structuredFieldType: StructuredFieldType {
        .item
    }

    var item: Base

    init(_ item: Base) {
        self.item = item
    }
}

struct List<Base: Codable & Equatable>: StructuredFieldValue, Equatable {
    static var structuredFieldType: StructuredFieldType {
        .list
    }

    var items: [Base]

    init(_ items: [Base]) {
        self.items = items
    }
}

struct DictionaryField<Key: Codable & Hashable, Value: Codable & Equatable>: StructuredFieldValue, Equatable {
    static var structuredFieldType: StructuredFieldType {
        .dictionary
    }

    var items: [Key: Value]

    init(_ items: [Key: Value]) {
        self.items = items
    }

    func encode(to encoder: Encoder) throws {
        try self.items.encode(to: encoder)
    }

    init(from decoder: Decoder) throws {
        self.items = try .init(from: decoder)
    }
}

/// An example ListyDictionary structured header field.
///
/// An example of this field is: 'primary=bar;q=1.0, secondary=baz;q=0.5;fallback=last, acceptablejurisdictions=(AU;q=1.0 GB;q=0.9 FR);fallback=primary'
struct ListyDictionaryField: StructuredFieldValue, Equatable {
    static let structuredFieldType: StructuredFieldType = .dictionary

    var primary: ListyDictionaryParameterisedString
    var secondary: ListyDictionaryParameterisedString
    var acceptablejurisdictions: ListyDictionaryParameterisedList
}

final class StructuredFieldDecoderTests: XCTestCase {
    func testSimpleCodableDecode() throws {
        let headerField =
            "primary=bar;q=1.0, secondary=baz;q=0.5;fallback=last, acceptablejurisdictions=(AU;q=1.0 GB;q=0.9 FR);fallback=\"primary\""
        let parsed = try StructuredFieldValueDecoder().decode(ListyDictionaryField.self, from: Array(headerField.utf8))
        let expected = ListyDictionaryField(
            primary: .init(item: "bar", parameters: .init(q: 1, fallback: nil)),
            secondary: .init(item: "baz", parameters: .init(q: 0.5, fallback: "last")),
            acceptablejurisdictions: .init(
                items: [
                    .init(item: "AU", parameters: .init(q: 1, fallback: nil)),
                    .init(item: "GB", parameters: .init(q: 0.9, fallback: nil)),
                    .init(item: "FR", parameters: .init(q: nil, fallback: nil)),
                ],
                parameters: .init(q: nil, fallback: "primary")
            )
        )
        XCTAssertEqual(parsed, expected)
    }

    func testCanDecodeParameterisedItemsWithoutParameters() throws {
        struct ListyDictionaryNoParams: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .dictionary

            var primary: String
            var secondary: String
            var acceptablejurisdictions: [String]
        }
        let headerField =
            "primary=bar;q=1.0, secondary=baz;q=0.5;fallback=last, acceptablejurisdictions=(AU;q=1.0 GB;q=0.9 FR);fallback=\"primary\""
        let parsed = try StructuredFieldValueDecoder().decode(
            ListyDictionaryNoParams.self,
            from: Array(headerField.utf8)
        )
        let expected = ListyDictionaryNoParams(
            primary: "bar",
            secondary: "baz",
            acceptablejurisdictions: ["AU", "GB", "FR"]
        )
        XCTAssertEqual(parsed, expected)
    }

    func testCanDecodeIntegersInVariousWays() throws {
        let headerField = "5;bar=baz"

        XCTAssertEqual(ItemField(UInt8(5)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(ItemField(Int8(5)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(ItemField(UInt16(5)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(ItemField(Int16(5)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(ItemField(UInt32(5)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(ItemField(Int32(5)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(ItemField(UInt64(5)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(ItemField(Int64(5)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(ItemField(UInt(5)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(ItemField(Int(5)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
    }

    func testOutOfRangeNumbersAreReported() throws {
        // Most-negative supported integer value is -999,999,999,999,999. This will fit into a
        // 64-bit integer, but no other integer type. Let's validate that this throws errors
        // rather than crashing for all non-Int64 types. (Ignoring Int/UInt due to their platform
        // dependence)
        let headerField = "-999999999999999;bar=baz"
        let expected = ItemField(Int64(-999_999_999_999_999))

        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<Int8>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<UInt8>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<Int16>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<UInt16>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<Int32>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<UInt32>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<UInt64>.self, from: Array(headerField.utf8))
        )
        XCTAssertEqual(expected, try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
    }

    func testDoubleAndFloatInterchangeable() throws {
        let headerField = "5.0;bar=baz"

        XCTAssertEqual(ItemField(Float(5.0)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
        XCTAssertEqual(ItemField(Double(5.0)), try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
    }

    func testAskingForTheWrongType() throws {
        let headerField = "gzip"
        let intField = "5"

        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<Int8>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<UInt8>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<Int16>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<UInt16>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<Int32>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<UInt32>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<Int64>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<UInt64>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<Double>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<Float>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<Bool>.self, from: Array(headerField.utf8))
        )
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(ItemField<String>.self, from: Array(intField.utf8))
        )
    }

    func testDecodingTopLevelItemWithParameters() throws {
        struct IntWithParams: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item

            var item: Int
            var parameters: [String: String]
        }

        let headerField = "5;bar=baz"
        let expected = IntWithParams(item: 5, parameters: ["bar": "baz"])
        XCTAssertEqual(expected, try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
    }

    func testDecodingTopLevelList() throws {
        let headerField = "foo, bar, baz"
        let expected = List(["foo", "bar", "baz"])
        XCTAssertEqual(expected, try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8)))
    }

    func testDecodingLowercaseKeyStrategy() throws {
        struct Camel: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .dictionary

            var hasHump: Bool
        }

        let headerField = "hashump"
        let expected = Camel(hasHump: true)
        var decoder = StructuredFieldValueDecoder()
        decoder.keyDecodingStrategy = .lowercase

        XCTAssertEqual(expected, try decoder.decode(from: Array(headerField.utf8)))
    }

    func testDecodingLowercaseKeyStrategyParameters() throws {
        struct CamelParameters: Codable, Equatable {
            var hasHump: Bool
        }

        struct Camel: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item

            var item: String
            var parameters: CamelParameters
        }

        let headerField = "dromedary;hashump"
        let expected = Camel(item: "dromedary", parameters: .init(hasHump: true))
        var decoder = StructuredFieldValueDecoder()
        decoder.keyDecodingStrategy = .lowercase

        XCTAssertEqual(expected, try decoder.decode(from: Array(headerField.utf8)))
    }

    func testDecodingKeyMissingFromDictionary() throws {
        struct MissingKey: StructuredFieldValue {
            static let structuredFieldType: StructuredFieldType = .dictionary
            var foo: Int
        }

        let headerField = "bar=baz"
        XCTAssertThrowsError(try StructuredFieldValueDecoder().decode(MissingKey.self, from: Array(headerField.utf8)))
    }

    func testDecodingKeyAsItemWantedInnerList() throws {
        struct MissingInnerList: StructuredFieldValue {
            static let structuredFieldType: StructuredFieldType = .dictionary
            var innerlist: [String]
        }

        let headerField = "innerlist=x"
        XCTAssertThrowsError(
            try StructuredFieldValueDecoder().decode(MissingInnerList.self, from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryAsTopLevelData() throws {
        let headerField = ":AQIDBA==:"
        XCTAssertEqual(
            ItemField(Data([1, 2, 3, 4])),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryAsParameterisedData() throws {
        struct Item: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: Data
            var parameters: [String: Float]
        }

        let headerFieldNoParameters = ":AQIDBA==:"
        let headerFieldParameters = ":AQIDBA==:;q=0.8"

        XCTAssertEqual(
            Item(item: Data([1, 2, 3, 4]), parameters: [:]),
            try StructuredFieldValueDecoder().decode(Item.self, from: Array(headerFieldNoParameters.utf8))
        )

        XCTAssertEqual(
            Item(item: Data([1, 2, 3, 4]), parameters: ["q": 0.8]),
            try StructuredFieldValueDecoder().decode(Item.self, from: Array(headerFieldParameters.utf8))
        )
    }

    func testDecodingBinaryInParameterField() throws {
        struct Item: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: Int
            var parameters: [String: Data]
        }

        let headerField = "1;q=:AQIDBA==:"
        XCTAssertEqual(
            Item(item: 1, parameters: ["q": Data([1, 2, 3, 4])]),
            try StructuredFieldValueDecoder().decode(Item.self, from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryInOuterListRaw() throws {
        let headerField = ":AQIDBA==:, :BQYHCA==:"
        XCTAssertEqual(
            List([Data([1, 2, 3, 4]), Data([5, 6, 7, 8])]),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryInOuterListKeyed() throws {
        let headerField = ":AQIDBA==:, :BQYHCA==:"
        XCTAssertEqual(
            List([Data([1, 2, 3, 4]), Data([5, 6, 7, 8])]),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryInInnerListRaw() throws {
        let headerField = "(:AQIDBA==: :BQYHCA==:), (:AQIDBA==: :BQYHCA==:)"
        XCTAssertEqual(
            List(Array(repeating: [Data([1, 2, 3, 4]), Data([5, 6, 7, 8])], count: 2)),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryInInnerListKeyed() throws {
        struct ListField: Codable, Equatable {
            var items: [Data]
            var parameters: [String: Bool]
        }
        let headerField = "(:AQIDBA==: :BQYHCA==:);foo, (:AQIDBA==: :BQYHCA==:);foo"
        XCTAssertEqual(
            List(
                Array(
                    repeating: ListField(items: [Data([1, 2, 3, 4]), Data([5, 6, 7, 8])], parameters: ["foo": true]),
                    count: 2
                )
            ),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingBinaryInDictionaries() throws {
        struct DictionaryField: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .dictionary
            var bin: Data
            var box: Data
        }

        let headerField = "bin=:AQIDBA==:, box=:AQIDBA==:"
        XCTAssertEqual(
            DictionaryField(bin: Data([1, 2, 3, 4]), box: Data([1, 2, 3, 4])),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalAsTopLevelData() throws {
        let headerField = "987654321.123"
        XCTAssertEqual(
            ItemField(Decimal(string: "987654321.123")!),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalAsParameterisedData() throws {
        struct Item: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: Decimal
            var parameters: [String: Float]
        }

        let headerFieldNoParameters = "987654321.123"
        let headerFieldParameters = "987654321.123;q=0.8"

        XCTAssertEqual(
            Item(item: Decimal(string: "987654321.123")!, parameters: [:]),
            try StructuredFieldValueDecoder().decode(from: Array(headerFieldNoParameters.utf8))
        )

        XCTAssertEqual(
            Item(item: Decimal(string: "987654321.123")!, parameters: ["q": 0.8]),
            try StructuredFieldValueDecoder().decode(from: Array(headerFieldParameters.utf8))
        )
    }

    func testDecodingDecimalInParameterField() throws {
        struct Item: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: Int
            var parameters: [String: Decimal]
        }

        let headerField = "1;q=987654321.123"
        XCTAssertEqual(
            Item(item: 1, parameters: ["q": Decimal(string: "987654321.123")!]),
            try StructuredFieldValueDecoder().decode(Item.self, from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalInOuterListRaw() throws {
        let headerField = "987654321.123, 123456789.321"
        XCTAssertEqual(
            List([Decimal(string: "987654321.123")!, Decimal(string: "123456789.321")!]),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalInInnerListRaw() throws {
        let headerField = "(987654321.123 123456789.321), (987654321.123 123456789.321)"
        XCTAssertEqual(
            List(Array(repeating: [Decimal(string: "987654321.123")!, Decimal(string: "123456789.321")!], count: 2)),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalInInnerListKeyed() throws {
        struct ListField: Codable, Equatable {
            var items: [Decimal]
            var parameters: [String: Bool]
        }
        let headerField = "(987654321.123 123456789.321);foo, (987654321.123 123456789.321);foo"
        XCTAssertEqual(
            List(
                Array(
                    repeating: ListField(
                        items: [Decimal(string: "987654321.123")!, Decimal(string: "123456789.321")!],
                        parameters: ["foo": true]
                    ),
                    count: 2
                )
            ),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingDecimalInDictionaries() throws {
        struct DictionaryField: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .dictionary
            var bin: Decimal
            var box: Decimal
        }

        let headerField = "bin=987654321.123, box=123456789.321"
        XCTAssertEqual(
            DictionaryField(bin: Decimal(string: "987654321.123")!, box: Decimal(string: "123456789.321")!),
            try StructuredFieldValueDecoder().decode(DictionaryField.self, from: Array(headerField.utf8))
        )
    }

    func testDecodingDateAsTopLevelData() throws {
        let headerField = "@4294967296"
        XCTAssertEqual(
            ItemField(Date(timeIntervalSince1970: 4_294_967_296)),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingDateAsParameterisedData() throws {
        struct Item: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: Date
            var parameters: [String: Float]
        }

        let headerFieldNoParameters = "@4294967296"
        let headerFieldParameters = "@4294967296;q=0.8"

        XCTAssertEqual(
            Item(
                item: Date(timeIntervalSince1970: 4_294_967_296),
                parameters: [:]
            ),
            try StructuredFieldValueDecoder().decode(
                Item.self,
                from: Array(headerFieldNoParameters.utf8)
            )
        )

        XCTAssertEqual(
            Item(item: Date(timeIntervalSince1970: 4_294_967_296), parameters: ["q": 0.8]),
            try StructuredFieldValueDecoder().decode(
                Item.self,
                from: Array(headerFieldParameters.utf8)
            )
        )
    }

    func testDecodingDateInParameterField() throws {
        struct Item: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: Int
            var parameters: [String: Date]
        }

        let headerField = "1;q=@4294967296"
        XCTAssertEqual(
            Item(item: 1, parameters: ["q": Date(timeIntervalSince1970: 4_294_967_296)]),
            try StructuredFieldValueDecoder().decode(Item.self, from: Array(headerField.utf8))
        )
    }

    func testDecodingDateInOuterListRaw() throws {
        let headerField = "@4294967296, @-1659578233"
        XCTAssertEqual(
            List(
                [
                    Date(timeIntervalSince1970: 4_294_967_296),
                    Date(timeIntervalSince1970: -1_659_578_233),
                ]
            ),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingDateInInnerListRaw() throws {
        let headerField = "(@4294967296 @-1659578233), (@4294967296 @-1659578233)"
        XCTAssertEqual(
            List(
                Array(
                    repeating: [
                        Date(timeIntervalSince1970: 4_294_967_296),
                        Date(timeIntervalSince1970: -1_659_578_233),
                    ],
                    count: 2
                )
            ),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingDateInInnerListKeyed() throws {
        struct ListField: Codable, Equatable {
            var items: [Date]
            var parameters: [String: Bool]
        }
        let headerField = "(@4294967296 @-1659578233);foo, (@4294967296 @-1659578233);foo"
        XCTAssertEqual(
            List(
                Array(
                    repeating: ListField(
                        items: [
                            Date(timeIntervalSince1970: 4_294_967_296),
                            Date(timeIntervalSince1970: -1_659_578_233),
                        ],
                        parameters: ["foo": true]
                    ),
                    count: 2
                )
            ),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingDateInDictionaries() throws {
        struct DictionaryField: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .dictionary
            var bin: Date
            var box: Date
        }

        let headerField = "bin=@4294967296, box=@-1659578233"
        XCTAssertEqual(
            DictionaryField(
                bin: Date(timeIntervalSince1970: 4_294_967_296),
                box: Date(timeIntervalSince1970: -1_659_578_233)
            ),
            try StructuredFieldValueDecoder().decode(from: Array(headerField.utf8))
        )
    }

    func testDecodingDisplayStringAsTopLevelData() throws {
        XCTAssertEqual(
            ItemField(DisplayString(rawValue: "füü")),
            try StructuredFieldValueDecoder().decode(from: Array("%\"f%c3%bc%c3%bc\"".utf8))
        )
    }

    func testDecodingDisplayStringAsParameterisedData() throws {
        struct Item: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: DisplayString
            var parameters: [String: Float]
        }

        XCTAssertEqual(
            Item(
                item: DisplayString(rawValue: "füü"),
                parameters: [:]
            ),
            try StructuredFieldValueDecoder().decode(
                Item.self,
                from: Array("%\"f%c3%bc%c3%bc\"".utf8)
            )
        )

        XCTAssertEqual(
            Item(item: DisplayString(rawValue: "füü"), parameters: ["q": 0.8]),
            try StructuredFieldValueDecoder().decode(
                Item.self,
                from: Array("%\"f%c3%bc%c3%bc\";q=0.8".utf8)
            )
        )
    }

    func testDecodingDisplayStringInParameterField() throws {
        struct Item: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: Int
            var parameters: [String: DisplayString]
        }

        XCTAssertEqual(
            Item(item: 1, parameters: ["q": DisplayString(rawValue: "füü")]),
            try StructuredFieldValueDecoder().decode(
                Item.self,
                from: Array("1;q=%\"f%c3%bc%c3%bc\"".utf8)
            )
        )
    }

    func testDecodingDisplayStringInOuterListRaw() throws {
        XCTAssertEqual(
            List(
                [
                    DisplayString(rawValue: "füü"),
                    DisplayString(rawValue: "foo \"bar\" \\ baz"),
                ]
            ),
            try StructuredFieldValueDecoder().decode(
                from: Array("%\"f%c3%bc%c3%bc\", %\"foo %22bar%22 \\ baz\"".utf8)
            )
        )
    }

    func testDecodingDisplayStringInInnerListRaw() throws {
        XCTAssertEqual(
            List(
                Array(
                    repeating: [
                        DisplayString(rawValue: "füü"),
                        DisplayString(rawValue: "foo \"bar\" \\ baz"),
                    ],
                    count: 2
                )
            ),
            try StructuredFieldValueDecoder().decode(
                from: Array(
                    """
                    (%\"f%c3%bc%c3%bc\" %\"foo %22bar%22 \\ baz\"), (%\"f%c3%bc%c3%bc\" %\"foo \
                    %22bar%22 \\ baz\")
                    """.utf8
                )
            )
        )
    }

    func testDecodingDisplayStringInInnerListKeyed() throws {
        struct ListField: Codable, Equatable {
            var items: [DisplayString]
            var parameters: [String: Bool]
        }
        XCTAssertEqual(
            List(
                Array(
                    repeating: ListField(
                        items: [
                            DisplayString(rawValue: "füü"),
                            DisplayString(rawValue: "foo \"bar\" \\ baz"),
                        ],
                        parameters: ["foo": true]
                    ),
                    count: 2
                )
            ),
            try StructuredFieldValueDecoder().decode(
                from: Array(
                    """
                    (%\"f%c3%bc%c3%bc\" %\"foo %22bar%22 \\ baz\");foo, (%\"f%c3%bc%c3%bc\" %\"foo \
                    %22bar%22 \\ baz\");foo
                    """.utf8
                )
            )
        )
    }

    func testDecodingDisplayStringInDictionaries() throws {
        struct DictionaryField: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .dictionary
            var bin: DisplayString
            var box: DisplayString
        }

        XCTAssertEqual(
            DictionaryField(
                bin: DisplayString(rawValue: "füü"),
                box: DisplayString(rawValue: "foo \"bar\" \\ baz")
            ),
            try StructuredFieldValueDecoder().decode(
                from: Array("bin=%\"f%c3%bc%c3%bc\", box=%\"foo %22bar%22 \\ baz\"".utf8)
            )
        )
    }
}
