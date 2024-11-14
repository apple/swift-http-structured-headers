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
import XCTest

enum FixtureTestError: Error {
    case base64DecodingFailed
}

final class StructuredFieldParserTests: XCTestCase {
    enum TestResult {
        case dictionary(OrderedMap<String, ItemOrInnerList>)
        case list([ItemOrInnerList])
        case item(Item)
    }

    private func _validateBareItem(_ bareItem: RFC9651BareItem, against schema: JSONSchema, fixtureName: String) throws
    {
        switch (bareItem, schema) {
        case (.integer(let baseInt), .integer(let jsonInt)):
            XCTAssertEqual(baseInt, jsonInt, "\(fixtureName): Got \(bareItem), expected \(schema)")
        case (.decimal(let baseDecimal), .double(let jsonDouble)):
            XCTAssertEqual(
                String(baseDecimal),
                String(jsonDouble),
                "\(fixtureName): Got \(bareItem), expected \(schema)"
            )
        case (.decimal(let baseDecimal), .integer(let jsonInteger)):
            // Due to limits of Foundation's JSONSerialization, we can get types that decode as integers but are actually decimals.
            // We just cannot tell the difference here, so we tolerate this flexibility.
            XCTAssertEqual(
                Double(baseDecimal),
                Double(jsonInteger),
                "\(fixtureName): Got \(bareItem), expected \(schema)"
            )
        case (.string(let baseString), .string(let jsonString)):
            XCTAssertEqual(baseString, jsonString, "\(fixtureName): Got \(bareItem), expected \(schema)")
        case (.token(let token), .dictionary(let typeDictionary)):
            guard typeDictionary.count == 2, case .string(let typeName) = typeDictionary["__type"],
                case .string(let typeValue) = typeDictionary["value"]
            else {
                XCTFail("\(fixtureName): Unexpected type dict \(typeDictionary)")
                return
            }

            XCTAssertEqual(typeName, "token", "\(fixtureName): Expected type token, got type \(typeName)")
            XCTAssertEqual(typeValue, token, "\(fixtureName): Got \(token), expected \(typeValue)")
        case (.undecodedByteSequence(let binary), .dictionary(let typeDictionary)):
            guard typeDictionary.count == 2, case .string(let typeName) = typeDictionary["__type"],
                case .string(let typeValue) = typeDictionary["value"]
            else {
                XCTFail("\(fixtureName): Unexpected type dict \(typeDictionary)")
                return
            }

            XCTAssertEqual(typeName, "binary", "\(fixtureName): Expected type binary, got type \(typeName)")
            guard let decodedValue = Data(base64Encoded: binary) else {
                throw FixtureTestError.base64DecodingFailed
            }
            let decodedExpected = Data(base32Encoded: Data(typeValue.utf8))
            XCTAssertEqual(
                decodedValue,
                decodedExpected,
                "\(fixtureName): Got \(Array(decodedValue)), expected \(Array(decodedExpected))"
            )
        case (.bool(let baseBool), .bool(let expectedBool)):
            XCTAssertEqual(baseBool, expectedBool, "\(fixtureName): Got \(baseBool), expected \(expectedBool)")
        case (.date(let baseDate), .dictionary(let typeDictionary)):
            guard typeDictionary.count == 2, case .string(let typeName) = typeDictionary["__type"],
                case .integer(let typeValue) = typeDictionary["value"]
            else {
                XCTFail("\(fixtureName): Unexpected type dict \(typeDictionary)")
                return
            }

            XCTAssertEqual(typeName, "date", "\(fixtureName): Expected type date, got type \(typeName)")
            XCTAssertEqual(typeValue, baseDate, "\(fixtureName): Got \(baseDate), expected \(typeValue)")
        case (.displayString(let baseDisplayString), .dictionary(let typeDictionary)):
            guard typeDictionary.count == 2, case .string(let typeName) = typeDictionary["__type"],
                case .string(let typeValue) = typeDictionary["value"]
            else {
                XCTFail("\(fixtureName): Unexpected type dict \(typeDictionary)")
                return
            }

            XCTAssertEqual(
                typeName,
                "displaystring",
                "\(fixtureName): Expected type displaystring, got type \(typeName)"
            )
            XCTAssertEqual(
                typeValue,
                baseDisplayString,
                "\(fixtureName): Got \(baseDisplayString), expected \(typeValue)"
            )
        default:
            XCTFail("\(fixtureName): Got \(bareItem), expected \(schema)")
        }
    }

    private func _validateParameters(
        _ parameters: OrderedMap<String, RFC9651BareItem>,
        against schema: JSONSchema,
        fixtureName: String
    ) throws {
        guard case .dictionary(let expectedParameters) = schema else {
            XCTFail("\(fixtureName): Expected parameters to be a JSON dictionary, but got \(schema)")
            return
        }
        XCTAssertEqual(
            expectedParameters.count,
            parameters.count,
            "\(fixtureName): Different numbers of parameters: expected \(expectedParameters), got \(parameters)"
        )
        for (name, value) in parameters {
            guard let expectedValue = expectedParameters[name] else {
                XCTFail("\(fixtureName): Did not contain parameter for \(name)")
                return
            }
            try self._validateBareItem(value, against: expectedValue, fixtureName: fixtureName)
        }
    }

    private func _validateItem(_ item: Item, against schema: JSONSchema, fixtureName: String) throws {
        // Item: JSON array with two elements, the Bare-Item and Parameters
        guard case .array(let arrayElements) = schema, arrayElements.count == 2 else {
            XCTFail("\(fixtureName): Unexpected item: got \(item), expected \(schema)")
            return
        }

        // First, match the item.
        try self._validateBareItem(item.rfc9651BareItem, against: arrayElements.first!, fixtureName: fixtureName)

        // Now the parameters.
        try self._validateParameters(item.rfc9651Parameters, against: arrayElements.last!, fixtureName: fixtureName)
    }

