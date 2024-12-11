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

private let keyedInnerListDecoderSupportedKeys = ["items", "parameters"]

/// Used when someone has requested a keyed decoder for a property of inner list type.
///
/// There are only two valid keys for this: "items" and "parameters".
struct KeyedInnerListDecoder<Key: CodingKey, BaseData: RandomAccessCollection> where BaseData.Element == UInt8 {
    private var innerList: InnerList

    private var decoder: _StructuredFieldDecoder<BaseData>

    init(_ innerList: InnerList, decoder: _StructuredFieldDecoder<BaseData>) {
        self.innerList = innerList
        self.decoder = decoder
    }
}

extension KeyedInnerListDecoder: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey] {
        self.decoder.codingPath
    }

    var allKeys: [Key] {
        keyedInnerListDecoderSupportedKeys.compactMap { Key(stringValue: $0) }
    }

    func contains(_ key: Key) -> Bool {
        keyedInnerListDecoderSupportedKeys.contains(key.stringValue)
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        // Keys are never nil for this type.
        false
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
        try self.decoder.push(_StructuredHeaderCodingKey(key, keyDecodingStrategy: self.decoder.keyDecodingStrategy))
        defer {
            self.decoder.pop()
        }

        switch type {
        case is Data.Type:
            let container = try self.decoder.singleValueContainer()
            return try container.decode(Data.self) as! T
        case is Decimal.Type:
            let container = try self.decoder.singleValueContainer()
            return try container.decode(Decimal.self) as! T
        case is Date.Type:
            let container = try self.decoder.singleValueContainer()
            return try container.decode(Date.self) as! T
        case is DisplayString.Type:
            let container = try self.decoder.singleValueContainer()
            return try container.decode(DisplayString.self) as! T
        default:
            return try type.init(from: self.decoder)
        }
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        try self.decoder.push(_StructuredHeaderCodingKey(key, keyDecodingStrategy: self.decoder.keyDecodingStrategy))
        defer {
            self.decoder.pop()
        }
        return try self.decoder.container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try self.decoder.push(_StructuredHeaderCodingKey(key, keyDecodingStrategy: self.decoder.keyDecodingStrategy))
        defer {
            self.decoder.pop()
        }
        return try self.decoder.unkeyedContainer()
    }

    func superDecoder() throws -> Decoder {
        // Items never support inherited types.
        throw StructuredHeaderError.invalidTypeForItem
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        // Items never support inherited types.
        throw StructuredHeaderError.invalidTypeForItem
    }
}
