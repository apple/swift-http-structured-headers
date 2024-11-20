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

private let validIntegerRange = Int64(-999_999_999_999_999)...Int64(999_999_999_999_999)

/// A `StructuredFieldValueSerializer` is the basic parsing object for structured header field values.
public struct StructuredFieldValueSerializer: Sendable {
    private var data: [UInt8]

    public init() {
        self.data = []
    }
}

extension StructuredFieldValueSerializer {
    /// Writes a structured dictionary header field value.
    ///
    /// - parameters:
    ///     - root: The dictionary object.
    /// - throws: If the dictionary could not be serialized.
    /// - returns: The bytes of the serialized header field value.
    public mutating func writeDictionaryFieldValue(_ root: OrderedMap<String, ItemOrInnerList>) throws -> [UInt8] {
        guard root.count > 0 else {
            return []
        }

        defer {
            self.data.removeAll(keepingCapacity: true)
        }
        try self.serializeADictionary(root)
        return self.data
    }

    /// Writes a structured list header field value.
    ///
    /// - parameters:
    ///     - list: The list object.
    /// - throws: If the list could not be serialized.
    /// - returns: The bytes of the serialized header field value.
    public mutating func writeListFieldValue(_ list: [ItemOrInnerList]) throws -> [UInt8] {
        guard list.count > 0 else {
            return []
        }

        defer {
            self.data.removeAll(keepingCapacity: true)
        }
        try self.serializeAList(list)
        return self.data
    }

    /// Writes a structured item header field value.
    ///
    /// - parameters:
    ///     - item: The item.
    /// - throws: If the item could not be serialized.
    /// - returns: The bytes of the serialized header field value.
    public mutating func writeItemFieldValue(_ item: Item) throws -> [UInt8] {
        defer {
            self.data.removeAll(keepingCapacity: true)
        }
        try self.serializeAnItem(item)
        return self.data
    }
}

extension StructuredFieldValueSerializer {
    private mutating func serializeADictionary(_ dictionary: OrderedMap<String, ItemOrInnerList>) throws {
        for (name, value) in dictionary {
            try self.serializeAKey(name)

            if case .item(let item) = value, case .bool(true) = item.rfc9651BareItem {
                try self.serializeParameters(item.rfc9651Parameters)
            } else {
                self.data.append(asciiEqual)

                switch value {
                case .innerList(let inner):
                    try self.serializeAnInnerList(inner)
                case .item(let item):
                    try self.serializeAnItem(item)
                }
            }

            self.data.append(asciiComma)
            self.data.append(asciiSpace)
        }

        self.data.removeLast(2)
    }

    private mutating func serializeAList(_ list: [ItemOrInnerList]) throws {
        for element in list.dropLast() {
            switch element {
            case .innerList(let innerList):
                try self.serializeAnInnerList(innerList)
            case .item(let item):
                try self.serializeAnItem(item)
            }

            self.data.append(asciiComma)
            self.data.append(asciiSpace)
        }

        if let last = list.last {
            switch last {
            case .innerList(let innerList):
                try self.serializeAnInnerList(innerList)
            case .item(let item):
                try self.serializeAnItem(item)
            }
        }
    }

    private mutating func serializeAnInnerList(_ innerList: InnerList) throws {
        self.data.append(asciiOpenParenthesis)

        for item in innerList.bareInnerList.dropLast() {
            try self.serializeAnItem(item)
            self.data.append(asciiSpace)
        }

        if let last = innerList.bareInnerList.last {
            try self.serializeAnItem(last)
        }

        self.data.append(asciiCloseParenthesis)

        try self.serializeParameters(innerList.rfc9651Parameters)
    }

    private mutating func serializeAnItem(_ item: Item) throws {
        try self.serializeABareItem(item.rfc9651BareItem)
        try self.serializeParameters(item.rfc9651Parameters)
    }

    private mutating func serializeParameters(_ parameters: OrderedMap<String, RFC9651BareItem>) throws {
        for (key, value) in parameters {
            self.data.append(asciiSemicolon)
            try self.serializeAKey(key)

            if case .bool(true) = value {
                // Don't serialize boolean true
                continue
            }

            self.data.append(asciiEqual)
            try self.serializeABareItem(value)
        }
    }

