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

/// A `StructuredFieldValueEncoder` allows encoding `Encodable` objects to the format of a HTTP
/// structured header field.
public struct StructuredFieldValueEncoder: Sendable {
    public var keyEncodingStrategy: KeyEncodingStrategy?

    public init() {}
}

extension StructuredFieldValueEncoder {
    /// A strategy that should be used to map coding keys to wire format keys.
    public struct KeyEncodingStrategy: Hashable, Sendable {
        fileprivate enum Base: Hashable {
            case lowercase
        }

        fileprivate var base: Base

        /// Lowercase all coding keys before encoding them in keyed containers such as
        /// dictionaries or parameters.
        public static let lowercase = KeyEncodingStrategy(base: .lowercase)
    }
}

extension StructuredFieldValueEncoder {
    /// Attempt to encode an object into a structured header field.
    ///
    /// - parameters:
    ///     - data: The object to encode.
    /// - throws: If the header field could not be encoded, or could not be serialized.
    /// - returns: The bytes representing the HTTP structured header field.
    public func encode<StructuredField: StructuredFieldValue>(_ data: StructuredField) throws -> [UInt8] {
        switch StructuredField.structuredFieldType {
        case .item:
            return try self.encodeItemField(data)
        case .list:
            return try self.encodeListField(data)
        case .dictionary:
            return try self.encodeDictionaryField(data)
        }
    }

    /// Attempt to encode an object into a structured header dictionary field.
    ///
    /// - parameters:
    ///     - data: The object to encode.
    /// - throws: If the header field could not be encoded, or could not be serialized.
    /// - returns: The bytes representing the HTTP structured header field.
    private func encodeDictionaryField<StructuredField: Encodable>(_ data: StructuredField) throws -> [UInt8] {
        let serializer = StructuredFieldValueSerializer()
        let encoder = _StructuredFieldEncoder(serializer, keyEncodingStrategy: self.keyEncodingStrategy)
        return try encoder.encodeDictionaryField(data)
    }

    /// Attempt to encode an object into a structured header list field.
    ///
    /// - parameters:
    ///     - data: The object to encode.
    /// - throws: If the header field could not be encoded, or could not be serialized.
    /// - returns: The bytes representing the HTTP structured header field.
    private func encodeListField<StructuredField: Encodable>(_ data: StructuredField) throws -> [UInt8] {
        let serializer = StructuredFieldValueSerializer()
        let encoder = _StructuredFieldEncoder(serializer, keyEncodingStrategy: self.keyEncodingStrategy)
        return try encoder.encodeListField(data)
    }

    /// Attempt to encode an object into a structured header item field.
    ///
    /// - parameters:
    ///     - data: The object to encode.
    /// - throws: If the header field could not be encoded, or could not be serialized.
    /// - returns: The bytes representing the HTTP structured header field.
    private func encodeItemField<StructuredField: Encodable>(_ data: StructuredField) throws -> [UInt8] {
        let serializer = StructuredFieldValueSerializer()
        let encoder = _StructuredFieldEncoder(serializer, keyEncodingStrategy: self.keyEncodingStrategy)
        return try encoder.encodeItemField(data)
    }
}

class _StructuredFieldEncoder {
    private var serializer: StructuredFieldValueSerializer

    // For now we use a stack here because the CoW operations on Array would stuck. Ideally I'd just have us decode
    // our way down with values, but doing that is a CoWy nightmare from which we cannot escape.
    private var _codingPath: [CodingStackEntry]

    private var currentStackEntry: CodingStackEntry

    internal var keyEncodingStrategy: StructuredFieldValueEncoder.KeyEncodingStrategy?

    init(
        _ serializer: StructuredFieldValueSerializer,
        keyEncodingStrategy: StructuredFieldValueEncoder.KeyEncodingStrategy?
    ) {
        self.serializer = serializer
        self._codingPath = []
        self.keyEncodingStrategy = keyEncodingStrategy

        // This default doesn't matter right now.
        self.currentStackEntry = CodingStackEntry(key: .init(stringValue: ""), storage: .itemHeader)
    }

