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

struct TopLevelListDecoder<BaseData: RandomAccessCollection> where BaseData.Element == UInt8 {
    private var list: [ItemOrInnerList]

    private var currentOffset: Int

    private var decoder: _StructuredFieldDecoder<BaseData>

    init(_ list: [ItemOrInnerList], decoder: _StructuredFieldDecoder<BaseData>) {
        self.list = list
        self.currentOffset = 0
        self.decoder = decoder
    }
}

extension TopLevelListDecoder: UnkeyedDecodingContainer {
    var codingPath: [CodingKey] {
        self.decoder.codingPath
    }

    var count: Int? {
        self.list.count
    }

    var isAtEnd: Bool {
        self.currentOffset == self.list.count
    }

    var currentIndex: Int {
        self.currentOffset
    }

    mutating func decodeNil() throws -> Bool {
        // We never decode nil.
        false
    }

    mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
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

    mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey>
    where NestedKey: CodingKey {
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
