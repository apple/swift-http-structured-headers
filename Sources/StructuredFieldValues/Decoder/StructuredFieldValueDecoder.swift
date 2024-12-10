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

/// A `StructuredFieldValueDecoder` allows decoding `Decodable` objects from a HTTP
/// structured header field.
public struct StructuredFieldValueDecoder: Sendable {
    /// A strategy that should be used to map coding keys to wire format keys.
    public var keyDecodingStrategy: KeyDecodingStrategy?

    public init() {}
}

extension StructuredFieldValueDecoder {
    /// A strategy that should be used to map coding keys to wire format keys.
    public struct KeyDecodingStrategy: Hashable, Sendable {
        fileprivate enum Base: Hashable {
            case lowercase
        }

        fileprivate var base: Base

        /// Lowercase all coding keys before searching for them in keyed containers such as
        /// dictionaries or parameters.
        public static let lowercase = KeyDecodingStrategy(base: .lowercase)
    }
}

extension StructuredFieldValueDecoder {
    /// Attempt to decode an object from a structured header field.
    ///
    /// - parameters:
    ///     - type: The type of the object to decode.
    ///     - data: The bytes of the structured header field.
    /// - throws: If the header field could not be parsed, or could not be decoded.
    /// - returns: An object of type `StructuredField`.
    public func decode<StructuredField: StructuredFieldValue, BaseData: RandomAccessCollection>(
        _ type: StructuredField.Type = StructuredField.self,
        from data: BaseData
    ) throws -> StructuredField where BaseData.Element == UInt8 {
        switch StructuredField.structuredFieldType {
        case .item:
            return try self.decodeItemField(from: data)
        case .list:
            return try self.decodeListField(from: data)
        case .dictionary:
            return try self.decodeDictionaryField(from: data)
        }
    }

    /// Attempt to decode an object from a structured header dictionary field.
    ///
    /// - parameters:
    ///     - type: The type of the object to decode.
    ///     - data: The bytes of the structured header field.
    /// - throws: If the header field could not be parsed, or could not be decoded.
    /// - returns: An object of type `StructuredField`.
    private func decodeDictionaryField<StructuredField: Decodable, BaseData: RandomAccessCollection>(
        _ type: StructuredField.Type = StructuredField.self,
        from data: BaseData
    ) throws -> StructuredField where BaseData.Element == UInt8 {
        let parser = StructuredFieldValueParser(data)
        let decoder = _StructuredFieldDecoder(parser, keyDecodingStrategy: self.keyDecodingStrategy)
        try decoder.parseDictionaryField()
        return try type.init(from: decoder)
    }

    /// Attempt to decode an object from a structured header list field.
    ///
    /// - parameters:
    ///     - type: The type of the object to decode.
    ///     - data: The bytes of the structured header field.
    /// - throws: If the header field could not be parsed, or could not be decoded.
    /// - returns: An object of type `StructuredField`.
    private func decodeListField<StructuredField: Decodable, BaseData: RandomAccessCollection>(
        _ type: StructuredField.Type = StructuredField.self,
        from data: BaseData
    ) throws -> StructuredField where BaseData.Element == UInt8 {
        let parser = StructuredFieldValueParser(data)
        let decoder = _StructuredFieldDecoder(parser, keyDecodingStrategy: self.keyDecodingStrategy)
        try decoder.parseListField()
        return try type.init(from: decoder)
    }

    /// Attempt to decode an object from a structured header item field.
    ///
    /// - parameters:
    ///     - type: The type of the object to decode.
    ///     - data: The bytes of the structured header field.
    /// - throws: If the header field could not be parsed, or could not be decoded.
    /// - returns: An object of type `StructuredField`.
    private func decodeItemField<StructuredField: Decodable, BaseData: RandomAccessCollection>(
        _ type: StructuredField.Type = StructuredField.self,
        from data: BaseData
    ) throws -> StructuredField where BaseData.Element == UInt8 {
        let parser = StructuredFieldValueParser(data)
        let decoder = _StructuredFieldDecoder(parser, keyDecodingStrategy: self.keyDecodingStrategy)
        try decoder.parseItemField()

        // An escape hatch here for top-level data: if we don't do this, it'll ask for
        // an unkeyed container and get very confused.
        switch type {
        case is Data.Type:
            let container = try decoder.singleValueContainer()
            return try container.decode(Data.self) as! StructuredField
        case is Decimal.Type:
            let container = try decoder.singleValueContainer()
            return try container.decode(Decimal.self) as! StructuredField
        case is Date.Type:
            let container = try decoder.singleValueContainer()
            return try container.decode(Date.self) as! StructuredField
        case is DisplayString.Type:
            let container = try decoder.singleValueContainer()
            return try container.decode(DisplayString.self) as! StructuredField
        default:
            return try type.init(from: decoder)
        }
    }
}

