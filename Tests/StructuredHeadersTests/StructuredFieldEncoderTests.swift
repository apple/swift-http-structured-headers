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
import CodableStructuredHeaders

final class StructuredFieldEncoderTests: XCTestCase {
    func testSimpleItemHeaderEncodeBareItem() throws {
        // We're going to try encoding a few bare items as item headers to confirm
        // that functions.
        let encoder = StructuredFieldEncoder()

        // Bool
        XCTAssertEqual(Array("?1".utf8), try encoder.encodeItemField(true))
        XCTAssertEqual(Array("?0".utf8), try encoder.encodeItemField(false))

        // String and token
        XCTAssertEqual(Array("\"hello, world\"".utf8), try encoder.encodeItemField("hello, world"))
        XCTAssertEqual(Array("gzip".utf8), try encoder.encodeItemField("gzip"))

        // Integer
        XCTAssertEqual(Array("10".utf8), try encoder.encodeItemField(UInt8(10)))
        XCTAssertEqual(Array("-10".utf8), try encoder.encodeItemField(Int64(-10)))

        // Decimal
        XCTAssertEqual(Array("102.2".utf8), try encoder.encodeItemField(Float(102.2)))
        XCTAssertEqual(Array("-166.66".utf8), try encoder.encodeItemField(Double(-166.66)))

        // Binary Data
        XCTAssertEqual(Array(":AQIDBA==:".utf8), try encoder.encodeItemField(Data([1, 2, 3, 4])))
    }

    func testEncodeKeyedItemHeader() throws {
        struct KeyedItem<ItemType: Encodable & Equatable>: Equatable, Encodable {
            var item: ItemType
            var parameters: [String: Bool]
        }

        let encoder = StructuredFieldEncoder()

        // Bool
        XCTAssertEqual(Array("?1;x".utf8), try encoder.encodeItemField(KeyedItem(item: true, parameters: ["x": true])))
        XCTAssertEqual(Array("?0;x=?0".utf8), try encoder.encodeItemField(KeyedItem(item: false, parameters: ["x": false])))

        // String and token
        XCTAssertEqual(Array("\"hello, world\"".utf8), try encoder.encodeItemField(KeyedItem(item: "hello, world", parameters: [:])))
        XCTAssertEqual(Array("gzip;x".utf8), try encoder.encodeItemField(KeyedItem(item: "gzip", parameters: ["x": true])))

        // Integer
        XCTAssertEqual(Array("10;x".utf8), try encoder.encodeItemField(KeyedItem(item: UInt16(10), parameters: ["x": true])))
        XCTAssertEqual(Array("-10".utf8), try encoder.encodeItemField(KeyedItem(item: Int32(-10), parameters: [:])))

        // Decimal
        XCTAssertEqual(Array("102.2;y=?0".utf8), try encoder.encodeItemField(KeyedItem(item: Float(102.2), parameters: ["y": false])))
        XCTAssertEqual(Array("-166.66".utf8), try encoder.encodeItemField(KeyedItem(item: Double(-166.66), parameters: [:])))

        // Binary
        XCTAssertEqual(Array(":AQIDBA==:;y=?0".utf8), try encoder.encodeItemField(KeyedItem(item: Data([1, 2, 3, 4]), parameters: ["y": false])))
        XCTAssertEqual(Array(":AQIDBA==:".utf8), try encoder.encodeItemField(KeyedItem(item: Data([1, 2, 3, 4]), parameters: [:])))
    }

    func testEncodeKeyedItemHeaderWithParamsAsStruct() throws {
        struct Parameters: Equatable, Encodable {
            var x: Bool?
            var q: Float?
        }

        struct Field: Equatable, Encodable {
            var item: String
            var parameters: Parameters
        }

        let encoder = StructuredFieldEncoder()

        XCTAssertEqual(Array("gzip;x;q=0.8".utf8), try encoder.encodeItemField(Field(item: "gzip", parameters: Parameters(x: true, q: 0.8))))
        XCTAssertEqual(Array("deflate;q=0.6".utf8), try encoder.encodeItemField(Field(item: "deflate", parameters: Parameters(x: nil, q: 0.6))))
        XCTAssertEqual(Array("zlib".utf8), try encoder.encodeItemField(Field(item: "zlib", parameters: Parameters(x: nil, q: nil))))
    }

    func testEncodeSimpleDictionary() throws {
        let encoder = StructuredFieldEncoder()

        let result = try encoder.encodeDictionaryField(["x": true, "y": false])
        let possibilities = [Array("x, y=?0".utf8), Array("y=?0, x".utf8)]
        XCTAssertTrue(possibilities.contains(result), "\(possibilities) does not contain \(result)")
    }

    func testEncodeDictionaryOfParameterisedItems() throws {
        struct Field: Equatable, Encodable {
            var item: Int
            var parameters: [String: Float]
        }

        let encoder = StructuredFieldEncoder()

        XCTAssertEqual(Array("x=66;q=0.8".utf8),
                       try encoder.encodeDictionaryField(["x": Field(item: 66, parameters: ["q": 0.8])]))
    }

