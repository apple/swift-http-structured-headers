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

/// A `StructuredFieldValueParser` is the basic parsing object for structured header field values.
public struct StructuredFieldValueParser<BaseData: RandomAccessCollection> where BaseData.Element == UInt8 {
    // Right now I'm on the fence about whether this should be generic. It's convenient,
    // and makes it really easy for us to express the parsing over a wide range of data types.
    // But it risks code size in a really nasty way! We should validate that we don't pay too
    // much for this flexibility.
    private var underlyingData: BaseData.SubSequence

    public init(_ data: BaseData) {
        self.underlyingData = data[...]
    }
}

extension StructuredFieldValueParser: Sendable where BaseData: Sendable, BaseData.SubSequence: Sendable {}

extension StructuredFieldValueParser {
    // Helper typealiases to avoid the explosion of generic parameters
    @available(*, deprecated, renamed: "RFC9651BareItem")
    public typealias BareItem = RawStructuredFieldValues.BareItem
    public typealias RFC9651BareItem = RawStructuredFieldValues.RFC9651BareItem
    public typealias Item = RawStructuredFieldValues.Item
    public typealias BareInnerList = RawStructuredFieldValues.BareInnerList
    public typealias InnerList = RawStructuredFieldValues.InnerList
    public typealias ItemOrInnerList = RawStructuredFieldValues.ItemOrInnerList
    public typealias Key = String

    /// Parse the HTTP structured field value as a list.
    ///
    /// This is a straightforward implementation of the parser in the spec.
    ///
    /// - throws: If the field value could not be parsed.
    /// - returns: An array of items or inner lists.
    public mutating func parseListFieldValue() throws -> [ItemOrInnerList] {
        // Step one, strip leading spaces.
        self.underlyingData.stripLeadingSpaces()

        // Step 2, enter the core list parsing loop.
        let members = try self._parseAList()

        // Final step, strip trailing spaces (which are now leading spaces, natch).
        self.underlyingData.stripLeadingSpaces()

        // The data is _required_ to be empty now, if it isn't we fail.
        guard self.underlyingData.count == 0 else {
            throw StructuredHeaderError.invalidTrailingBytes
        }

        return members
    }

    /// Parse the HTTP structured header field value as a dictionary.
    ///
    /// - throws: If the field value could not be parsed.
    /// - returns: An ``OrderedMap`` corresponding to the entries in the dictionary.
    public mutating func parseDictionaryFieldValue() throws -> OrderedMap<Key, ItemOrInnerList> {
        // Step one, strip leading spaces.
        self.underlyingData.stripLeadingSpaces()

        // Step 2, enter the core dictionary parsing loop.
        let map = try self._parseADictionary()

        // Final step, strip trailing spaces (which are now leading spaces, natch).
        self.underlyingData.stripLeadingSpaces()

        // The data is _required_ to be empty now, if it isn't we fail.
        guard self.underlyingData.count == 0 else {
            throw StructuredHeaderError.invalidTrailingBytes
        }

        return map
    }

    /// Parse the HTTP structured header field value as an item.
    ///
    /// - throws: If the field value could not be parsed.
    /// - returns: The ``Item`` in the field.
    public mutating func parseItemFieldValue() throws -> Item {
        // Step one, strip leading spaces.
        self.underlyingData.stripLeadingSpaces()

        // Step 2, do the core parse.
        let item = try self._parseAnItem()

        // Final step, strip trailing spaces (which are now leading spaces, natch).
        self.underlyingData.stripLeadingSpaces()

        // The data is _required_ to be empty now, if it isn't we fail.
        guard self.underlyingData.count == 0 else {
            throw StructuredHeaderError.invalidTrailingBytes
        }

        return item
    }

    private mutating func _parseAList() throws -> [ItemOrInnerList] {
        var results: [ItemOrInnerList] = []

        loop: while self.underlyingData.count > 0 {
            results.append(try self._parseAnItemOrInnerList())
            self.underlyingData.stripLeadingOWS()

            // If we've consumed all the data, the parse is finished.
            guard let next = self.underlyingData.popFirst() else {
                break loop
            }

            // Otherwise, the next character needs to be a comma.
            guard next == asciiComma else {
                throw StructuredHeaderError.invalidList
            }
            self.underlyingData.stripLeadingOWS()
            guard self.underlyingData.count > 0 else {
                // Trailing comma!
                throw StructuredHeaderError.invalidList
            }
        }

        return results
    }

