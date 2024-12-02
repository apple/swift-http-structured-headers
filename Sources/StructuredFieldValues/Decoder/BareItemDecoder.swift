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

struct BareItemDecoder {
    private var item: RFC9651BareItem

    private var _codingPath: [_StructuredHeaderCodingKey]

    init(_ item: RFC9651BareItem, codingPath: [_StructuredHeaderCodingKey]) {
        self.item = item
        self._codingPath = codingPath
    }
}

extension BareItemDecoder: SingleValueDecodingContainer {
    var codingPath: [CodingKey] {
        self._codingPath as [CodingKey]
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        try self._decodeFixedWidthInteger(type)
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        try self._decodeFixedWidthInteger(type)
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        try self._decodeFixedWidthInteger(type)
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        try self._decodeFixedWidthInteger(type)
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        try self._decodeFixedWidthInteger(type)
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        try self._decodeFixedWidthInteger(type)
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        try self._decodeFixedWidthInteger(type)
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        try self._decodeFixedWidthInteger(type)
    }

    #if compiler(>=6.0)
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func decode(_ type: UInt128.Type) throws -> UInt128 {
        try self._decodeFixedWidthInteger(type)
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    func decode(_ type: Int128.Type) throws -> Int128 {
        try self._decodeFixedWidthInteger(type)
    }
    #endif

    func decode(_ type: UInt.Type) throws -> UInt {
        try self._decodeFixedWidthInteger(type)
    }

    func decode(_ type: Int.Type) throws -> Int {
        try self._decodeFixedWidthInteger(type)
    }

    func decode(_ type: Float.Type) throws -> Float {
        try self._decodeBinaryFloatingPoint(type)
    }

    func decode(_ type: Double.Type) throws -> Double {
        try self._decodeBinaryFloatingPoint(type)
    }

    func decode(_: String.Type) throws -> String {
        switch self.item {
        case .string(let string):
            return string
        case .token(let token):
            return token
        default:
            throw StructuredHeaderError.invalidTypeForItem
        }
    }

    func decode(_: Bool.Type) throws -> Bool {
        guard case .bool(let bool) = self.item else {
            throw StructuredHeaderError.invalidTypeForItem
        }

        return bool
    }

    func decode(_: Data.Type) throws -> Data {
        guard case .undecodedByteSequence(let data) = self.item else {
            throw StructuredHeaderError.invalidTypeForItem
        }

        guard let decoded = Data(base64Encoded: data) else {
            throw StructuredHeaderError.invalidByteSequence
        }

        return decoded
    }

    func decode(_: Decimal.Type) throws -> Decimal {
        guard case .decimal(let pseudoDecimal) = self.item else {
            throw StructuredHeaderError.invalidTypeForItem
        }

        return Decimal(
            sign: pseudoDecimal.mantissa > 0 ? .plus : .minus,
            exponent: Int(pseudoDecimal.exponent),
            significand: Decimal(pseudoDecimal.mantissa.magnitude)
        )
    }

    func decode(_: Date.Type) throws -> Date {
        guard case .date(let date) = self.item else {
            throw StructuredHeaderError.invalidTypeForItem
        }

        return Date(timeIntervalSince1970: Double(date))
    }

    func decode(_: DisplayString.Type) throws -> DisplayString {
        guard case .displayString(let string) = self.item else {
            throw StructuredHeaderError.invalidTypeForItem
        }

        return DisplayString(rawValue: string)
    }

    func decodeNil() -> Bool {
        // Items are never nil.
        false
    }

    func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
        switch type {
        case is UInt8.Type:
            return try self.decode(UInt8.self) as! T
        case is Int8.Type:
            return try self.decode(Int8.self) as! T
        case is UInt16.Type:
            return try self.decode(UInt16.self) as! T
        case is Int16.Type:
            return try self.decode(Int16.self) as! T
        case is UInt32.Type:
            return try self.decode(UInt32.self) as! T
        case is Int32.Type:
            return try self.decode(Int32.self) as! T
        case is UInt64.Type:
            return try self.decode(UInt64.self) as! T
        case is Int64.Type:
            return try self.decode(Int64.self) as! T
        case is UInt.Type:
            return try self.decode(UInt.self) as! T
        case is Int.Type:
            return try self.decode(Int.self) as! T
        case is Float.Type:
            return try self.decode(Float.self) as! T
        case is Double.Type:
            return try self.decode(Double.self) as! T
        case is String.Type:
            return try self.decode(String.self) as! T
        case is Bool.Type:
            return try self.decode(Bool.self) as! T
        case is Data.Type:
            return try self.decode(Data.self) as! T
        case is Decimal.Type:
            return try self.decode(Decimal.self) as! T
        case is Date.Type:
            return try self.decode(Date.self) as! T
        case is DisplayString.Type:
            return try self.decode(DisplayString.self) as! T
        default:
            throw StructuredHeaderError.invalidTypeForItem
        }
    }

    private func _decodeBinaryFloatingPoint<T: BinaryFloatingPoint>(_: T.Type) throws -> T {
        guard case .decimal(let decimal) = self.item else {
            throw StructuredHeaderError.invalidTypeForItem
        }

        // Going via Double is a bit sad. Swift Numerics would help here.
        return T(Double(decimal))
    }

    private func _decodeFixedWidthInteger<T: FixedWidthInteger>(_: T.Type) throws -> T {
        guard case .integer(let int) = self.item else {
            throw StructuredHeaderError.invalidTypeForItem
        }

        guard let result = T(exactly: int) else {
            throw StructuredHeaderError.integerOutOfRange
        }

        return result
    }
}
