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
import StructuredHeaders

struct BareInnerListDecoder<BaseData: RandomAccessCollection> where BaseData.Element == UInt8, BaseData.SubSequence: Hashable {
    private var list: BareInnerList<BaseData.SubSequence>

    private var currentOffset: Int

    private var decoder: _StructuredFieldDecoder<BaseData>

    init(_ list: BareInnerList<BaseData.SubSequence>, decoder: _StructuredFieldDecoder<BaseData>) {
        self.list = list
        self.currentOffset = 0
        self.decoder = decoder
    }
}

extension BareInnerListDecoder: UnkeyedDecodingContainer {
    var codingPath: [CodingKey] {
        return self.decoder.codingPath
    }

    var count: Int? {
        return self.list.count
    }

    var isAtEnd: Bool {
        return self.currentOffset == self.list.count
    }

    var currentIndex: Int {
        return self.currentOffset
    }

    mutating func decodeNil() throws -> Bool {
        // We never decode nil.
        return false
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        // This is a request to decode a scalar. We decode the next entry and increment the index.
        guard !self.isAtEnd else {
            throw StructuredHeaderError.indexOutOfRange
        }

        let codingKey = _StructuredHeaderCodingKey(intValue: self.currentOffset)
        defer {
            self.currentOffset += 1
        }

        try self.decoder.push(codingKey)
        defer {
            self.decoder.pop()
        }

        if type is Data.Type {
            let container = try self.decoder.singleValueContainer()
            return try container.decode(Data.self) as! T
        } else {
            return try type.init(from: self.decoder)
        }
    }

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
        // This is a request to decode a full item. We decode the next entry and increment the index.
        guard !self.isAtEnd else {
            throw StructuredHeaderError.indexOutOfRange
        }

        let codingKey = _StructuredHeaderCodingKey(intValue: self.currentOffset)
        defer {
            self.currentOffset += 1
        }

        try self.decoder.push(codingKey)
        defer {
            self.decoder.pop()
        }
        return try self.decoder.container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard !self.isAtEnd else {
            throw StructuredHeaderError.indexOutOfRange
        }

        let codingKey = _StructuredHeaderCodingKey(intValue: self.currentOffset)
        defer {
            self.currentOffset += 1
        }

        try self.decoder.push(codingKey)
        defer {
            self.decoder.pop()
        }
        return try self.decoder.unkeyedContainer()
    }

    mutating func superDecoder() throws -> Decoder {
        // No inheritance here folks
        throw StructuredHeaderError.invalidTypeForItem
    }

}
