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

// MARK: - StructuredHeaderError

/// Errors that may be encountered when working with structured headers.
public struct StructuredHeaderError: Error, Sendable {
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
        case invalidDate
        case invalidDisplayString
        case invalidList
        case invalidDictionary
        case missingKey
        case invalidTypeForItem
        case integerOutOfRange
        case indexOutOfRange
    }

    private var base: _BaseError

    private init(_ base: _BaseError) {
        self.base = base
    }
}

extension StructuredHeaderError {
    public static let invalidTrailingBytes = StructuredHeaderError(.invalidTrailingBytes)
    public static let invalidInnerList = StructuredHeaderError(.invalidInnerList)
    public static let invalidItem = StructuredHeaderError(.invalidItem)
    public static let invalidKey = StructuredHeaderError(.invalidKey)
    public static let invalidIntegerOrDecimal = StructuredHeaderError(.invalidIntegerOrDecimal)
    public static let invalidString = StructuredHeaderError(.invalidString)
    public static let invalidByteSequence = StructuredHeaderError(.invalidByteSequence)
    public static let invalidBoolean = StructuredHeaderError(.invalidBoolean)
    public static let invalidToken = StructuredHeaderError(.invalidToken)
    public static let invalidDate = StructuredHeaderError(.invalidDate)
    public static let invalidDisplayString = StructuredHeaderError(.invalidDisplayString)
    public static let invalidList = StructuredHeaderError(.invalidList)
    public static let invalidDictionary = StructuredHeaderError(.invalidDictionary)
    public static let missingKey = StructuredHeaderError(.missingKey)
    public static let invalidTypeForItem = StructuredHeaderError(.invalidTypeForItem)
    public static let integerOutOfRange = StructuredHeaderError(.integerOutOfRange)
    public static let indexOutOfRange = StructuredHeaderError(.indexOutOfRange)
}

extension StructuredHeaderError: Hashable {}

extension StructuredHeaderError: CustomStringConvertible {
    public var description: String {
        String(describing: self.base)
    }
}
