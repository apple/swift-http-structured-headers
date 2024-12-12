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

enum FixturesLoader {
    private static var fixturesDirectory: URL {
        let myURL = URL(fileURLWithPath: #filePath, isDirectory: false)
        return URL(string: "../TestFixtures/", relativeTo: myURL)!.absoluteURL
    }

    private static var serializationFixturesDirectory: URL {
        fixturesDirectory.appendingPathComponent("serialisation-tests").absoluteURL
    }

    static var parsingFixtures: [StructuredHeaderTestFixture] {
        // ContentsOfDirectory can throw if it hits EINTR, just spin
        var files: [URL]?
        for _ in 0..<1000 {
            do {
                files = try FileManager.default.contentsOfDirectory(
                    at: fixturesDirectory,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                break
            } catch let error as NSError {
                guard let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError,
                    underlyingError.domain == NSPOSIXErrorDomain, underlyingError.code == EINTR
                else {
                    fatalError("\(error)")
                }
                // Ok, we'll continue
            }
        }
        guard let realFiles = files else {
            fatalError("Hit EINTR 1000 times!")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return realFiles.filter { $0.pathExtension == "json" }.flatMap { file -> [StructuredHeaderTestFixture] in
            let content = try! Data(contentsOf: file, options: [.uncached, .mappedIfSafe])
            return try! decoder.decode([StructuredHeaderTestFixture].self, from: content)
        }
    }

    static var serializingFixtures: [StructuredHeaderTestFixture] {
        // ContentsOfDirectory can throw if it hits EINTR, just spin
        var files: [URL]?
        for _ in 0..<1000 {
            do {
                files = try FileManager.default.contentsOfDirectory(
                    at: serializationFixturesDirectory,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                break
            } catch let error as NSError {
                guard let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError,
                    underlyingError.domain == NSPOSIXErrorDomain, underlyingError.code == EINTR
                else {
                    fatalError("\(error)")
                }
                // Ok, we'll continue
            }
        }
        guard let realFiles = files else {
            fatalError("Hit EINTR 1000 times!")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return realFiles.filter { $0.pathExtension == "json" }.flatMap { file -> [StructuredHeaderTestFixture] in
            let content = try! Data(contentsOf: file, options: [.uncached, .mappedIfSafe])
            return try! decoder.decode([StructuredHeaderTestFixture].self, from: content)
        }
    }
}

struct StructuredHeaderTestFixture: Decodable {
    /// The name of this test.
    var name: String

    /// The list of header fields that should be parsed. Not present if this is a serialization test.
    var raw: [String]?

    /// The type to use to parse the fields
    var headerType: String

    /// The expected data structure to be produced. Note that this is stored as a serialized JSON object:
    /// this is because the shape of this data structure varies from test-case to test-case, so we can't
    /// incorporate it into the type system. This type is also preventing us from using Codable here: we just
    /// don't know what the heck we're expecting to see.
    var expected: JSONSchema?

    /// Whether this test is required to fail.
    var mustFail: Bool?

    /// Whether this test is allowed to fail.
    var canFail: Bool?

    /// The canonical form if the field value, if different from raw. Not applicable if `mustFail` is `true`.
    var canonical: [String]?
}

/// This defines the JSON types that can be used to encode structured headers. It allows us to express the expected outcome of
/// a parse in a type-safe way.
enum JSONSchema: Decodable {
    case dictionary([String: JSONSchema])
    case array([JSONSchema])
    case integer(Int64)
    case double(Double)
    case string(String)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode([String: JSONSchema].self) {
            self = .dictionary(value)
        } else if let value = try? container.decode([JSONSchema].self) {
            self = .array(value)
        } else {
            preconditionFailure("Failed to decode at \(container.codingPath)")
        }
    }

    var isArray: Bool {
        switch self {
        case .array:
            return true
        case .dictionary, .integer, .double, .string, .bool:
            return false
        }
    }
}