    fileprivate func encodeDictionaryField<StructuredField: Encodable>(_ data: StructuredField) throws -> [UInt8] {
        self.push(key: .init(stringValue: ""), newStorage: .dictionaryHeader)
        try data.encode(to: self)

        switch self.currentStackEntry.storage {
        case .dictionary(let map):
            return try self.serializer.writeDictionaryFieldValue(map)
        case .dictionaryHeader:
            // No encoding happened.
            return []
        case .listHeader, .list, .itemHeader, .item, .bareInnerList, .innerList,
            .parameters, .itemOrInnerList:
            throw StructuredHeaderError.invalidTypeForItem
        }
    }

    fileprivate func encodeListField<StructuredField: Encodable>(_ data: StructuredField) throws -> [UInt8] {
        self.push(key: .init(stringValue: ""), newStorage: .listHeader)
        try data.encode(to: self)

        switch self.currentStackEntry.storage {
        case .list(let list):
            return try self.serializer.writeListFieldValue(list)
        case .listHeader:
            // No encoding happened
            return []
        case .dictionaryHeader, .dictionary, .itemHeader, .item, .bareInnerList, .innerList,
            .parameters, .itemOrInnerList:
            throw StructuredHeaderError.invalidTypeForItem
        }
    }

    fileprivate func encodeItemField<StructuredField: Encodable>(_ data: StructuredField) throws -> [UInt8] {
        self.push(key: .init(stringValue: ""), newStorage: .itemHeader)

        // There's an awkward special hook here: if the outer type is `Data`, `Decimal`, `Date` or
        // `DisplayString`, we skip the regular encoding path.
        //
        // Everything else goes through the normal flow.
        switch data {
        case is Data:
            try self.encode(data)
        case is Decimal:
            try self.encode(data)
        case is Date:
            try self.encode(data)
        case is DisplayString:
            try self.encode(data)
        default:
            try data.encode(to: self)
        }

        switch self.currentStackEntry.storage {
        case .item(let item):
            return try self.serializer.writeItemFieldValue(Item(item))
        case .itemHeader:
            // No encoding happened
            return []
        case .dictionaryHeader, .dictionary, .listHeader, .list, .bareInnerList, .innerList,
            .parameters, .itemOrInnerList:
            throw StructuredHeaderError.invalidTypeForItem
        }
    }
}

extension _StructuredFieldEncoder: Encoder {
    var codingPath: [CodingKey] {
        self._codingPath.map { $0.key as CodingKey }
    }

    var userInfo: [CodingUserInfoKey: Any] {
        [:]
    }

    func push(key: _StructuredHeaderCodingKey, newStorage: NodeType) {
        self._codingPath.append(self.currentStackEntry)
        self.currentStackEntry = .init(key: key, storage: newStorage)
    }

    func pop() throws {
        // This is called when we've completed the storage in the current container.
        // We can pop the value at the base of the stack, then "insert" the current one
        // into it, and save the new value as the new current.
        let current = self.currentStackEntry
        var newCurrent = self._codingPath.removeLast()
        try newCurrent.storage.insert(current.storage, atKey: current.key)
        self.currentStackEntry = newCurrent
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        KeyedEncodingContainer(StructuredFieldKeyedEncodingContainer(encoder: self))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        StructuredFieldUnkeyedEncodingContainer(encoder: self)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        self
    }
}

extension _StructuredFieldEncoder: SingleValueEncodingContainer {
    func encodeNil() throws {
        // bare items are never nil.
        throw StructuredHeaderError.invalidTypeForItem
    }

    func encode(_ value: Bool) throws {
        try self.currentStackEntry.storage.insertBareItem(.bool(value))
    }