    private mutating func serializeAKey(_ key: String) throws {
        // We touch each byte twice here, but that's ok: this is cache friendly and less branchy (the copy gets to be memcpy in some cases!)
        try key.validateStructuredHeaderKey()
        self.data.append(contentsOf: key.utf8)
    }

    private mutating func serializeABareItem(_ item: RFC9651BareItem) throws {
        switch item {
        case .integer(let int):
            guard let wideInt = Int64(exactly: int), validIntegerRange.contains(wideInt) else {
                throw StructuredHeaderError.invalidIntegerOrDecimal
            }

            self.data.append(contentsOf: String(int, radix: 10).utf8)

        case .decimal(let decimal):
            self.data.append(contentsOf: String(decimal).utf8)
        case .string(let string):
            let bytes = string.utf8
            guard bytes.allSatisfy({ !(0x00...0x1F).contains($0) && $0 != 0x7F && $0 < 0x80 }) else {
                throw StructuredHeaderError.invalidString
            }
            self.data.append(asciiDquote)
            for byte in bytes {
                if byte == asciiBackslash || byte == asciiDquote {
                    self.data.append(asciiBackslash)
                }
                self.data.append(byte)
            }
            self.data.append(asciiDquote)
        case .token(let token):
            guard token.structuredHeadersIsValidToken else {
                throw StructuredHeaderError.invalidToken
            }
            self.data.append(contentsOf: token.utf8)
        case .undecodedByteSequence(let bytes):
            // We require the user to have gotten this right.
            self.data.append(asciiColon)
            self.data.append(contentsOf: bytes.utf8)
            self.data.append(asciiColon)
        case .bool(let bool):
            self.data.append(asciiQuestionMark)
            let character = bool ? asciiOne : asciiZero
            self.data.append(character)
        case .date(let date):
            self.data.append(asciiAt)

            // Then, serialize as integer.
            guard let wideInt = Int64(exactly: date), validIntegerRange.contains(wideInt) else {
                throw StructuredHeaderError.invalidDate
            }

            self.data.append(contentsOf: String(date, radix: 10).utf8)
        case .displayString(let displayString):
            let bytes = displayString.utf8

            self.data.append(asciiPercent)
            self.data.append(asciiDquote)

            for byte in bytes {
                if byte == asciiPercent
                    || byte == asciiDquote
                    || (0x00...0x1F).contains(byte)
                    || (0x7F...).contains(byte)
                {
                    self.data.append(asciiPercent)

                    let encodedByte = UInt8.encodeToHex(byte)
                    self.data.append(encodedByte.firstChar)
                    self.data.append(encodedByte.secondChar)
                } else {
                    self.data.append(byte)
                }
            }

            self.data.append(asciiDquote)
        }
    }
}

extension String {
    func validateStructuredHeaderKey() throws {
        let utf8View = self.utf8
        if let firstByte = utf8View.first {
            switch firstByte {
            case asciiLowercases, asciiAsterisk:
                // Good
                ()
            default:
                throw StructuredHeaderError.invalidKey
            }
        }

        let validKey = utf8View.dropFirst().allSatisfy {
            switch $0 {
            case asciiLowercases, asciiDigits, asciiUnderscore,
                asciiDash, asciiPeriod, asciiAsterisk:
                return true
            default:
                return false
            }
        }

        guard validKey else {
            throw StructuredHeaderError.invalidKey
        }
    }
}

extension UInt8 {
    /// Converts an integer in base 10 to hex of type `EncodedHex`.
    fileprivate static func encodeToHex(_ int: Self) -> EncodedHex {
        let firstChar = self.itoh(int >> 4)
        let secondChar = self.itoh(int & 0x0F)

        return EncodedHex([firstChar, secondChar])
    }

    /// Converts an integer to its hex character in UTF8.
    private static func itoh(_ int: Self) -> Self {
        (int > 9) ? (asciiLowerA + int - 10) : (asciiZero + int)
    }
}