class _StructuredFieldDecoder<BaseData: RandomAccessCollection> where BaseData.Element == UInt8 {
    private var parser: StructuredFieldValueParser<BaseData>

    // For now we use a stack here because the CoW operations on Array would suck. Ideally I'd just have us decode
    // our way down with values, but doing that is a CoWy nightmare from which we cannot escape.
    private var _codingStack: [CodingStackEntry]

    var keyDecodingStrategy: StructuredFieldValueDecoder.KeyDecodingStrategy?

    init(
        _ parser: StructuredFieldValueParser<BaseData>,
        keyDecodingStrategy: StructuredFieldValueDecoder.KeyDecodingStrategy?
    ) {
        self.parser = parser
        self._codingStack = []
        self.keyDecodingStrategy = keyDecodingStrategy
    }
}

extension _StructuredFieldDecoder: Decoder {
    var codingPath: [CodingKey] {
        self._codingStack.map { $0.key as CodingKey }
    }

    var userInfo: [CodingUserInfoKey: Any] {
        [:]
    }

    func push(_ codingKey: _StructuredHeaderCodingKey) throws {
        // This force-unwrap is safe: we cannot create containers without having first
        // produced the base element, which will always be present.
        let nextElement = try self.currentElement!.innerElement(for: codingKey)
        self._codingStack.append(CodingStackEntry(key: codingKey, element: nextElement))
    }

    func pop() {
        self._codingStack.removeLast()
    }

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        switch self.currentElement! {
        case .dictionary(let dictionary):
            return KeyedDecodingContainer(DictionaryKeyedContainer(dictionary, decoder: self))
        case .item(let item):
            return KeyedDecodingContainer(KeyedItemDecoder(item, decoder: self))
        case .list(let list):
            return KeyedDecodingContainer(KeyedTopLevelListDecoder(list, decoder: self))
        case .innerList(let innerList):
            return KeyedDecodingContainer(KeyedInnerListDecoder(innerList, decoder: self))
        case .parameters(let parameters):
            return KeyedDecodingContainer(ParametersDecoder(parameters, decoder: self))
        case .bareItem, .bareInnerList:
            // No keyed container for these types.
            throw StructuredHeaderError.invalidTypeForItem
        }
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        // We have unkeyed containers for lists, inner lists, and bare inner lists.
        switch self.currentElement! {
        case .list(let items):
            return TopLevelListDecoder(items, decoder: self)
        case .innerList(let innerList):
            return BareInnerListDecoder(innerList.bareInnerList, decoder: self)
        case .bareInnerList(let bareInnerList):
            return BareInnerListDecoder(bareInnerList, decoder: self)
        case .dictionary, .item, .bareItem, .parameters:
            // No unkeyed container for these types.
            throw StructuredHeaderError.invalidTypeForItem
        }
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        // We have single value containers for items and bareItems.
        switch self.currentElement! {
        case .item(let item):
            return BareItemDecoder(item.rfc9651BareItem, codingPath: self._codingStack.map { $0.key })
        case .bareItem(let bareItem):
            return BareItemDecoder(bareItem, codingPath: self._codingStack.map { $0.key })
        case .dictionary, .list, .innerList, .bareInnerList, .parameters:
            throw StructuredHeaderError.invalidTypeForItem
        }
    }

    func parseDictionaryField() throws {
        precondition(self._codingStack.isEmpty)
        let parsed = try self.parser.parseDictionaryFieldValue()

        // We unconditionally add to the base of the coding stack here. This element is never popped off.
        self._codingStack.append(CodingStackEntry(key: .init(stringValue: ""), element: .dictionary(parsed)))
    }

    func parseListField() throws {
        precondition(self._codingStack.isEmpty)
        let parsed = try self.parser.parseListFieldValue()

        // We unconditionally add to the base of the coding stack here. This element is never popped off.
        self._codingStack.append(CodingStackEntry(key: .init(stringValue: ""), element: .list(parsed)))
    }

    func parseItemField() throws {
        precondition(self._codingStack.isEmpty)
        let parsed = try self.parser.parseItemFieldValue()

        // We unconditionally add to the base of the coding stack here. This element is never popped off.
        self._codingStack.append(CodingStackEntry(key: .init(stringValue: ""), element: .item(parsed)))
    }
}