    func testSimpleListField() throws {
        let encoder = StructuredFieldEncoder()

        // Bool
        XCTAssertEqual(Array("?1, ?0, ?1".utf8),
                       try encoder.encodeListField([true, false, true]))

        // String and token
        XCTAssertEqual(Array("\"hello, world\", gzip".utf8),
                       try encoder.encodeListField(["hello, world", "gzip"]))

        // Integer
        XCTAssertEqual(Array("10, -10".utf8), try encoder.encodeListField([Int16(10), Int16(-10)]))

        // Decimal
        XCTAssertEqual(Array("102.2, -166.66".utf8), try encoder.encodeListField([Float(102.2), Float(-166.66)]))

        // Binary
        XCTAssertEqual(Array(":AQIDBA==:, :BQYHCA==:".utf8),
                       try encoder.encodeListField([Data([1, 2, 3, 4]), Data([5, 6, 7, 8])]))
    }

    func testListFieldInnerItemsWithDict() throws {
        struct Item: Equatable, Encodable {
            var parameters: [String: Float]
            var item: String
        }

        let encoder = StructuredFieldEncoder()
        let header = [Item(parameters: ["q": 0.8], item: "gzip"),
                      Item(parameters: ["q": 0.6], item: "deflate"),]

        XCTAssertEqual(Array("gzip;q=0.8, deflate;q=0.6".utf8),
                       try encoder.encodeListField(header))
    }

    func testListFieldInnerItemsWithObject() throws {
        struct Parameters: Equatable, Encodable {
            var q: Float?
        }

        struct Item: Equatable, Encodable {
            var item: String
            var parameters: Parameters
        }

        let encoder = StructuredFieldEncoder()
        let header = [Item(item: "gzip", parameters: Parameters(q: 0.8)),
                      Item(item: "deflate", parameters: Parameters(q: nil))]

        XCTAssertEqual(Array("gzip;q=0.8, deflate".utf8),
                       try encoder.encodeListField(header))
    }

    func testListFieldInnerListsBare() throws {
        let encoder = StructuredFieldEncoder()
        let header = [[1, 2, 3], [4, 5, 6]]
        XCTAssertEqual(Array("(1 2 3), (4 5 6)".utf8), try encoder.encodeListField(header))
    }

    func testListFieldInnerListsParameters() throws {
        struct Integers: Equatable, Encodable {
            var items: [Int]
            var parameters: [String: String]
        }

        let encoder = StructuredFieldEncoder()
        let header = [Integers(items: [1, 2, 3], parameters: ["early": "yes"]),
                      Integers(items: [4, 5, 6], parameters: ["early": "no"])]
        XCTAssertEqual(Array("(1 2 3);early=yes, (4 5 6);early=no".utf8), try encoder.encodeListField(header))
    }

    func testListFieldInnerListElementsWithParameters() throws {
        struct Item: Equatable, Encodable {
            var item: Int
            var parameters: [String: Bool]
        }

        let encoder = StructuredFieldEncoder()
        let header = [
            [
                Item(item: 1, parameters: ["odd": true]),
                Item(item: 2, parameters: ["odd": false]),
            ],
            [
                Item(item: 3, parameters: ["odd": true]),
                Item(item: 4, parameters: ["odd": false])
            ],
        ]
        XCTAssertEqual(Array("(1;odd 2;odd=?0), (3;odd 4;odd=?0)".utf8),
                       try encoder.encodeListField(header))
    }

    func testListFieldExplicitInnerListsWithItemsWithParameters() throws {
        struct ItemParams: Equatable, Encodable {
            var q: Float
        }

        struct Item: Equatable, Encodable {
            var item: String
            var parameters: ItemParams
        }

        struct FieldParams: Equatable, Encodable {
            var sorted: Bool
        }

        struct Fields: Equatable, Encodable {
            var items: [Item]
            var parameters: FieldParams
        }

        let encoder = StructuredFieldEncoder()
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
        XCTAssertEqual(Array("(gzip;q=0.8 deflate;q=0.6);sorted, (zlib;q=0.4 br;q=1.0);sorted=?0".utf8),
                       try encoder.encodeListField(header))
    }

    func testDictionaryFieldWithSimpleInnerLists() throws {
        struct Field: Encodable, Equatable {
            var name: String
            var color: String?
            var intensity: [Float]
        }

        let encoder = StructuredFieldEncoder()
        XCTAssertEqual(Array("name=red, intensity=(1.0 0.0 0.0)".utf8),
                       try encoder.encodeDictionaryField(Field(name: "red", color: nil, intensity: [1.0, 0.0, 0.0])))
    }

    func testDictionaryFieldWithComplexInnerLists() throws {
        struct ColorParameters: Encodable, Equatable {
            var name: String?
        }

        struct Color: Encodable, Equatable {
            var items: [Float]
            var parameters: ColorParameters
        }

        let encoder = StructuredFieldEncoder()
        let field = [
            "green": Color(items: [0.0, 1.0, 0.0], parameters: ColorParameters(name: "green")),
        ]
        XCTAssertEqual(Array("green=(0.0 1.0 0.0);name=green".utf8),
                       try encoder.encodeDictionaryField(field))
    }

