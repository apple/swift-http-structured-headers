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

public struct StructuredFieldDecoder {
    public init() { }
}

extension StructuredFieldDecoder {
    public func decode<StructuredField: Decodable, BaseData: RandomAccessCollection>(_ type: StructuredField.Type = StructuredField.self, from data: BaseData) throws -> StructuredField where BaseData.Element == UInt8, BaseData.SubSequence: Hashable {
        let parser = StructuredFieldParser(data)
        let decoder = _StructuredFieldDecoder(parser)
        return try type.init(from: decoder)
    }
}

class _StructuredFieldDecoder<BaseData: RandomAccessCollection> where BaseData.Element == UInt8, BaseData.SubSequence: Hashable {
    private var parser: StructuredFieldParser<BaseData>

    // For now we use a stack here because the CoW operations on Array would stuck. Ideally I'd just have us decode
    // our way down with values, but doing that is a CoWy nightmare from which we cannot escape.
    private var _codingStack: [CodingStackEntry]

    init(_ parser: StructuredFieldParser<BaseData>) {
        self.parser = parser
        self._codingStack = []
    }
}

extension _StructuredFieldDecoder: Decoder {
    var codingPath: [CodingKey] {
        return self._codingStack.map { $0.key as CodingKey }
    }

    var userInfo: [CodingUserInfoKey : Any] {
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

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        if self.currentElement == nil {
            // First parse, this is a dictionary.
            // TODO: This assumption is wrong. Item and List headers may appear here if users want
            // their parameters. We have to check for those cases.
            let parsed = try self.parser.parseDictionaryField()

            // We unconditionally add to the base of the coding stack here. This element is never popped off.
            self._codingStack.append(CodingStackEntry(key: .init(stringValue: ""), element: .dictionary(parsed)))
        }

        switch self.currentElement! {
        case .dictionary(let dictionary):
            return KeyedDecodingContainer(DictionaryKeyedContainer(dictionary, decoder: self))
        case .item(let item):
            return KeyedDecodingContainer(KeyedItemDecoder(item, decoder: self))
        case .innerList(let innerList):
            return KeyedDecodingContainer(KeyedInnerListDecoder(innerList, decoder: self))
        case .parameters(let parameters):
            return KeyedDecodingContainer(ParametersDecoder(parameters, decoder: self))
        case .bareItem, .bareInnerList, .list:
            // No keyed container for these types.
            throw StructuredHeaderError.invalidTypeForItem
        }
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        if self.currentElement == nil {
            // First parse, this is a list header.
            let parsed = try self.parser.parseListField()

            // We unconditionally add to the base of the coding stack here. This element is never popped off.
            self._codingStack.append(CodingStackEntry(key: .init(stringValue: ""), element: .list(parsed)))
        }

        // We have unkeyed containers for lists, inner lists, and bare inner lists.
        switch self.currentElement! {
        case .list(let items):
            fatalError("Not yet implemented")
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
        if self.currentElement == nil {
            // First parse, this is a an item header.
            let parsed = try self.parser.parseItemField()

            // We unconditionally add to the base of the coding stack here. This element is never popped off.
            self._codingStack.append(CodingStackEntry(key: .init(stringValue: ""), element: .item(parsed)))
        }

        // We have single value containers for items and bareItems.
        switch self.currentElement! {
        case .item(let item):
            return BareItemDecoder(item.bareItem, codingPath: self._codingStack.map { $0.key })
        case .bareItem(let bareItem):
            return BareItemDecoder(bareItem, codingPath: self._codingStack.map { $0.key })
        case .dictionary, .list, .innerList, .bareInnerList, .parameters:
            throw StructuredHeaderError.invalidTypeForItem
        }
    }
}

extension _StructuredFieldDecoder {
    /// The basic elements that make up a Structured Header
    fileprivate enum Element {
        case dictionary(OrderedMap<BaseData.SubSequence, ItemOrInnerList<BaseData.SubSequence>>)
        case list([ItemOrInnerList<BaseData.SubSequence>])
        case item(Item<BaseData.SubSequence>)
        case innerList(InnerList<BaseData.SubSequence>)
        case bareItem(BareItem<BaseData.SubSequence>)
        case bareInnerList(BareInnerList<BaseData.SubSequence>)
        case parameters(OrderedMap<BaseData.SubSequence, BareItem<BaseData.SubSequence>>)

        func innerElement(for key: _StructuredHeaderCodingKey) throws -> Element {
            switch self {
            case .dictionary(let dictionary):
                guard let element = dictionary.first(where: { $0.0.elementsEqual(key.stringValue.utf8) }) else {
                    throw StructuredHeaderError.invalidTypeForItem
                }
                switch element.1 {
                case .item(let item):
                    return .item(item)
                case .innerList(let innerList):
                    return .innerList(innerList)
                }
            case .list(let list):
                guard let offset = key.intValue, offset < list.count else {
                    throw StructuredHeaderError.invalidTypeForItem
                }
                let index = list.index(list.startIndex, offsetBy: offset)
                switch list[index] {
                case .item(let item):
                    return .item(item)
                case .innerList(let innerList):
                    return .innerList(innerList)
                }
            case .item(let item):
                // Two keys, "item" and "parameters".
                switch key.stringValue {
                case "item":
                    return .bareItem(item.bareItem)
                case "parameters":
                    return .parameters(item.parameters)
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
                    return .parameters(innerList.parameters)
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
                guard let element = params.first(where: { $0.0.elementsEqual(key.stringValue.utf8) }) else {
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
        return self._codingStack.last.map { $0.element }
    }
}