    func encode(_ value: String) throws {
        if value.structuredHeadersIsValidToken {
            try self.currentStackEntry.storage.insertBareItem(.token(value))
        } else {
            try self.currentStackEntry.storage.insertBareItem(.string(value))
        }
    }

    func encode(_ value: Double) throws {
        try self._encodeBinaryFloatingPoint(value)
    }

    func encode(_ value: Float) throws {
        try self._encodeBinaryFloatingPoint(value)
    }

    func encode(_ value: Int) throws {
        try self._encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int8) throws {
        try self._encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int16) throws {
        try self._encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int32) throws {
        try self._encodeFixedWidthInteger(value)
    }

    func encode(_ value: Int64) throws {
        try self._encodeFixedWidthInteger(value)
    }

    #if compiler(>=6.0)
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func encode(_ value: Int128) throws {
        try self._encodeFixedWidthInteger(value)
    }
    #endif

    func encode(_ value: UInt) throws {
        try self._encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt8) throws {
        try self._encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt16) throws {
        try self._encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt32) throws {
        try self._encodeFixedWidthInteger(value)
    }

    func encode(_ value: UInt64) throws {
        try self._encodeFixedWidthInteger(value)
    }

    #if compiler(>=6.0)
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func encode(_ value: UInt128) throws {
        try self._encodeFixedWidthInteger(value)
    }
    #endif

    func encode(_ data: Data) throws {
        let encoded = data.base64EncodedString()
        try self.currentStackEntry.storage.insertBareItem(.undecodedByteSequence(encoded))
    }

    func encode(_ data: Decimal) throws {
        let significand = (data.significand.magnitude as NSNumber).intValue  // Yes, really.
        guard let exponent = Int8(exactly: data.exponent) else {
            throw StructuredHeaderError.invalidIntegerOrDecimal
        }

        let pd = PseudoDecimal(mantissa: significand * (data.isSignMinus ? -1 : 1), exponent: Int(exponent))
        try self.currentStackEntry.storage.insertBareItem(.decimal(pd))
    }

    func encode(_ data: Date) throws {
        let date = Int64(data.timeIntervalSince1970)
        try self.currentStackEntry.storage.insertBareItem(.date(date))
    }

    func encode(_ data: DisplayString) throws {
        try self.currentStackEntry.storage.insertBareItem(.displayString(data.rawValue))
    }

    func encode<T>(_ value: T) throws where T: Encodable {
        switch value {
        case let value as UInt8:
            try self.encode(value)
        case let value as Int8:
            try self.encode(value)
        case let value as UInt16:
            try self.encode(value)
        case let value as Int16:
            try self.encode(value)
        case let value as UInt32:
            try self.encode(value)
        case let value as Int32:
            try self.encode(value)
        case let value as UInt64:
            try self.encode(value)
        case let value as Int64:
            try self.encode(value)
        case let value as Int:
            try self.encode(value)
        case let value as UInt:
            try self.encode(value)
        case let value as Float:
            try self.encode(value)
        case let value as Double:
            try self.encode(value)
        case let value as String:
            try self.encode(value)
        case let value as Bool:
            try self.encode(value)
        case let value as Data:
            try self.encode(value)
        case let value as Decimal:
            try self.encode(value)
        case let value as Date:
            try self.encode(value)
        case let value as DisplayString:
            try self.encode(value)
        default:
            throw StructuredHeaderError.invalidTypeForItem
        }
    }

    private func _encodeBinaryFloatingPoint<T: BinaryFloatingPoint>(_ value: T) throws {
        // We go via double and encode it as a decimal.
        let pseudoDecimal = try PseudoDecimal(Double(value))
        try self.currentStackEntry.storage.insertBareItem(.decimal(pseudoDecimal))
    }

    private func _encodeFixedWidthInteger<T: FixedWidthInteger>(_ value: T) throws {
        guard let base = Int64(exactly: value) else {
            throw StructuredHeaderError.integerOutOfRange
        }
        try self.currentStackEntry.storage.insertBareItem(.integer(base))
    }
}

