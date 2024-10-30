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

/// This object translates between the unkeyed coding API and methods on the encoder.
///
/// All methods here call back to similar methods on the encoder.
struct StructuredFieldUnkeyedEncodingContainer {
    private var encoder: _StructuredFieldEncoder

    init(encoder: _StructuredFieldEncoder) {
        self.encoder = encoder
    }
}

extension StructuredFieldUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    var codingPath: [CodingKey] {
        self.encoder.codingPath
    }

    var count: Int {
        self.encoder.count
    }

    func encodeNil() throws {
        try self.encoder.appendNil()
    }

    func encode(_ value: Bool) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: String) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: Double) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: Float) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: Int) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: Int8) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: Int16) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: Int32) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: Int64) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: UInt) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: UInt8) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: UInt16) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: UInt32) throws {
        try self.encoder.append(value)
    }

    func encode(_ value: UInt64) throws {
        try self.encoder.append(value)
    }

    func encode<T>(_ value: T) throws where T: Encodable {
        try self.encoder.append(value)
    }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey>
    where NestedKey: CodingKey {
        self.encoder.container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        self.encoder.unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder {
        self.encoder
    }
}