    private mutating func _parseADictionary() throws -> OrderedMap<Key, ItemOrInnerList> {
        var results = OrderedMap<Key, ItemOrInnerList>()

        loop: while self.underlyingData.count > 0 {
            let key = try self._parseAKey()

            if self.underlyingData.first == asciiEqual {
                self.underlyingData.consumeFirst()
                results[key] = try self._parseAnItemOrInnerList()
            } else {
                results[key] = .item(Item(bareItem: true, parameters: try self._parseParameters()))
            }

            self.underlyingData.stripLeadingOWS()

            /// If we've consumed all the data, the parse is finished.
            guard let next = self.underlyingData.popFirst() else {
                break loop
            }
            guard next == asciiComma else {
                throw StructuredHeaderError.invalidDictionary
            }
            self.underlyingData.stripLeadingOWS()

            guard self.underlyingData.count > 0 else {
                // Trailing comma!
                throw StructuredHeaderError.invalidList
            }
        }

        return results
    }

    private mutating func _parseAnItemOrInnerList() throws -> ItemOrInnerList {
        if self.underlyingData.first == asciiOpenParenthesis {
            return .innerList(try self._parseAnInnerList())
        } else {
            return .item(try self._parseAnItem())
        }
    }

    private mutating func _parseAnInnerList() throws -> InnerList {
        precondition(self.underlyingData.popFirst() == asciiOpenParenthesis)

        var innerList = BareInnerList()

        while self.underlyingData.count > 0 {
            self.underlyingData.stripLeadingSpaces()

            if self.underlyingData.first == asciiCloseParenthesis {
                // Consume, parse parameters, and complete.
                self.underlyingData.consumeFirst()
                let parameters = try self._parseParameters()
                return InnerList(bareInnerList: innerList, parameters: parameters)
            }

            innerList.append(try self._parseAnItem())

            let nextChar = self.underlyingData.first
            guard nextChar == asciiSpace || nextChar == asciiCloseParenthesis else {
                throw StructuredHeaderError.invalidInnerList
            }
        }

        // If we got here, we never got the close character for the list. Not good! This is an error.
        throw StructuredHeaderError.invalidInnerList
    }

    private mutating func _parseAnItem() throws -> Item {
        let bareItem = try _parseABareItem()
        let parameters = try self._parseParameters()
        return Item(bareItem: bareItem, parameters: parameters)
    }

    private mutating func _parseABareItem() throws -> RFC9651BareItem {
        guard let first = self.underlyingData.first else {
            throw StructuredHeaderError.invalidItem
        }

        switch first {
        case asciiDash, asciiDigits:
            return try self._parseAnIntegerOrDecimal(isDate: false)
        case asciiDquote:
            return try self._parseAString()
        case asciiColon:
            return try self._parseAByteSequence()
        case asciiQuestionMark:
            return try self._parseABoolean()
        case asciiCapitals, asciiLowercases, asciiAsterisk:
            return try self._parseAToken()
        case asciiAt:
            return try self._parseADate()
        case asciiPercent:
            return try self._parseADisplayString()
        default:
            throw StructuredHeaderError.invalidItem
        }
    }

