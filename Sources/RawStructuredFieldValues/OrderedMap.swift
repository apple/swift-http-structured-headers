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

/// `OrderedMap` is a data type that has associative-array properties, but that
/// maintains insertion order.
///
/// Our initial implementation takes advantage of the fact that the vast majority of
/// maps in structured headers are small (fewer than 20 elements), and so the
/// distinction between hashing and linear search is not really a concern. However, for
/// future implementation flexibility, we continue to require that keys be hashable.
///
/// Note that this preserves _original_ insertion order: if you overwrite a key's value, the
/// key does not move to "last". This is a specific requirement for Structured Headers and may
/// harm the generality of this implementation.
public struct OrderedMap<Key, Value> where Key: Hashable {
    private var backing: [Entry]

    public init() {
        self.backing = []
    }

    /// Look up the value for a given key.
    ///
    /// Warning! Unlike a regular dictionary, we do not promise this will be O(1)!
    public subscript(key: Key) -> Value? {
        get {
            self.backing.first(where: { $0.key == key }).map { $0.value }
        }
        set {
            if let existing = self.backing.firstIndex(where: { $0.key == key }) {
                if let newValue = newValue {
                    self.backing[existing] = Entry(key: key, value: newValue)
                } else {
                    self.backing.remove(at: existing)
                }
            } else if let newValue = newValue {
                self.backing.append(Entry(key: key, value: newValue))
            }
        }
    }

    func mapValues<NewValue>(_ body: (Value) throws -> NewValue) rethrows -> OrderedMap<Key, NewValue> {
        var returnValue = OrderedMap<Key, NewValue>()
        returnValue.backing = try self.backing.map { try .init(key: $0.key, value: body($0.value)) }
        return returnValue
    }
}

// MARK: - Helper struct for storing elements

extension OrderedMap {
    // This struct takes some explaining.
    //
    // We don't want to maintain too much code here. In particular, we'd like to have straightforward equatable and hashable
    // implementations. However, tuples aren't equatable or hashable. So we need to actually store something that is: a nominal
    // type. That's this!
    //
    // This existence of this struct is a pure implementation detail and not exposed to the user of the type.
    fileprivate struct Entry {
        var key: Key
        var value: Value
    }
}

extension OrderedMap: Sendable where Key: Sendable, Value: Sendable {}

extension OrderedMap.Entry: Sendable where Key: Sendable, Value: Sendable {}

// MARK: - Collection conformances

extension OrderedMap: RandomAccessCollection, MutableCollection {
    public struct Index: Sendable {
        fileprivate var baseIndex: Array<(Key, Value)>.Index

        fileprivate init(_ baseIndex: Array<(Key, Value)>.Index) {
            self.baseIndex = baseIndex
        }
    }

    public var startIndex: Index {
        Index(self.backing.startIndex)
    }

    public var endIndex: Index {
        Index(self.backing.endIndex)
    }

    public var count: Int {
        self.backing.count
    }

    public subscript(position: Index) -> (Key, Value) {
        get {
            let element = self.backing[position.baseIndex]
            return (element.key, element.value)
        }
        set {
            self.backing[position.baseIndex] = Entry(key: newValue.0, value: newValue.1)
        }
    }

    public func index(_ i: Index, offsetBy distance: Int) -> Index {
        Index(self.backing.index(i.baseIndex, offsetBy: distance))
    }

    public func index(after i: Index) -> Index {
        self.index(i, offsetBy: 1)
    }

    public func index(before i: Index) -> Index {
        self.index(i, offsetBy: -1)
    }
}

extension OrderedMap.Index: Hashable {}

extension OrderedMap.Index: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.baseIndex < rhs.baseIndex
    }
}

extension OrderedMap.Index: Strideable {
    public func advanced(by n: Int) -> Self {
        Self(self.baseIndex.advanced(by: n))
    }

    public func distance(to other: Self) -> Int {
        self.baseIndex.distance(to: other.baseIndex)
    }
}

// MARK: - Helper conformances

extension OrderedMap: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.backing = elements.map { Entry(key: $0.0, value: $0.1) }
    }
}

extension OrderedMap: CustomDebugStringConvertible {
    public var debugDescription: String {
        let backingRepresentation = self.backing.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        return "[\(backingRepresentation)]"
    }
}

// MARK: - Conditional conformances

extension OrderedMap.Entry: Equatable where Value: Equatable {}
extension OrderedMap: Equatable where Value: Equatable {}
extension OrderedMap.Entry: Hashable where Value: Hashable {}
extension OrderedMap: Hashable where Value: Hashable {}