    func testEmptyListField() throws {
        let encoder = StructuredFieldEncoder()
        XCTAssertEqual([], try encoder.encodeListField([] as [Int]))
    }

    func testEmptyDictionaryField() throws {
        let encoder = StructuredFieldEncoder()
        XCTAssertEqual([], try encoder.encodeDictionaryField([:] as [String: Int]))
    }

    func testEmptyItemField() throws {
        struct Field: Encodable {
            var item: Int?
        }
        let encoder = StructuredFieldEncoder()
        XCTAssertEqual([], try encoder.encodeItemField(Field(item: nil)))
        XCTAssertThrowsError(try encoder.encodeListField([Field(item: nil)]))
        XCTAssertThrowsError(try encoder.encodeDictionaryField(["x": Field(item: nil)]))
    }

    func testForbidEmptyItemWithActualParameters() throws {
        struct Field: Encodable {
            var item: Int?
            var parameters: [String: Int]
        }

        let encoder = StructuredFieldEncoder()
        let badField = Field(item: nil, parameters: ["x": 0])
        XCTAssertThrowsError(try encoder.encodeItemField(badField))
        XCTAssertThrowsError(try encoder.encodeListField([badField]))
        XCTAssertThrowsError(try encoder.encodeDictionaryField(["x": badField]))
    }

    func testForbidItemWithExtraField() throws {
        struct Field: Encodable {
            var item: Int
            var parameters: [String: Int]
            var other: Bool
        }

        let encoder = StructuredFieldEncoder()
        let badField = Field(item: 1, parameters: ["x": 0], other: true)
        XCTAssertThrowsError(try encoder.encodeItemField(badField))
        XCTAssertThrowsError(try encoder.encodeListField([badField]))
        XCTAssertThrowsError(try encoder.encodeDictionaryField(["x": badField]))
    }

    func testForbidJustParameters() throws {
        struct Field: Encodable {
            var parameters: [String: Int]
        }

        let encoder = StructuredFieldEncoder()
        let badField = Field(parameters: ["x": 0])
        XCTAssertThrowsError(try encoder.encodeItemField(badField))
        XCTAssertThrowsError(try encoder.encodeListField([badField]))
        XCTAssertThrowsError(try encoder.encodeDictionaryField(["x": badField]))
    }

    func testForbidNullInnerList() throws {
        struct Field: Encodable {
            var items: Int?
        }
        let encoder = StructuredFieldEncoder()
        XCTAssertThrowsError(try encoder.encodeListField([Field(items: nil)]))
        XCTAssertThrowsError(try encoder.encodeDictionaryField(["x": Field(items: nil)]))
    }

    func testLowercaseKeysOnDictionaries() throws {
        struct DictionaryField: Encodable {
            var allowAll: Bool
        }

        let noStrategyEncoder = StructuredFieldEncoder()
        XCTAssertThrowsError(try noStrategyEncoder.encodeDictionaryField(DictionaryField(allowAll: false)))

        var lowercaseEncoder = noStrategyEncoder
        lowercaseEncoder.keyEncodingStrategy = .lowercase
        XCTAssertEqual(Array("allowall".utf8),
                       try lowercaseEncoder.encodeDictionaryField(DictionaryField(allowAll: true)))
    }

    func testLowercaseKeysOnParameters() throws {
        struct Parameters: Encodable {
            var allowAll: Bool
        }

        struct ItemField: Encodable {
            var item: Int
            var parameters: Parameters
        }

        struct ListField: Encodable {
            var items: [Int]
            var parameters: Parameters
        }

        let noStrategyEncoder = StructuredFieldEncoder()
        var lowercaseEncoder = noStrategyEncoder
        lowercaseEncoder.keyEncodingStrategy = .lowercase

        let item = ItemField(item: 1, parameters: Parameters(allowAll: true))
        let list = ListField(items: [1, 2], parameters: Parameters(allowAll: true))

        XCTAssertThrowsError(try noStrategyEncoder.encodeItemField(item))
        XCTAssertEqual(Array("1;allowall".utf8), try lowercaseEncoder.encodeItemField(item))

        XCTAssertThrowsError(try noStrategyEncoder.encodeListField([item, item]))
        XCTAssertEqual(Array("1;allowall, 1;allowall".utf8),
                       try lowercaseEncoder.encodeListField([item, item]))

        XCTAssertThrowsError(try noStrategyEncoder.encodeListField([list]))
        XCTAssertEqual(Array("(1 2);allowall".utf8),
                       try lowercaseEncoder.encodeListField([list]))

        XCTAssertThrowsError(try noStrategyEncoder.encodeDictionaryField(["item": item]))
        XCTAssertEqual(Array("item=1;allowall".utf8),
                       try lowercaseEncoder.encodeDictionaryField(["item": item]))

        XCTAssertThrowsError(try noStrategyEncoder.encodeDictionaryField(["list": list]))
        XCTAssertEqual(Array("list=(1 2);allowall".utf8),
                       try lowercaseEncoder.encodeDictionaryField(["list": list]))
    }
}