    private mutating func _parseAnIntegerOrDecimal(isDate: Bool) throws -> RFC9651BareItem {
        var sign = Int64(1)
        var type = IntegerOrDecimal.integer

        if let first = self.underlyingData.first, first == asciiDash {
            sign = -1
            self.underlyingData.consumeFirst()
        }

        guard let first = self.underlyingData.first, asciiDigits.contains(first) else {
            throw StructuredHeaderError.invalidIntegerOrDecimal
        }

        var index = self.underlyingData.startIndex
        let endIndex = self.underlyingData.endIndex
        loop: while index < endIndex {
            switch self.underlyingData[index] {
            case asciiDigits:
                // Do nothing
                ()
            case asciiPeriod where type == .integer:
                // If output_date is decimal, fail parsing.
                if isDate {
                    throw StructuredHeaderError.invalidDate
                }

                // If input_number contains more than 12 characters, fail parsing. Otherwise,
                // set type to decimal and consume.
                if self.underlyingData.distance(from: self.underlyingData.startIndex, to: index) > 12 {
                    if isDate {
                        throw StructuredHeaderError.invalidDate
                    } else {
                        throw StructuredHeaderError.invalidIntegerOrDecimal
                    }
                }
                type = .decimal
            default:
                // Non period or number, we're done parsing.
                break loop
            }

            // "Consume" the character by advancing.
            self.underlyingData.formIndex(after: &index)

            // If type is integer and the input contains more than 15 characters, or type is decimal and more than 16,
            // fail parsing.
            let count = self.underlyingData.distance(from: self.underlyingData.startIndex, to: index)
            switch type {
            case .integer:
                if count > 15 {
                    if isDate {
                        throw StructuredHeaderError.invalidDate
                    } else {
                        throw StructuredHeaderError.invalidIntegerOrDecimal
                    }
                }
            case .decimal:
                assert(isDate == false)

                if count > 16 {
                    throw StructuredHeaderError.invalidIntegerOrDecimal
                }
            }
        }

        // Consume the string.
        let integerBytes = self.underlyingData[..<index]
        self.underlyingData = self.underlyingData[index...]

        switch type {
        case .integer:
            // This intermediate string is sad, we should rewrite this manually to avoid it.
            // This force-unwrap is safe, as we have validated that all characters are ascii digits.
            let baseInt = Int64(String(decoding: integerBytes, as: UTF8.self), radix: 10)!
            let resultingInt = baseInt * sign

            if isDate {
                return .date(resultingInt)
            } else {
                return .integer(resultingInt)
            }
        case .decimal:
            // This must be non-nil, otherwise we couldn't have flipped to the decimal type.
            let periodIndex = integerBytes.firstIndex(of: asciiPeriod)!
            let periodIndexDistance = integerBytes.distance(from: periodIndex, to: integerBytes.endIndex)
            if periodIndexDistance == 1 || periodIndexDistance > 4 {
                // Period may not be last, or have more than three characters after it.
                throw StructuredHeaderError.invalidIntegerOrDecimal
            }

            // Same notes here as above
            var decimal = PseudoDecimal(bytes: integerBytes)
            decimal.mantissa *= Int64(sign)
            return .decimal(decimal)
        }
    }

    private mutating func _parseAString() throws -> RFC9651BareItem {
        assert(self.underlyingData.first == asciiDquote)
        self.underlyingData.consumeFirst()

        // Ok, let's pause. Here we need to parse out a String and turn it into...well, into something.
        // It doesn't have to be a String now, but at some stage a user is going to want it to be a String,
        // so we need to include the idea that we'll have to manifest a String at some point.
        //
        // The wrinkle here is we have to deal with escapes. Two characters may appear escaped in strings:
        // dquote and backslash. Worse, _only_ those two may appear escaped: any other escape sequence is invalid.
        // This means the most naive algorithm, which also happens to be best for the cache and branch predictor
        // (just treat a string as a byte slice, walk forward until we find dquote, and slice it out) doesn't work.
        //
        // We can choose to do this _anyway_, by searching for the first unescaped dquote. But we have to remember
        // to handle the escaping at some point, and we also have to police character validity. Doing this later risks
        // that we'll have evicted these bytes from cache, forcing a cache miss to get them back. Not ideal.
        //
        // So we do a different thing. We walk the string twice: first to validate and find its length, and then the
        // second time to actually create the String. We can't do this in one step without risking gravely over-allocating
        // for the String, which would be sad, so we tolerate doing it twice. While we do it, we record whether the string
        // contains escapes. If it doesn't, we know that we can fall back to the optimised String construction with no branches,
        // making this fairly quick. If it does, well, we have branchy awkward code, but at least we have confidence that our
        // data is in cache.

        // First, walk 1: find the length, validate as we go, check for escapes.
        var escapes = 0
        var index = self.underlyingData.startIndex
        var endIndex = self.underlyingData.endIndex
        loop: while index < endIndex {
            let char = self.underlyingData[index]

            switch char {
            case asciiBackslash:
                self.underlyingData.formIndex(after: &index)
                if index == endIndex {
                    throw StructuredHeaderError.invalidString
                }
                let next = self.underlyingData[index]
                guard next == asciiDquote || next == asciiBackslash else {
                    throw StructuredHeaderError.invalidString
                }
                escapes += 1

            case asciiDquote:
                // Unquoted dquote, this is the end of the string.
                endIndex = index
                break loop
            case 0x00...0x1F, 0x7F...:
                // Forbidden bytes in string: string must be VCHAR and SP.
                throw StructuredHeaderError.invalidString
            default:
                // Allowed, unescape, uncontrol byte.
                ()
            }

            self.underlyingData.formIndex(after: &index)
        }

        // Oops, fell off the back of the string.
        if endIndex == self.underlyingData.endIndex {
            throw StructuredHeaderError.invalidString
        }
        let stringSlice = self.underlyingData[self.underlyingData.startIndex..<index]
        self.underlyingData.formIndex(after: &index)
        self.underlyingData = self.underlyingData[index...]

        // Ok, now we check: if we have encountered an escape, we have to fall back to the slow mode. If not,
        // we can initialize the string directly.
        if escapes == 0 {
            return .string(String(decoding: stringSlice, as: UTF8.self))
        } else {
            return .string(String.decodingEscapes(stringSlice, escapes: escapes))
        }
    }

