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
import RawStructuredFieldValues

/// This object translates between the keys used by the encoder and the keys used by the encoding object.
///
/// All methods here call back to similar methods on the encoder.
struct StructuredFieldKeyedEncodingContainer<Key: CodingKey> {
    private var encoder: _StructuredFieldEncoder

    init(encoder: _StructuredFieldEncoder) {
        self.encoder = encoder
    }
}

extension StructuredFieldKeyedEncodingContainer: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey] {
        self.encoder.codingPath
    }

    mutating func encodeNil(forKey key: Key) throws {
        // Nil has no representation in structured headers
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: String, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: Double, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: Float, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: Int, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: Int8, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: Int16, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: Int32, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: Int64, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: UInt, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        try self.encoder.encode(value, forKey: key.stringValue)
    }

    mutating func nestedContainer<NestedKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        self.encoder.container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        self.encoder.unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder {
        self.encoder
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        self.encoder
    }
}
