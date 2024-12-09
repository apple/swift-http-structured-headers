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

// swift-format-ignore: DontRepeatTypeInStaticProperties
final class StructuredFieldEncoderTests: XCTestCase {
    func testSimpleItemHeaderEncodeBareItem() throws {
        // We're going to try encoding a few bare items as item headers to confirm
        // that functions.
        let encoder = StructuredFieldValueEncoder()

        // Bool
        XCTAssertEqual(Array("?1".utf8), try encoder.encode(ItemField(true)))
        XCTAssertEqual(Array("?0".utf8), try encoder.encode(ItemField(false)))

        // String and token
        XCTAssertEqual(Array("\"hello, world\"".utf8), try encoder.encode(ItemField("hello, world")))
        XCTAssertEqual(Array("gzip".utf8), try encoder.encode(ItemField("gzip")))

        // Integer
        XCTAssertEqual(Array("10".utf8), try encoder.encode(ItemField(UInt8(10))))
        XCTAssertEqual(Array("-10".utf8), try encoder.encode(ItemField(Int64(-10))))

        // Decimal
        XCTAssertEqual(Array("102.2".utf8), try encoder.encode(ItemField(Float(102.2))))
        XCTAssertEqual(Array("-166.66".utf8), try encoder.encode(ItemField(Double(-166.66))))
        XCTAssertEqual(Array("987654321.123".utf8), try encoder.encode(ItemField(Decimal(string: "987654321.123")!)))
        XCTAssertEqual(Array("-123456789.321".utf8), try encoder.encode(ItemField(Decimal(string: "-123456789.321")!)))

        // Binary Data
        XCTAssertEqual(Array(":AQIDBA==:".utf8), try encoder.encode(ItemField(Data([1, 2, 3, 4]))))

        // Date
        XCTAssertEqual(
            Array("@4294967296".utf8),
            try encoder.encode(ItemField(Date(timeIntervalSince1970: 4_294_967_296)))
        )
        XCTAssertEqual(
            Array("@-1659578233".utf8),
            try encoder.encode(ItemField(Date(timeIntervalSince1970: -1_659_578_233)))
        )

        // Display String
        XCTAssertEqual(
            Array("%\"f%c3%bc%c3%bc\"".utf8),
            try encoder.encode(ItemField(DisplayString(rawValue: "füü")))
        )
    }