    private mutating func _parseAByteSequence() throws -> RFC9651BareItem {
        assert(self.underlyingData.first == asciiColon)
        self.underlyingData.consumeFirst()

        var index = self.underlyingData.startIndex
        while index < self.underlyingData.endIndex {
            switch self.underlyingData[index] {
            case asciiColon:
                // Hey, this is the end! The base64 data is the data prior to here.
                let consumedSlice = self.underlyingData[..<index]

                // Skip the colon and consume it.
                self.underlyingData.formIndex(after: &index)
                self.underlyingData = self.underlyingData[index...]

                return .undecodedByteSequence(String(decoding: consumedSlice, as: UTF8.self))

            case asciiCapitals, asciiLowercases, asciiDigits, asciiPlus, asciiSlash, asciiEqual:
                // All valid characters for Base64 here.
                self.underlyingData.formIndex(after: &index)
            default:
                // Invalid character
                throw StructuredHeaderError.invalidByteSequence
            }
        }

        // Whoops, got to the end, invalid byte sequence.
        throw StructuredHeaderError.invalidByteSequence
    }

    private mutating func _parseABoolean() throws -> RFC9651BareItem {
        assert(self.underlyingData.first == asciiQuestionMark)
        self.underlyingData.consumeFirst()

        switch self.underlyingData.first {
        case asciiOne:
            self.underlyingData.consumeFirst()
            return true
        case asciiZero:
            self.underlyingData.consumeFirst()
            return false
        default:
            // Whoops!
            throw StructuredHeaderError.invalidBoolean
        }
    }

    private mutating func _parseAToken() throws -> RFC9651BareItem {
        assert(
            asciiCapitals.contains(self.underlyingData.first!) || asciiLowercases.contains(self.underlyingData.first!)
                || self.underlyingData.first! == asciiAsterisk
        )

        var index = self.underlyingData.startIndex
        loop: while index < self.underlyingData.endIndex {
            switch self.underlyingData[index] {
            // Valid token characters are RFC 7230 tchar, colon, and slash.
            // tchar is:
            //
            // tchar          = "!" / "#" / "$" / "%" / "&" / "'" / "*"
            //                / "+" / "-" / "." / "^" / "_" / "`" / "|" / "~"
            //                / DIGIT / ALPHA
            //
            // The following unfortunate case statement covers this. Tokens; not even once.
            case asciiExclamationMark, asciiOctothorpe, asciiDollar, asciiPercent,
                asciiAmpersand, asciiSquote, asciiAsterisk, asciiPlus, asciiDash,
                asciiPeriod, asciiCaret, asciiUnderscore, asciiBacktick, asciiPipe,
                asciiTilde, asciiDigits, asciiCapitals, asciiLowercases,
                asciiColon, asciiSlash:
                // Good, consume
                self.underlyingData.formIndex(after: &index)
            default:
                // Token complete
                break loop
            }
        }

        // Token is complete either when we stop getting valid token characters or when
        // we get to the end of the string.
        let tokenSlice = self.underlyingData[..<index]
        self.underlyingData = self.underlyingData[index...]
        return .token(String(decoding: tokenSlice, as: UTF8.self))
    }

    private mutating func _parseADate() throws -> RFC9651BareItem {
        assert(self.underlyingData.first == asciiAt)
        self.underlyingData.consumeFirst()
        return try self._parseAnIntegerOrDecimal(isDate: true)
    }