extension _StructuredFieldEncoder {
    // This extension sort-of corresponds to the unkeyed encoding container: all of
    // these methods are called from there.
    var count: Int {
        switch self.currentStackEntry.storage {
        case .bareInnerList(let list):
            return list.count

        case .innerList(let list):
            return list.bareInnerList.count

        case .itemOrInnerList:
            return 0

        case .list(let list):
            return list.count

        case .listHeader:
            return 0

        case .dictionaryHeader, .dictionary, .itemHeader, .item, .parameters:
            fatalError("Cannot have unkeyed container at \(self.currentStackEntry)")
        }
    }

    func appendNil() throws {
        // list entries are never nil.
        throw StructuredHeaderError.invalidTypeForItem
    }

    func append(_ value: Bool) throws {
        try self.currentStackEntry.storage.appendBareItem(.bool(value))
    }

    func append(_ value: String) throws {
        if value.structuredHeadersIsValidToken {
            try self.currentStackEntry.storage.appendBareItem(.token(value))
        } else {
            try self.currentStackEntry.storage.appendBareItem(.string(value))
        }
    }

    func append(_ value: Double) throws {
        try self._appendBinaryFloatingPoint(value)
    }

    func append(_ value: Float) throws {
        try self._appendBinaryFloatingPoint(value)
    }

    func append(_ value: Int) throws {
        try self._appendFixedWidthInteger(value)
    }

    func append(_ value: Int8) throws {
        try self._appendFixedWidthInteger(value)
    }

    func append(_ value: Int16) throws {
        try self._appendFixedWidthInteger(value)
    }

    func append(_ value: Int32) throws {
        try self._appendFixedWidthInteger(value)
    }

    func append(_ value: Int64) throws {
        try self._appendFixedWidthInteger(value)
    }

    func append(_ value: UInt) throws {
        try self._appendFixedWidthInteger(value)
    }

    func append(_ value: UInt8) throws {
        try self._appendFixedWidthInteger(value)
    }

    func append(_ value: UInt16) throws {
        try self._appendFixedWidthInteger(value)
    }

    func append(_ value: UInt32) throws {
        try self._appendFixedWidthInteger(value)
    }

    func append(_ value: UInt64) throws {
        try self._appendFixedWidthInteger(value)
    }

    func append(_ value: Data) throws {
        try self.currentStackEntry.storage.appendBareItem(.undecodedByteSequence(value.base64EncodedString()))
    }

    func append(_ value: Decimal) throws {
        let significand = (value.significand.magnitude as NSNumber).intValue  // Yes, really.
        guard let exponent = Int8(exactly: value.exponent) else {
            throw StructuredHeaderError.invalidIntegerOrDecimal
        }

        let pd = PseudoDecimal(mantissa: significand * (value.isSignMinus ? -1 : 1), exponent: Int(exponent))
        try self.currentStackEntry.storage.appendBareItem(.decimal(pd))
    }

    func append(_ value: Date) throws {
        let date = Int64(value.timeIntervalSince1970)
        try self.currentStackEntry.storage.appendBareItem(.date(date))
    }

    func append(_ value: DisplayString) throws {
        try self.currentStackEntry.storage.appendBareItem(.displayString(value.rawValue))
    }