    func testEncodeKeyedItemHeader() throws {
        struct KeyedItem<ItemType: Codable & Equatable>: Equatable, StructuredFieldValue {
            static var structuredFieldType: StructuredFieldType {
                .item
            }

            var item: ItemType
            var parameters: [String: Bool]
        }

        let encoder = StructuredFieldValueEncoder()

        // Bool
        XCTAssertEqual(Array("?1;x".utf8), try encoder.encode(KeyedItem(item: true, parameters: ["x": true])))
        XCTAssertEqual(Array("?0;x=?0".utf8), try encoder.encode(KeyedItem(item: false, parameters: ["x": false])))

        // String and token
        XCTAssertEqual(
            Array("\"hello, world\"".utf8),
            try encoder.encode(KeyedItem(item: "hello, world", parameters: [:]))
        )
        XCTAssertEqual(Array("gzip;x".utf8), try encoder.encode(KeyedItem(item: "gzip", parameters: ["x": true])))

        // Integer
        XCTAssertEqual(Array("10;x".utf8), try encoder.encode(KeyedItem(item: UInt16(10), parameters: ["x": true])))
        XCTAssertEqual(Array("-10".utf8), try encoder.encode(KeyedItem(item: Int32(-10), parameters: [:])))

        // Decimal
        XCTAssertEqual(
            Array("102.2;y=?0".utf8),
            try encoder.encode(KeyedItem(item: Float(102.2), parameters: ["y": false]))
        )
        XCTAssertEqual(Array("-166.66".utf8), try encoder.encode(KeyedItem(item: Double(-166.66), parameters: [:])))
        XCTAssertEqual(
            Array("987654321.123;y=?0".utf8),
            try encoder.encode(KeyedItem(item: Decimal(string: "987654321.123")!, parameters: ["y": false]))
        )
        XCTAssertEqual(
            Array("-123456789.321".utf8),
            try encoder.encode(KeyedItem(item: Decimal(string: "-123456789.321")!, parameters: [:]))
        )

        // Binary
        XCTAssertEqual(
            Array(":AQIDBA==:;y=?0".utf8),
            try encoder.encode(KeyedItem(item: Data([1, 2, 3, 4]), parameters: ["y": false]))
        )
        XCTAssertEqual(
            Array(":AQIDBA==:".utf8),
            try encoder.encode(KeyedItem(item: Data([1, 2, 3, 4]), parameters: [:]))
        )

        // Date
        XCTAssertEqual(
            Array("@4294967296;x".utf8),
            try encoder.encode(
                KeyedItem(
                    item: Date(timeIntervalSince1970: 4_294_967_296),
                    parameters: ["x": true]
                )
            )
        )
        XCTAssertEqual(
            Array("@-1659578233".utf8),
            try encoder.encode(
                KeyedItem(
                    item: Date(timeIntervalSince1970: -1_659_578_233),
                    parameters: [:]
                )
            )
        )

        // Display String
        XCTAssertEqual(
            Array("%\"f%c3%bc%c3%bc\";x".utf8),
            try encoder.encode(
                KeyedItem(item: DisplayString(rawValue: "füü"), parameters: ["x": true])
            )
        )
        XCTAssertEqual(
            Array("%\"foo %22bar%22 \\ baz\"".utf8),
            try encoder.encode(
                KeyedItem(item: DisplayString(rawValue: "foo \"bar\" \\ baz"), parameters: [:])
            )
        )
    }

    func testEncodeKeyedItemHeaderWithParamsAsStruct() throws {
        struct Parameters: Equatable, Codable {
            var x: Bool?
            var q: Float?
        }

        struct Field: Equatable, StructuredFieldValue {
            static let structuredFieldType: StructuredFieldType = .item
            var item: String
            var parameters: Parameters
        }

        let encoder = StructuredFieldValueEncoder()

        XCTAssertEqual(
            Array("gzip;x;q=0.8".utf8),
            try encoder.encode(Field(item: "gzip", parameters: Parameters(x: true, q: 0.8)))
        )
        XCTAssertEqual(
            Array("deflate;q=0.6".utf8),
            try encoder.encode(Field(item: "deflate", parameters: Parameters(x: nil, q: 0.6)))
        )
        XCTAssertEqual(
            Array("zlib".utf8),
            try encoder.encode(Field(item: "zlib", parameters: Parameters(x: nil, q: nil)))
        )
    }

    func testEncodeSimpleDictionary() throws {
        let encoder = StructuredFieldValueEncoder()

        struct DictionaryField: StructuredFieldValue {
            static let structuredFieldType: StructuredFieldType = .dictionary
            var x: Bool
            var y: Bool
        }

        let result = try encoder.encode(DictionaryField(x: true, y: false))
        let possibilities = [Array("x, y=?0".utf8), Array("y=?0, x".utf8)]
        XCTAssertTrue(possibilities.contains(result), "\(possibilities) does not contain \(result)")
    }

    func testEncodeDictionaryOfParameterisedItems() throws {
        struct Field: Equatable, Codable {
            var item: Int
            var parameters: [String: Float]
        }

        struct DictionaryField: StructuredFieldValue {
            static let structuredFieldType: StructuredFieldType = .dictionary
            var x: Field
        }

        let encoder = StructuredFieldValueEncoder()

        XCTAssertEqual(
            Array("x=66;q=0.8".utf8),
            try encoder.encode(DictionaryField(x: Field(item: 66, parameters: ["q": 0.8])))
        )
    }