    private mutating func _parseADisplayString() throws -> RFC9651BareItem {
        assert(self.underlyingData.first == asciiPercent)
        self.underlyingData.consumeFirst()

        guard self.underlyingData.first == asciiDquote else {
            throw StructuredHeaderError.invalidDisplayString
        }

        self.underlyingData.consumeFirst()

        var byteArray = [UInt8]()

        while let char = self.underlyingData.first {
            self.underlyingData.consumeFirst()

            switch char {
            case 0x00...0x1F, 0x7F...:
                throw StructuredHeaderError.invalidDisplayString
            case asciiPercent:
                if self.underlyingData.count < 2 {
                    throw StructuredHeaderError.invalidDisplayString
                }

                let octetHex = EncodedHex(self.underlyingData.prefix(2))

                self.underlyingData = self.underlyingData.dropFirst(2)

                guard let octet = octetHex.decode() else {
                    throw StructuredHeaderError.invalidDisplayString
                }

                byteArray.append(octet)
            case asciiDquote:
                #if compiler(>=6.0)
                if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
                    let unicodeSequence = String(validating: byteArray, as: UTF8.self)

                    guard let unicodeSequence else {
                        throw StructuredHeaderError.invalidDisplayString
                    }

                    return .displayString(unicodeSequence)
                } else {
                    return try _decodeDisplayString(byteArray: &byteArray)
                }
                #else
                return try _decodeDisplayString(byteArray: &byteArray)
                #endif
            default:
                byteArray.append(char)
            }
        }

        // Fail parsing — reached the end of the string without finding a closing DQUOTE.
        throw StructuredHeaderError.invalidDisplayString
    }

    /// This method is called in environments where `String(validating:as:)` is unavailable. It uses
    /// `String(validatingUTF8:)` which requires `byteArray` to be null terminated. `String(validating:as:)`
    /// does not require that requirement. Therefore, it does not perform null checks, which makes it more optimal.
    private func _decodeDisplayString(byteArray: inout [UInt8]) throws -> RFC9651BareItem {
        // String(validatingUTF8:) requires byteArray to be null-terminated.
        byteArray.append(0)

        let unicodeSequence = byteArray.withUnsafeBytes {
            $0.withMemoryRebound(to: CChar.self) {
                // This force-unwrap is safe, as the buffer must successfully bind to CChar.
                String(validatingCString: $0.baseAddress!)
            }
        }

        guard let unicodeSequence else {
            throw StructuredHeaderError.invalidDisplayString
        }

        return .displayString(unicodeSequence)
    }

    private mutating func _parseParameters() throws -> OrderedMap<Key, RFC9651BareItem> {
        var parameters = OrderedMap<Key, RFC9651BareItem>()

        // We want to loop while we still have bytes _and_ while the first character is asciiSemicolon.
        // This covers both.
        while self.underlyingData.first == asciiSemicolon {
            // Consume the colon
            self.underlyingData.consumeFirst()
            self.underlyingData.stripLeadingSpaces()
            let paramName = try self._parseAKey()
            var paramValue: RFC9651BareItem = true

            if self.underlyingData.first == asciiEqual {
                self.underlyingData.consumeFirst()
                paramValue = try self._parseABareItem()
            }

            parameters[paramName] = paramValue
        }

        return parameters
    }

    private mutating func _parseAKey() throws -> Key {
        guard let first = self.underlyingData.first, asciiLowercases.contains(first) || first == asciiAsterisk else {
            throw StructuredHeaderError.invalidKey
        }

        let key = self.underlyingData.prefix(while: {
            switch $0 {
            case asciiLowercases, asciiDigits, asciiUnderscore, asciiDash, asciiPeriod, asciiAsterisk:
                return true
            default:
                return false
            }
        })
        self.underlyingData = self.underlyingData.dropFirst(key.count)
        return String(decoding: key, as: UTF8.self)
    }
}

private enum IntegerOrDecimal {
    case integer
    case decimal
}

extension RandomAccessCollection where Element == UInt8, SubSequence == Self {
    mutating func stripLeadingSpaces() {
        self = self.drop(while: { $0 == asciiSpace })
    }

    mutating func stripLeadingOWS() {
        self = self.drop(while: { $0 == asciiSpace || $0 == asciiTab })
    }

    mutating func consumeFirst() {
        self = self.dropFirst()
    }
}

extension String {
    // This is the slow path, so we never inline this.
    @inline(never)
    fileprivate static func decodingEscapes<Bytes: RandomAccessCollection>(_ bytes: Bytes, escapes: Int) -> String
    where Bytes.Element == UInt8 {
        // We assume the string is previously validated, so the escapes are easily removed. See the doc comment for
        // `StrippingStringEscapesCollection` for more details on what we're doing here.
        let unescapedBytes = StrippingStringEscapesCollection(bytes, escapes: escapes)
        if #available(macOS 10.16, macCatalyst 14.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            return String(unsafeUninitializedCapacity: unescapedBytes.count) { innerPtr in
                let (_, endIndex) = innerPtr.initialize(from: unescapedBytes)
                return endIndex
            }
        } else {
            return String(decoding: unescapedBytes, as: UTF8.self)
        }
    }
}