    private func _validateInnerList(_ innerList: InnerList, against schema: JSONSchema, fixtureName: String) throws {
        guard case .array(let arrayElements) = schema,
            arrayElements.count == 2,
            case .some(.array(let expectedItems)) = arrayElements.first,
            let expectedParameters = arrayElements.last
        else {
            XCTFail("\(fixtureName): Unexpected inner list: got \(innerList), expected \(schema)")
            return
        }

        XCTAssertEqual(
            expectedItems.count,
            innerList.bareInnerList.count,
            "\(fixtureName): Unexpected inner list items: expected \(expectedItems), got \(innerList.bareInnerList)"
        )
        for (actualItem, expectedItem) in zip(innerList.bareInnerList, expectedItems) {
            try self._validateItem(actualItem, against: expectedItem, fixtureName: fixtureName)
        }

        try self._validateParameters(innerList.rfc9651Parameters, against: expectedParameters, fixtureName: fixtureName)
    }

    private func _validateList(_ result: [ItemOrInnerList], against schema: JSONSchema, fixtureName: String) throws {
        guard case .array(let arrayElements) = schema else {
            XCTFail("\(fixtureName): Unexpected list: got \(result), expected \(schema)")
            return
        }

        XCTAssertEqual(
            arrayElements.count,
            result.count,
            "\(fixtureName): Different counts in list: got \(result), expected \(arrayElements)"
        )
        for (innerResult, expectedElement) in zip(result, arrayElements) {
            switch innerResult {
            case .innerList(let innerList):
                try self._validateInnerList(innerList, against: expectedElement, fixtureName: fixtureName)
            case .item(let item):
                try self._validateItem(item, against: expectedElement, fixtureName: fixtureName)
            }
        }
    }

    private func _validateDictionary(
        _ result: OrderedMap<String, ItemOrInnerList>,
        against schema: JSONSchema,
        fixtureName: String
    ) throws {
        guard case .dictionary(let expectedElements) = schema else {
            XCTFail("\(fixtureName): Unexpected dictionary: got \(result), expected \(schema)")
            return
        }

        XCTAssertEqual(
            expectedElements.count,
            result.count,
            "\(fixtureName): Different counts in dictionary: got \(result), expected \(expectedElements)"
        )
        for (key, value) in result {
            guard let expectedEntry = expectedElements[key] else {
                XCTFail("\(fixtureName): Could not find \(key) in \(expectedElements)")
                return
            }
            switch value {
            case .innerList(let innerList):
                try self._validateInnerList(innerList, against: expectedEntry, fixtureName: fixtureName)
            case .item(let item):
                try self._validateItem(item, against: expectedEntry, fixtureName: fixtureName)
            }
        }
    }

    private func _validateFixtureResult(_ result: TestResult, against schema: JSONSchema, fixtureName: String) throws {
        // We want to recursively validate the result here.
        switch result {
        case .list(let resultItems):
            try self._validateList(resultItems, against: schema, fixtureName: fixtureName)
        case .dictionary(let resultDictionary):
            try self._validateDictionary(resultDictionary, against: schema, fixtureName: fixtureName)
        case .item(let resultItem):
            // Items have a specific format, but we have a helper for it.
            try self._validateItem(resultItem, against: schema, fixtureName: fixtureName)
        }
    }

    private func _runTestOnFixture(_ fixture: StructuredHeaderTestFixture) {
        // Temporary join here for now, we may want to use a fancy collection at some point.
        guard let raw = fixture.raw else {
            // Serialization only test, skip.
            return
        }
        let joinedHeaders = Array(raw.joined(separator: ", ").utf8)

        do {
            var parser = StructuredFieldValueParser(joinedHeaders)

            let testResult: TestResult
            switch fixture.headerType {
            case "dictionary":
                testResult = try .dictionary(parser.parseDictionaryFieldValue())
            case "list":
                testResult = try .list(parser.parseListFieldValue())
            case "item":
                testResult = try .item(parser.parseItemFieldValue())
            default:
                XCTFail("\(fixture.name): Unexpected header type \(fixture.headerType)")
                return
            }

            // If we got here, but we were supposed to error, we should error.
            if fixture.mustFail == true {
                XCTFail("\(fixture.name): Fixture must fail, but parse succeeded")
                return
            }

            // We allow this function to throw. It may only throw in cases where the test is allowed to fail,
            // so we police it under the same rules. In this case, we do some extra policing to confirm we only
            // tolerate the appropriate kinds of errors.
            // This force-unwrap is safe, expected can only be nil if mustFail is true.
            do {
                try self._validateFixtureResult(testResult, against: fixture.expected!, fixtureName: fixture.name)
            } catch let error as FixtureTestError {
                throw error
            } catch {
                XCTFail("\(fixture.name): validator threw unexpected error \(error)")
            }
        } catch {
            // Throwing is fine if this test is allowed to or expected to fail. If it isn't, fail the test.
            guard fixture.mustFail == true || fixture.canFail == true else {
                XCTFail("\(fixture.name): Fixture threw unexpected error \(error)")
                return
            }
        }
    }

    func testCanPassAllFixtures() throws {
        // This is a bulk-test: we run across all the fixtures in the fixtures directory to confirm we can handle all of them.
        for fixture in FixturesLoader.parsingFixtures {
            self._runTestOnFixture(fixture)
        }
    }
}
