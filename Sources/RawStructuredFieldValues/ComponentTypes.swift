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

// MARK: - ItemOrInnerList

/// `ItemOrInnerList` represents the values in a structured header dictionary, or the
/// entries in a structured header list.
public enum ItemOrInnerList: SHSendable {
    case item(Item)
    case innerList(InnerList)
}

extension ItemOrInnerList: Hashable {}

// MARK: - BareItem

/// `BareItem` is a representation of the base data types at the bottom of a structured
/// header field. These types are not parameterised: they are raw data.
public enum BareItem: SHSendable {
    /// A boolean item.
    case bool(Bool)

    /// An integer item.
    case integer(Int)

    /// A decimal item.
    case decimal(PseudoDecimal)

    /// A string item.
    case string(String)

    /// A byte sequence. This case must contain base64-encoded data, as
    /// `StructuredHeaders` does not do base64 encoding or decoding.
    case undecodedByteSequence(String)

    /// A token item.
    case token(String)
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
        self = .decimal(.init(floatLiteral: value))
    }
}

extension BareItem: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        if value.structuredHeadersIsValidToken {
            self = .token(value)
        } else {
            self = .string(value)
        }
    }
}

extension BareItem: Hashable {}

// MARK: - Item

/// `Item` represents a structured header field item: a combination of a `bareItem`
/// and some parameters.
public struct Item: SHSendable {
    /// The `BareItem` that this `Item` contains.
    public var bareItem: BareItem

    /// The parameters associated with `bareItem`
    public var parameters: OrderedMap<String, BareItem>

    public init(bareItem: BareItem, parameters: OrderedMap<String, BareItem>) {
        self.bareItem = bareItem
        self.parameters = parameters
    }
}

extension Item: Hashable {}

// MARK: - BareInnerList

/// A `BareInnerList` represents the items contained within an ``InnerList``, without
/// the associated parameters.
public struct BareInnerList: Hashable, SHSendable {
    private var items: [Item]

    public init() {
        self.items = []
    }

    public mutating func append(_ item: Item) {
        self.items.append(item)
    }
}

extension BareInnerList: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Item...) {
        self.items = elements
    }
}

// TODO: RangeReplaceableCollection I guess
extension BareInnerList: RandomAccessCollection, MutableCollection {
    public struct Index {
        fileprivate var baseIndex: Array<Item>.Index

        init(_ baseIndex: Array<Item>.Index) {
            self.baseIndex = baseIndex
        }
    }

    public var count: Int {
        self.items.count
    }

    public var startIndex: Index {
        Index(self.items.startIndex)
    }

    public var endIndex: Index {
        Index(self.items.endIndex)
    }

    public func index(after i: Index) -> Index {
        Index(self.items.index(after: i.baseIndex))
    }

    public func index(before i: Index) -> Index {
        Index(self.items.index(before: i.baseIndex))
    }

    public func index(_ i: Index, offsetBy offset: Int) -> Index {
        Index(self.items.index(i.baseIndex, offsetBy: offset))
    }

    public subscript(index: Index) -> Item {
        get {
            self.items[index.baseIndex]
        }
        set {
            self.items[index.baseIndex] = newValue
        }
    }
}

extension BareInnerList.Index: Hashable {}

extension BareInnerList.Index: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.baseIndex < rhs.baseIndex
    }
}

// MARK: - InnerList

/// An `InnerList` is a list of items, with some associated parameters.
public struct InnerList: Hashable, SHSendable {
    /// The items contained within this inner list.
    public var bareInnerList: BareInnerList

    /// The parameters associated with the `bareInnerList`.
    public var parameters: OrderedMap<String, BareItem>

    public init(bareInnerList: BareInnerList, parameters: OrderedMap<String, BareItem>) {
        self.bareInnerList = bareInnerList
        self.parameters = parameters
    }
}

extension String {
    /// Whether this string is a valid structured headers token, or whether it would
    /// need to be stored in a structured headers string.
    public var structuredHeadersIsValidToken: Bool {
        let view = self.utf8

        switch view.first {
        case .some(asciiCapitals), .some(asciiLowercases), .some(asciiAsterisk):
            // Good
            ()
        default:
            return false
        }

        for byte in view {
            switch byte {
            // Valid token characters are RFC 7230 tchar, colon, and slash.
            // tchar is:
            //
            // tchar          = "!" / "#" / "$" / "%" / "&" / "'" / "*"
            //                / "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
            //                / DIGIT / ALPHA
            //
            // The following insane case statement covers this. Tokens suck.
            case asciiExclamationMark, asciiOctothorpe, asciiDollar, asciiPercent,
                 asciiAmpersand, asciiSquote, asciiAsterisk, asciiPlus, asciiDash,
                 asciiPeriod, asciiCaret, asciiUnderscore, asciiBacktick, asciiPipe,
                 asciiTilde, asciiDigits, asciiCapitals, asciiLowercases,
                 asciiColon, asciiSlash:
                // Good
                ()
            default:
                // Bad token
                return false
            }
        }

        return true
    }
}