    func append<T>(_ value: T) throws where T: Encodable {
        switch value {
        case let value as UInt8:
            try self.append(value)
        case let value as Int8:
            try self.append(value)
        case let value as UInt16:
            try self.append(value)
        case let value as Int16:
            try self.append(value)
        case let value as UInt32:
            try self.append(value)
        case let value as Int32:
            try self.append(value)
        case let value as UInt64:
            try self.append(value)
        case let value as Int64:
            try self.append(value)
        case let value as Int:
            try self.append(value)
        case let value as UInt:
            try self.append(value)
        case let value as Float:
            try self.append(value)
        case let value as Double:
            try self.append(value)
        case let value as String:
            try self.append(value)
        case let value as Bool:
            try self.append(value)
        case let value as Data:
            try self.append(value)
        case let value as Decimal:
            try self.append(value)
        case let value as Date:
            try self.append(value)
        case let value as DisplayString:
            try self.append(value)
        default:
            // Some other codable type.
            switch self.currentStackEntry.storage {
            case .listHeader, .list:
                // This may be an item or inner list.
                self.push(key: .init(intValue: self.count), newStorage: .itemOrInnerList([:]))
                try value.encode(to: self)
                try self.pop()

            case .itemOrInnerList(let params):
                // This is an inner list.
                self.currentStackEntry.storage = .innerList(InnerList(bareInnerList: [], parameters: params))
                fallthrough

            case .innerList, .bareInnerList:
                // This may only be an item.
                self.push(key: .init(intValue: self.count), newStorage: .item(.init(bareItem: nil, parameters: [:])))
                try value.encode(to: self)
                try self.pop()

            case .dictionaryHeader, .dictionary, .itemHeader, .item, .parameters:
                throw StructuredHeaderError.invalidTypeForItem
            }
        }
    }

    private func _appendBinaryFloatingPoint<T: BinaryFloatingPoint>(_ value: T) throws {
        // We go via double and encode it as a decimal.
        let pseudoDecimal = try PseudoDecimal(Double(value))
        try self.currentStackEntry.storage.appendBareItem(.decimal(pseudoDecimal))
    }

    private func _appendFixedWidthInteger<T: FixedWidthInteger>(_ value: T) throws {
        guard let base = Int64(exactly: value) else {
            throw StructuredHeaderError.integerOutOfRange
        }
        try self.currentStackEntry.storage.appendBareItem(.integer(base))
    }
}

extension _StructuredFieldEncoder {
    // This extension sort-of corresponds to the keyed encoding container: all of
    // these methods are called from there. All our keyed encoding containers use
    // string keys.
    func encode(_ value: Bool, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self.currentStackEntry.storage.insertBareItem(.bool(value), atKey: key)
    }

    func encode(_ value: String, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        if value.structuredHeadersIsValidToken {
            try self.currentStackEntry.storage.insertBareItem(.token(value), atKey: key)
        } else {
            try self.currentStackEntry.storage.insertBareItem(.string(value), atKey: key)
        }
    }

    func encode(_ value: Double, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeBinaryFloatingPoint(value, forKey: key)
    }

    func encode(_ value: Float, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeBinaryFloatingPoint(value, forKey: key)
    }

    func encode(_ value: Int, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeFixedWidthInteger(value, forKey: key)
    }

    func encode(_ value: Int8, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeFixedWidthInteger(value, forKey: key)
    }

    func encode(_ value: Int16, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeFixedWidthInteger(value, forKey: key)
    }

    func encode(_ value: Int32, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeFixedWidthInteger(value, forKey: key)
    }

    func encode(_ value: Int64, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeFixedWidthInteger(value, forKey: key)
    }

    func encode(_ value: UInt, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeFixedWidthInteger(value, forKey: key)
    }

    func encode(_ value: UInt8, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeFixedWidthInteger(value, forKey: key)
    }

    func encode(_ value: UInt16, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeFixedWidthInteger(value, forKey: key)
    }

    func encode(_ value: UInt32, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeFixedWidthInteger(value, forKey: key)
    }

    func encode(_ value: UInt64, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self._encodeFixedWidthInteger(value, forKey: key)
    }

    func encode(_ value: Data, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        try self.currentStackEntry.storage.insertBareItem(
            .undecodedByteSequence(value.base64EncodedString()),
            atKey: key
        )
    }

