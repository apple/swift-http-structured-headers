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

// This file contains common, currency, component types.
//
// These types are used by the parser, the serializer, and by users of the direct encoding/decoding APIs.
// They are not used by those using the Codable interface.

// MARK:- ItemOrInnerList
public enum ItemOrInnerList<BaseData: RandomAccessCollection> where BaseData.Element == UInt8, BaseData.SubSequence == BaseData, BaseData: Hashable {
    case item(Item<BaseData>)
    case innerList(InnerList<BaseData>)
}

extension ItemOrInnerList: Hashable { }

// MARK:- BareItem
public enum BareItem<BaseData: RandomAccessCollection> where BaseData.Element == UInt8, BaseData.SubSequence == BaseData, BaseData: Hashable {
    case bool(Bool)
    case integer(Int)
    case decimal(Float64)  // Not great, can we do better?
    case string(String)
    case undecodedByteSequence(BaseData)
    case token(BaseData)
}

extension BareItem: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension BareItem: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

extension BareItem: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Float64) {
        self = .decimal(value)
    }
}

extension BareItem: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
}

extension BareItem: Hashable { }

// MARK:- Item
public struct Item<BaseData: RandomAccessCollection> where BaseData.Element == UInt8, BaseData.SubSequence == BaseData, BaseData: Hashable {
    public var bareItem: BareItem<BaseData>
    public var parameters: OrderedMap<BaseData, BareItem<BaseData>>
}

extension Item: Hashable { }

// MARK:- BareInnerList
public struct BareInnerList<BaseData: RandomAccessCollection>: Hashable where BaseData.Element == UInt8, BaseData.SubSequence == BaseData, BaseData: Hashable {
    private var items: [Item<BaseData>]

    public init() {
        self.items = []
    }

    public mutating func append(_ item: Item<BaseData>) {
        self.items.append(item)
    }
}

extension BareInnerList: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Item<BaseData>...) {
        self.items = elements
    }
}

// TODO: RangeReplaceableCollection I guess
extension BareInnerList: RandomAccessCollection, MutableCollection {
    public struct Index {
        fileprivate var baseIndex: Array<Item<BaseData>>.Index

        init(_ baseIndex: Array<Item<BaseData>>.Index) {
            self.baseIndex = baseIndex
        }
    }

    public var count: Int {
        return self.items.count
    }

    public var startIndex: Index {
        return Index(self.items.startIndex)
    }

    public var endIndex: Index {
        return Index(self.items.endIndex)
    }

    public func index(after i: Index) -> Index {
        return Index(self.items.index(after: i.baseIndex))
    }

    public func index(before i: Index) -> Index {
        return Index(self.items.index(before: i.baseIndex))
    }

    public func index(_ i: Index, offsetBy offset: Int) -> Index {
        return Index(self.items.index(i.baseIndex, offsetBy: offset))
    }

    public subscript(index: Index) -> Item<BaseData> {
        get {
            return self.items[index.baseIndex]
        }
        set {
            self.items[index.baseIndex] = newValue
        }
    }
}

extension BareInnerList.Index: Hashable { }

extension BareInnerList.Index: Comparable {
    public static func <(lhs: Self, rhs: Self) -> Bool {
        return lhs.baseIndex < rhs.baseIndex
    }
}

// MARK:- InnerList
public struct InnerList<BaseData: RandomAccessCollection>: Hashable where BaseData.Element == UInt8, BaseData.SubSequence == BaseData, BaseData: Hashable {
    public var bareInnerList: BareInnerList<BaseData>
    public var parameters: OrderedMap<BaseData, BareItem<BaseData>>
}