    func testSimpleListField() throws {
        let encoder = StructuredFieldValueEncoder()

        // Bool
        XCTAssertEqual(
            Array("?1, ?0, ?1".utf8),
            try encoder.encode(List([true, false, true]))
        )

        // String and token
        XCTAssertEqual(
            Array("\"hello, world\", gzip".utf8),
            try encoder.encode(List(["hello, world", "gzip"]))
        )

        // Integer
        XCTAssertEqual(Array("10, -10".utf8), try encoder.encode(List([Int16(10), Int16(-10)])))

        // Decimal
        XCTAssertEqual(Array("102.2, -166.66".utf8), try encoder.encode(List([Float(102.2), Float(-166.66)])))
        XCTAssertEqual(
            Array("123456789.321, -987654321.123".utf8),
            try encoder.encode(List([Decimal(string: "123456789.321")!, Decimal(string: "-987654321.123")!]))
        )

        // Binary
        XCTAssertEqual(
            Array(":AQIDBA==:, :BQYHCA==:".utf8),
            try encoder.encode(List([Data([1, 2, 3, 4]), Data([5, 6, 7, 8])]))
        )

        // Date
        XCTAssertEqual(
            Array("@4294967296, @-1659578233".utf8),
            try encoder.encode(
                List(
                    [
                        Date(timeIntervalSince1970: 4_294_967_296),
                        Date(timeIntervalSince1970: -1_659_578_233),
                    ]
                )
            )
        )

        // Display String
        XCTAssertEqual(
            Array("%\"f%c3%bc%c3%bc\", %\"foo %22bar%22 \\ baz\"".utf8),
            try encoder.encode(
                List(
                    [DisplayString(rawValue: "füü"), DisplayString(rawValue: "foo \"bar\" \\ baz")]
                )
            )
        )
    }

    func testListFieldInnerItemsWithDict() throws {
        struct Item: Equatable, Codable {
            var parameters: [String: Float]
            var item: String
        }

        let encoder = StructuredFieldValueEncoder()
        let header = [
            Item(parameters: ["q": 0.8], item: "gzip"),
            Item(parameters: ["q": 0.6], item: "deflate"),
        ]

        XCTAssertEqual(
            Array("gzip;q=0.8, deflate;q=0.6".utf8),
            try encoder.encode(List(header))
        )
    }

    func testListFieldInnerItemsWithObject() throws {
        struct Parameters: Equatable, Codable {
            var q: Float?
        }

        struct Item: Equatable, Codable {
            var item: String
            var parameters: Parameters
        }

        let encoder = StructuredFieldValueEncoder()
        let header = [
            Item(item: "gzip", parameters: Parameters(q: 0.8)),
            Item(item: "deflate", parameters: Parameters(q: nil)),
        ]

        XCTAssertEqual(
            Array("gzip;q=0.8, deflate".utf8),
            try encoder.encode(List(header))
        )
    }

    func testListFieldInnerListsBare() throws {
        let encoder = StructuredFieldValueEncoder()
        let header = [[1, 2, 3], [4, 5, 6]]
        XCTAssertEqual(Array("(1 2 3), (4 5 6)".utf8), try encoder.encode(List(header)))
    }

    func testListFieldInnerListsParameters() throws {
        struct Integers: Equatable, Codable {
            var items: [Int]
            var parameters: [String: String]
        }

        let encoder = StructuredFieldValueEncoder()
        let header = [
            Integers(items: [1, 2, 3], parameters: ["early": "yes"]),
            Integers(items: [4, 5, 6], parameters: ["early": "no"]),
        ]
        XCTAssertEqual(Array("(1 2 3);early=yes, (4 5 6);early=no".utf8), try encoder.encode(List(header)))
    }