    func encode(_ value: Decimal, forKey key: String) throws {
        let significand = (value.significand.magnitude as NSNumber).intValue  // Yes, really.
        guard let exponent = Int8(exactly: value.exponent) else {
            throw StructuredHeaderError.invalidIntegerOrDecimal
        }

        let pd = PseudoDecimal(mantissa: significand * (value.isSignMinus ? -1 : 1), exponent: Int(exponent))
        try self.currentStackEntry.storage.insertBareItem(.decimal(pd), atKey: key)
    }

    func encode(_ value: Date, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        let date = Int64(value.timeIntervalSince1970)
        try self.currentStackEntry.storage.insertBareItem(.date(date), atKey: key)
    }

    func encode(_ value: DisplayString, forKey key: String) throws {
        let key = self.sanitizeKey(key)
        let displayString = value.rawValue
        try self.currentStackEntry.storage.insertBareItem(.displayString(displayString), atKey: key)
    }

    func encode<T>(_ value: T, forKey key: String) throws where T: Encodable {
        let key = self.sanitizeKey(key)

        switch value {
        case let value as UInt8:
            try self.encode(value, forKey: key)
        case let value as Int8:
            try self.encode(value, forKey: key)
        case let value as UInt16:
            try self.encode(value, forKey: key)
        case let value as Int16:
            try self.encode(value, forKey: key)
        case let value as UInt32:
            try self.encode(value, forKey: key)
        case let value as Int32:
            try self.encode(value, forKey: key)
        case let value as UInt64:
            try self.encode(value, forKey: key)
        case let value as Int64:
            try self.encode(value, forKey: key)
        case let value as Int:
            try self.encode(value, forKey: key)
        case let value as UInt:
            try self.encode(value, forKey: key)
        case let value as Float:
            try self.encode(value, forKey: key)
        case let value as Double:
            try self.encode(value, forKey: key)
        case let value as String:
            try self.encode(value, forKey: key)
        case let value as Bool:
            try self.encode(value, forKey: key)
        case let value as Data:
            try self.encode(value, forKey: key)
        case let value as Decimal:
            try self.encode(value, forKey: key)
        case let value as Date:
            try self.encode(value, forKey: key)
        case let value as DisplayString:
            try self.encode(value, forKey: key)
        default:
            // Ok, we don't know what this is. This can only happen for a dictionary, or
            // for anything with parameters, or for lists, or for inner lists.
            switch self.currentStackEntry.storage {
            case .dictionaryHeader:
                // Ah, this is a dictionary, good to know. Initialize the storage, keep going.
                self.currentStackEntry.storage = .dictionary([:])
                fallthrough

            case .dictionary:
                // This must be an item or inner list.
                self.push(key: .init(stringValue: key), newStorage: .itemOrInnerList([:]))
                try value.encode(to: self)
                try self.pop()

            case .item:
                guard key == "parameters" else {
                    throw StructuredHeaderError.invalidTypeForItem
                }
                self.push(key: .init(stringValue: key), newStorage: .parameters([:]))
                try value.encode(to: self)
                try self.pop()

            case .innerList:
                switch key {
                case "items":
                    self.push(key: .init(stringValue: key), newStorage: .bareInnerList([]))
                    try value.encode(to: self)
                    try self.pop()
                case "parameters":
                    self.push(key: .init(stringValue: key), newStorage: .parameters([:]))
                    try value.encode(to: self)
                    try self.pop()
                default:
                    throw StructuredHeaderError.invalidTypeForItem
                }

            case .itemOrInnerList(let params):
                switch key {
                case "items":
                    // We're a list!
                    self.currentStackEntry.storage = .innerList(InnerList(bareInnerList: [], parameters: params))
                    self.push(key: .init(stringValue: key), newStorage: .bareInnerList([]))
                    try value.encode(to: self)
                    try self.pop()
                case "parameters":
                    self.push(key: .init(stringValue: key), newStorage: .parameters([:]))
                    try value.encode(to: self)
                    try self.pop()
                default:
                    throw StructuredHeaderError.invalidTypeForItem
                }

            case .listHeader:
                switch key {
                case "items":
                    // Ok, we're a list. Good to know.
                    self.push(key: .init(stringValue: key), newStorage: .list([]))
                    try value.encode(to: self)
                    try self.pop()
                default:
                    throw StructuredHeaderError.invalidTypeForItem
                }

            case .list, .itemHeader, .bareInnerList,
                .parameters:
                throw StructuredHeaderError.invalidTypeForItem
            }
        }
    }

