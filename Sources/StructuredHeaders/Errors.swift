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

public struct StructuredHeaderParsingError: Error {
    private enum _BaseError: Hashable {
        case invalidTrailingBytes
        case invalidInnerList
        case invalidItem
        case invalidKey
        case invalidIntegerOrDecimal
        case invalidString
        case invalidByteSequence
        case invalidBoolean
        case invalidToken
        case invalidList
        case invalidDictionary
    }

    private var base: _BaseError

    private init(_ base: _BaseError) {
        self.base = base
    }
}

extension StructuredHeaderParsingError {
    public static let invalidTrailingBytes = StructuredHeaderParsingError(.invalidTrailingBytes)
    public static let invalidInnerList = StructuredHeaderParsingError(.invalidInnerList)
    public static let invalidItem = StructuredHeaderParsingError(.invalidItem)
    public static let invalidKey = StructuredHeaderParsingError(.invalidKey)
    public static let invalidIntegerOrDecimal = StructuredHeaderParsingError(.invalidIntegerOrDecimal)
    public static let invalidString = StructuredHeaderParsingError(.invalidString)
    public static let invalidByteSequence = StructuredHeaderParsingError(.invalidByteSequence)
    public static let invalidBoolean = StructuredHeaderParsingError(.invalidBoolean)
    public static let invalidToken = StructuredHeaderParsingError(.invalidToken)
    public static let invalidList = StructuredHeaderParsingError(.invalidList)
    public static let invalidDictionary = StructuredHeaderParsingError(.invalidDictionary)
}

extension StructuredHeaderParsingError: Hashable { }

extension StructuredHeaderParsingError: CustomStringConvertible {
    public var description: String {
        return String(describing: self.base)
    }
}