    func testListFieldInnerListElementsWithParameters() throws {
        struct Item: Equatable, Codable {
            var item: Int
            var parameters: [String: Bool]
        }

        let encoder = StructuredFieldValueEncoder()
        let header = [
            [
                Item(item: 1, parameters: ["odd": true]),
                Item(item: 2, parameters: ["odd": false]),
            ],
            [
                Item(item: 3, parameters: ["odd": true]),
                Item(item: 4, parameters: ["odd": false]),
            ],
        ]
        XCTAssertEqual(
            Array("(1;odd 2;odd=?0), (3;odd 4;odd=?0)".utf8),
            try encoder.encode(List(header))
        )
    }

    func testListFieldExplicitInnerListsWithItemsWithParameters() throws {
        struct ItemParams: Equatable, Codable {
            var q: Float
        }

        struct Item: Equatable, Codable {
            var item: String
            var parameters: ItemParams
        }

        struct FieldParams: Equatable, Codable {
            var sorted: Bool
        }

        struct Fields: Equatable, Codable {
            var items: [Item]
            var parameters: FieldParams
        }

        let encoder = StructuredFieldValueEncoder()
        let header = [
            Fields(
                items: [
                    Item(item: "gzip", parameters: ItemParams(q: 0.8)),
                    Item(item: "deflate", parameters: ItemParams(q: 0.6)),
                ],
                parameters: FieldParams(sorted: true)
            ),
            Fields(
                items: [
                    Item(item: "zlib", parameters: ItemParams(q: 0.4)),
                    Item(item: "br", parameters: ItemParams(q: 1.0)),
                ],
                parameters: FieldParams(sorted: false)
            ),
        ]
        XCTAssertEqual(
            Array("(gzip;q=0.8 deflate;q=0.6);sorted, (zlib;q=0.4 br;q=1.0);sorted=?0".utf8),
            try encoder.encode(List(header))
        )
    }

    func testDictionaryFieldWithSimpleInnerLists() throws {
        struct Field: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .dictionary
            var name: String
            var color: String?
            var intensity: [Float]
        }