    private func _encodeFixedWidthInteger<T: FixedWidthInteger>(_ value: T, forKey key: String) throws {
        guard let base = Int64(exactly: value) else {
            throw StructuredHeaderError.integerOutOfRange
        }
        try self.currentStackEntry.storage.insertBareItem(.integer(base), atKey: key)
    }

    private func _encodeBinaryFloatingPoint<T: BinaryFloatingPoint>(_ value: T, forKey key: String) throws {
        let pseudoDecimal = try PseudoDecimal(Double(value))
        try self.currentStackEntry.storage.insertBareItem(.decimal(pseudoDecimal), atKey: key)
    }

    private func sanitizeKey(_ key: String) -> String {
        if self.keyEncodingStrategy == .lowercase {
            return key.lowercased()
        } else {
            return key
        }
    }
}

extension _StructuredFieldEncoder {
    /// An entry in the coding stack for _StructuredFieldEncoder.
    ///
    /// This is used to keep track of where we are in the encode.
    private struct CodingStackEntry {
        var key: _StructuredHeaderCodingKey
        var storage: NodeType
    }

    /// The type of the node at the current level of the encoding hierarchy.
    /// This controls what container types are allowed, and is where partial
    /// encodes are stored.
    ///
    /// Note that we never have a bare item here. This is deliberate: bare items
    /// are not a container for anything else, and so can never appear.
    internal enum NodeType {
        case dictionaryHeader
        case listHeader
        case itemHeader
        case dictionary(OrderedMap<String, ItemOrInnerList>)
        case list([ItemOrInnerList])
        case innerList(InnerList)
        case item(PartialItem)
        case bareInnerList(BareInnerList)
        case parameters(OrderedMap<String, RFC9651BareItem>)
        case itemOrInnerList(OrderedMap<String, RFC9651BareItem>)

        /// A helper struct used to tolerate the fact that we need partial items,
        /// but our `Item` struct doesn't like that much.
        struct PartialItem {
            var bareItem: RFC9651BareItem?
            var parameters: OrderedMap<String, RFC9651BareItem>
        }

        /// This is called when a complete object has been built.
        mutating func insert(_ childData: NodeType, atKey key: _StructuredHeaderCodingKey) throws {
            // Only some things can be inside other things, and often that relies on
            // the specifics of the key.
            switch (self, childData) {
            case (.item(var item), .parameters(let params)) where key.stringValue == "parameters":
                // Oh cool, parameters. Love it. Save it.
                item.parameters = params
                self = .item(item)

            case (.innerList(var list), .parameters(let params)) where key.stringValue == "parameters":
                list.rfc9651Parameters = params
                self = .innerList(list)

            case (.innerList(var list), .bareInnerList(let bare)) where key.stringValue == "items":
                list.bareInnerList = bare
                self = .innerList(list)

            case (.innerList(var list), .item(let item)) where key.intValue != nil:
                list.bareInnerList.append(Item(item))
                self = .innerList(list)

            case (.bareInnerList(var list), .item(let item)):
                precondition(key.intValue == list.count)
                list.append(Item(item))
                self = .bareInnerList(list)

            case (.itemOrInnerList, .parameters(let params)) where key.stringValue == "parameters":
                self = .itemOrInnerList(params)

            case (.itemOrInnerList, .item(let item)):
                self = .item(item)

            case (.itemOrInnerList, .innerList(let list)):
                self = .innerList(list)

            case (.dictionary(var map), .innerList(let innerList)):
                map[key.stringValue] = .innerList(innerList)
                self = .dictionary(map)

            case (.dictionary(var map), .item(let item)):
                map[key.stringValue] = .item(Item(item))
                self = .dictionary(map)

            case (.listHeader, .list(let list)) where key.stringValue == "items":
                self = .list(list)

            case (.listHeader, .innerList(let innerList)) where key.intValue != nil:
                self = .list([.innerList(innerList)])

            case (.listHeader, .item(let item)) where key.intValue != nil:
                self = .list([.item(Item(item))])

            case (.list(var list), .innerList(let innerList)) where key.intValue != nil:
                list.append(.innerList(innerList))
                self = .list(list)

            case (.list(var list), .item(let item)) where key.intValue != nil:
                list.append(.item(Item(item)))
                self = .list(list)

            default:
                throw StructuredHeaderError.invalidTypeForItem
            }
        }

