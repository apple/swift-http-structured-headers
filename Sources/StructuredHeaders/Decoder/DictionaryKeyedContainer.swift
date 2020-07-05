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

struct DictionaryKeyedContainer<Key: CodingKey, BaseData: RandomAccessCollection> where BaseData.Element == UInt8, BaseData.SubSequence: Hashable {
    private var dictionary: OrderedMap<BaseData.SubSequence, ItemOrInnerList<BaseData.SubSequence>>

    private var decoder: _StructuredFieldDecoder<BaseData>

    init(_ dictionary: OrderedMap<BaseData.SubSequence, ItemOrInnerList<BaseData.SubSequence>>, decoder: _StructuredFieldDecoder<BaseData>) {
        self.dictionary = dictionary
        self.decoder = decoder
    }
}

extension DictionaryKeyedContainer: KeyedDecodingContainerProtocol {
    var codingPath: [CodingKey] {
        return self.decoder.codingPath
    }

    var allKeys: [Key] {
        return self.dictionary.compactMap { Key(stringValue: String(decoding: $0.0, as: UTF8.self)) }
    }

    func contains(_ key: Key) -> Bool {
        return self.dictionary.contains(where: { $0.0.elementsEqual(key.stringValue.utf8) })
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
        // Dictionary headers never support inherited types.
        throw StructuredHeaderError.invalidTypeForItem
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        // Dictionary headers never support inherited types.
        throw StructuredHeaderError.invalidTypeForItem
    }
}