extension _StructuredFieldDecoder {
    /// The basic elements that make up a Structured Header
    fileprivate enum Element {
        case dictionary(OrderedMap<String, ItemOrInnerList>)
        case list([ItemOrInnerList])
        case item(Item)
        case innerList(InnerList)
        case bareItem(RFC9651BareItem)
        case bareInnerList(BareInnerList)
        case parameters(OrderedMap<String, RFC9651BareItem>)

        func innerElement(for key: _StructuredHeaderCodingKey) throws -> Element {
            switch self {
            case .dictionary(let dictionary):
                guard let element = dictionary.first(where: { $0.0 == key.stringValue }) else {
                    throw StructuredHeaderError.invalidTypeForItem
                }
                switch element.1 {
                case .item(let item):
                    return .item(item)
                case .innerList(let innerList):
                    return .innerList(innerList)
                }
            case .list(let list):
                if let offset = key.intValue {
                    guard offset < list.count else {
                        throw StructuredHeaderError.invalidTypeForItem
                    }
                    let index = list.index(list.startIndex, offsetBy: offset)
                    switch list[index] {
                    case .item(let item):
                        return .item(item)
                    case .innerList(let innerList):
                        return .innerList(innerList)
                    }
                } else if key.stringValue == "items" {
                    // Oh, the outer layer is keyed. That's fine, just put ourselves
                    // back on the stack.
                    return .list(list)
                } else {
                    throw StructuredHeaderError.invalidTypeForItem
                }
            case .item(let item):
                // Two keys, "item" and "parameters".
                switch key.stringValue {
                case "item":
                    return .bareItem(item.rfc9651BareItem)
                case "parameters":
                    return .parameters(item.rfc9651Parameters)
                default:
                    throw StructuredHeaderError.invalidTypeForItem
                }
            case .innerList(let innerList):
                // Quick check: is this an integer key? If it is, treat this like a bare inner list. Otherwise
                // there are two string keys: "items" and "parameters"
                if key.intValue != nil {
                    return try Element.bareInnerList(innerList.bareInnerList).innerElement(for: key)
                }

                switch key.stringValue {
                case "items":
                    return .bareInnerList(innerList.bareInnerList)
                case "parameters":
                    return .parameters(innerList.rfc9651Parameters)
                default:
                    throw StructuredHeaderError.invalidTypeForItem
                }
            case .bareItem:
                // Bare items may never be parsed through.
                throw StructuredHeaderError.invalidTypeForItem
            case .bareInnerList(let innerList):
                guard let offset = key.intValue, offset < innerList.count else {
                    throw StructuredHeaderError.invalidTypeForItem
                }
                let index = innerList.index(innerList.startIndex, offsetBy: offset)
                return .item(innerList[index])
            case .parameters(let params):
                guard let element = params.first(where: { $0.0 == key.stringValue }) else {
                    throw StructuredHeaderError.invalidTypeForItem
                }
                return .bareItem(element.1)
            }
        }
    }
}

extension _StructuredFieldDecoder {
    /// An entry in the coding stack for _StructuredFieldDecoder.
    ///
    /// This is used to keep track of where we are in the decode.
    private struct CodingStackEntry {
        var key: _StructuredHeaderCodingKey
        var element: Element
    }

    /// The element at the current head of the coding stack.
    private var currentElement: Element? {
        self._codingStack.last.map { $0.element }
    }
}