        /// Called to insert a bare item at a given level of the hierarchy.
        ///
        /// If the key is missing we will require the type to be `item`, in which case
        /// this will be for the "item" key.
        mutating func insertBareItem(_ bareItem: RFC9651BareItem, atKey key: String? = nil) throws {
            switch self {
            case .itemHeader:
                guard key == nil || key == "item" else {
                    throw StructuredHeaderError.invalidTypeForItem
                }
                self = .item(PartialItem(bareItem: bareItem, parameters: [:]))

            case .item(var partial):
                if key == nil || key == "item" {
                    partial.bareItem = bareItem
                    self = .item(partial)
                } else {
                    throw StructuredHeaderError.invalidTypeForItem
                }

            case .itemOrInnerList(let params):
                // Key can only be item: if we have a key, we must have asked for a keyed
                // container, which would have disambiguated what we were getting.
                if key == "item" {
                    self = .item(PartialItem(bareItem: bareItem, parameters: params))
                } else {
                    throw StructuredHeaderError.invalidTypeForItem
                }

            case .dictionaryHeader:
                // Ok cool, this is a dictionary.
                var map = OrderedMap<String, ItemOrInnerList>()

                // Bare item here means item, no parameters.
                map[key!] = .item(.init(bareItem: bareItem, parameters: [:]))
                self = .dictionary(map)

            case .dictionary(var map):
                // Bare item here means item, no parameters.
                map[key!] = .item(.init(bareItem: bareItem, parameters: [:]))
                self = .dictionary(map)

            case .parameters(var map):
                map[key!] = bareItem
                self = .parameters(map)

            case .listHeader, .list, .innerList, .bareInnerList:
                throw StructuredHeaderError.invalidTypeForItem
            }
        }

        /// Appends a bare item to the given container. This must be a list-type
        /// container that stores either bare items, or items.
        mutating func appendBareItem(_ bareItem: RFC9651BareItem) throws {
            switch self {
            case .listHeader:
                self = .list([.item(Item(bareItem: bareItem, parameters: [:]))])

            case .list(var list):
                list.append(.item(Item(bareItem: bareItem, parameters: [:])))
                self = .list(list)

            case .innerList(var list):
                list.bareInnerList.append(Item(bareItem: bareItem, parameters: [:]))
                self = .innerList(list)

            case .bareInnerList(var list):
                list.append(Item(bareItem: bareItem, parameters: [:]))
                self = .bareInnerList(list)

            case .itemOrInnerList(let params):
                // This is an inner list.
                self = .innerList(
                    InnerList(bareInnerList: [Item(bareItem: bareItem, parameters: [:])], parameters: params)
                )

            case .dictionaryHeader, .dictionary, .itemHeader, .item,
                .parameters:
                throw StructuredHeaderError.invalidTypeForItem
            }
        }
    }
}

extension Item {
    fileprivate init(_ partialItem: _StructuredFieldEncoder.NodeType.PartialItem) {
        self.init(bareItem: partialItem.bareItem!, parameters: partialItem.parameters)
    }
}
