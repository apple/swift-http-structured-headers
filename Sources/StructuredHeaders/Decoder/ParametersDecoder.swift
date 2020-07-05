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

struct ParametersDecoder<Key: CodingKey, BaseData: RandomAccessCollection> where BaseData.Element == UInt8, BaseData.SubSequence: Hashable {
    private var parameters: OrderedMap<BaseData.SubSequence, BareItem<BaseData.SubSequence>>

    private var decoder: _StructuredFieldDecoder<BaseData>

    init(_ parameters: OrderedMap<BaseData.SubSequence, BareItem<BaseData.SubSequence>>, decoder: _StructuredFieldDecoder<BaseData>) {
        self.parameters = parameters
        self.decoder = decoder
    }
}

extension ParametersDecoder: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey] {
        return self.decoder.codingPath
    }

    var allKeys: [Key] {
        return self.parameters.compactMap { Key(stringValue: String(decoding: $0.0, as: UTF8.self)) }
    }

    func contains(_ key: Key) -> Bool {
        return self.parameters.contains(where: { $0.0.elementsEqual(key.stringValue.utf8) })
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        // We will decode nil if the key is not present.
        return !self.contains(key)
    }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable {
        try self.decoder.push(_StructuredHeaderCodingKey(key, keyDecodingStrategy: self.decoder.keyDecodingStrategy))
        defer {
            self.decoder.pop()
        }
        return try type.init(from: self.decoder)
    }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
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
        // Parameters never support inherited types.
        throw StructuredHeaderError.invalidTypeForItem
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        // Parameters never support inherited types.
        throw StructuredHeaderError.invalidTypeForItem
    }
}