        let encoder = StructuredFieldValueEncoder()
        XCTAssertEqual(
            Array("name=red, intensity=(1.0 0.0 0.0)".utf8),
            try encoder.encode(Field(name: "red", color: nil, intensity: [1.0, 0.0, 0.0]))
        )
    }

    func testDictionaryFieldWithComplexInnerLists() throws {
        struct ColorParameters: Codable, Equatable {
            var name: String?
        }

        struct Color: Codable, Equatable {
            var items: [Float]
            var parameters: ColorParameters
        }

        struct Field: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .dictionary
            var green: Color
        }

        let encoder = StructuredFieldValueEncoder()
        let field = Field(
            green: Color(items: [0.0, 1.0, 0.0], parameters: ColorParameters(name: "green"))
        )
        XCTAssertEqual(
            Array("green=(0.0 1.0 0.0);name=green".utf8),
            try encoder.encode(field)
        )
    }

    func testEmptyListField() throws {
        let encoder = StructuredFieldValueEncoder()
        XCTAssertEqual([], try encoder.encode(List([] as [Int])))
    }

    func testEmptyDictionaryField() throws {
        struct Field: StructuredFieldValue {
            static let structuredFieldType: StructuredFieldType = .dictionary
        }
        let encoder = StructuredFieldValueEncoder()
        XCTAssertEqual([], try encoder.encode(Field()))
    }

    func testEmptyItemField() throws {
        struct Field: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: Int?
        }
        let encoder = StructuredFieldValueEncoder()
        XCTAssertEqual([], try encoder.encode(Field(item: nil)))
        XCTAssertThrowsError(try encoder.encode(List([Field(item: nil)])))
        XCTAssertThrowsError(try encoder.encode(DictionaryField(["x": Field(item: nil)])))
    }

    func testForbidEmptyItemWithActualParameters() throws {
        struct Field: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: Int?
            var parameters: [String: Int]
        }

        let encoder = StructuredFieldValueEncoder()
        let badField = Field(item: nil, parameters: ["x": 0])
        XCTAssertThrowsError(try encoder.encode(badField))
        XCTAssertThrowsError(try encoder.encode(List([badField])))
        XCTAssertThrowsError(try encoder.encode(DictionaryField(["x": badField])))
    }

    func testForbidItemWithExtraField() throws {
        struct Field: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: Int
            var parameters: [String: Int]
            var other: Bool
        }

        let encoder = StructuredFieldValueEncoder()
        let badField = Field(item: 1, parameters: ["x": 0], other: true)
        XCTAssertThrowsError(try encoder.encode(badField))
        XCTAssertThrowsError(try encoder.encode(List([badField])))
        XCTAssertThrowsError(try encoder.encode(DictionaryField(["x": badField])))
    }

    func testForbidJustParameters() throws {
        struct Field: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var parameters: [String: Int]
        }

        let encoder = StructuredFieldValueEncoder()
        let badField = Field(parameters: ["x": 0])
        XCTAssertThrowsError(try encoder.encode(badField))
        XCTAssertThrowsError(try encoder.encode(List([badField])))
        XCTAssertThrowsError(try encoder.encode(DictionaryField(["x": badField])))
    }

    func testForbidNullInnerList() throws {
        struct Field: Codable, Equatable {
            var items: Int?
        }
        let encoder = StructuredFieldValueEncoder()
        XCTAssertThrowsError(try encoder.encode(List([Field(items: nil)])))
        XCTAssertThrowsError(try encoder.encode(DictionaryField(["x": Field(items: nil)])))
    }

    func testLowercaseKeysOnDictionaries() throws {
        struct DictionaryField: StructuredFieldValue {
            static let structuredFieldType: StructuredFieldType = .dictionary
            var allowAll: Bool
        }

        let noStrategyEncoder = StructuredFieldValueEncoder()
        XCTAssertThrowsError(try noStrategyEncoder.encode(DictionaryField(allowAll: false)))

        var lowercaseEncoder = noStrategyEncoder
        lowercaseEncoder.keyEncodingStrategy = .lowercase
        XCTAssertEqual(
            Array("allowall".utf8),
            try lowercaseEncoder.encode(DictionaryField(allowAll: true))
        )
    }

    func testLowercaseKeysOnParameters() throws {
        struct Parameters: Codable, Equatable {
            var allowAll: Bool
        }

        struct ItemField: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .item
            var item: Int
            var parameters: Parameters
        }

        struct ListField: StructuredFieldValue, Equatable {
            static let structuredFieldType: StructuredFieldType = .list
            var items: [Int]
            var parameters: Parameters
        }

        let noStrategyEncoder = StructuredFieldValueEncoder()
        var lowercaseEncoder = noStrategyEncoder
        lowercaseEncoder.keyEncodingStrategy = .lowercase

        let item = ItemField(item: 1, parameters: Parameters(allowAll: true))
        let list = ListField(items: [1, 2], parameters: Parameters(allowAll: true))

        XCTAssertThrowsError(try noStrategyEncoder.encode(item))
        XCTAssertEqual(Array("1;allowall".utf8), try lowercaseEncoder.encode(item))

        XCTAssertThrowsError(try noStrategyEncoder.encode(List([item, item])))
        XCTAssertEqual(
            Array("1;allowall, 1;allowall".utf8),
            try lowercaseEncoder.encode(List([item, item]))
        )

        XCTAssertThrowsError(try noStrategyEncoder.encode(List([list])))
        XCTAssertEqual(
            Array("(1 2);allowall".utf8),
            try lowercaseEncoder.encode(List([list]))
        )

        XCTAssertThrowsError(try noStrategyEncoder.encode(DictionaryField(["item": item])))
        XCTAssertEqual(
            Array("item=1;allowall".utf8),
            try lowercaseEncoder.encode(DictionaryField(["item": item]))
        )

        XCTAssertThrowsError(try noStrategyEncoder.encode(DictionaryField(["list": list])))
        XCTAssertEqual(
            Array("list=(1 2);allowall".utf8),
            try lowercaseEncoder.encode(DictionaryField(["list": list]))
        )
    }
}