/// This helper struct is used to try to minimise the surface area of the unsafe string constructor.
///
/// We have a goal to create the String as cheaply as possible in the presence of escapes. Using the safe constructor will not
/// do that: if a non-contiguous collection is used to create a String directly, an intermediate Array will be used to flatten
/// the collection. As an escaped string is definitionally non-contiguous, we would hit that path, which is very sad.
/// Until this issue is fixed (https://bugs.swift.org/browse/SR-13111) we take a different approach: we use
/// `String.init(unsafeUninitializedCapacity:initializingWith)`. This is an unsafe function, so to reduce the unsafety as much
/// as possible we define this safe wrapping Collection and then use `copyBytes` to implement the initialization.
private struct StrippingStringEscapesCollection<BaseCollection: RandomAccessCollection>
where BaseCollection.Element == UInt8 {
    private var base: BaseCollection
    private var escapes: UInt

    init(_ base: BaseCollection, escapes: Int) {
        self.base = base
        self.escapes = UInt(escapes)
    }
}

extension StrippingStringEscapesCollection: Collection {
    fileprivate struct Index {
        fileprivate var _baseIndex: BaseCollection.Index

        fileprivate init(baseIndex: BaseCollection.Index) {
            self._baseIndex = baseIndex
        }
    }

    // This is an extremely important customisation point! Our base collection is random access,
    // so we know that on the base this is O(1), but as this collection is _not_ random access here
    // it's O(n).
    fileprivate var count: Int {
        self.base.count - Int(self.escapes)
    }

    fileprivate var startIndex: Index {
        // Tricky note here, but start index _might_ be an ascii backslash, which we have to skip.
        Index(baseIndex: self.unescapedIndex(self.base.startIndex))
    }

    fileprivate var endIndex: Index {
        Index(baseIndex: self.base.endIndex)
    }

    fileprivate func index(after i: Index) -> Index {
        let next = self.base.index(after: i._baseIndex)
        return Index(baseIndex: self.unescapedIndex(next))
    }

    fileprivate subscript(index: Index) -> UInt8 {
        self.base[index._baseIndex]
    }

    private func unescapedIndex(_ baseIndex: BaseCollection.Index) -> BaseCollection.Index {
        if baseIndex == self.base.endIndex {
            return baseIndex
        }

        if self.base[baseIndex] == asciiBackslash {
            return self.base.index(after: baseIndex)
        } else {
            return baseIndex
        }
    }
}

extension StrippingStringEscapesCollection.Index: Equatable {}

extension StrippingStringEscapesCollection.Index: Comparable {
    fileprivate static func < (lhs: Self, rhs: Self) -> Bool {
        lhs._baseIndex < rhs._baseIndex
    }
}

/// `EncodedHex` represents a (possibly invalid) hex value in UTF8.
struct EncodedHex {
    private(set) var firstChar: UInt8
    private(set) var secondChar: UInt8

    init<Bytes: RandomAccessCollection>(_ bytes: Bytes) where Bytes.Element == UInt8 {
        precondition(bytes.count == 2)
        self.firstChar = bytes[bytes.startIndex]
        self.secondChar = bytes[bytes.index(after: bytes.startIndex)]
    }

    /// Validates and converts `EncodedHex` to a base 10 UInt8.
    ///
    /// If `EncodedHex` does not represent a valid hex value, the result of this method is nil.
    fileprivate func decode() -> UInt8? {
        guard
            let firstCharAsInteger = self.htoi(self.firstChar),
            let secondCharAsInteger = self.htoi(self.secondChar)
        else { return nil }

        return (firstCharAsInteger << 4) + secondCharAsInteger
    }

    /// Converts a hex character given in UTF8 to its integer value.
    private func htoi(_ asciiChar: UInt8) -> UInt8? {
        switch asciiChar {
        case asciiZero...asciiNine:
            return asciiChar - asciiZero
        case asciiLowerA...asciiLowerF:
            return asciiChar - asciiLowerA + 10
        default:
            return nil
        }
    }
}
