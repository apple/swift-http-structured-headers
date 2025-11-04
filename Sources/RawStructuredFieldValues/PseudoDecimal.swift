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
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#else
#error("Unsupported OS")
#endif

/// A pseudo-representation of a decimal number.
///
/// The goal of this type is to remove a dependency on Foundation. As Structured Headers require only a very simple
/// conception of a decimal, there is no need to bring in the entire Foundation dependency: it's sufficient to define
/// a trivial type to represent the _idea_ of a decimal number. We don't have any requirement to do math on this type:
/// we just need to be able to use the type to store the fixed point representation of the value.
///
/// For ease of conversion to _actual_ decimal types, we use a mantissa/exponent/sign representation much like other
/// types would. Note that this is a base 10 exponent, not a base 2 exponent: the exponent multiplies by 10, not 2. We also
/// encode the sign bit implicitly in the sign bit of the mantissa.
///
/// The range of this type is from -999,999,999,999.999 to 999,999,999,999.999. This means the maximum value of the significand
/// is 999,999,999,999,999. The exponent ranges from -3 to 0. Additionally, there may be no more than 12 decimal digits before
/// the decimal place, so while the maximum value of the significand is 999,999,999,999,999, that is only acceptable if the
/// exponent is -3.
public struct PseudoDecimal: Hashable, Sendable {
    private var _mantissa: Int64

    private var _exponent: Int8

    public var mantissa: Int64 {
        get {
            self._mantissa
        }
        set {
            Self.fatalValidate(mantissa: newValue, exponent: self._exponent)
            self._mantissa = newValue
        }
    }

    public var exponent: Int8 {
        get {
            self._exponent
        }
        set {
            Self.fatalValidate(mantissa: self._mantissa, exponent: newValue)
            self._exponent = newValue
        }
    }

    public init(mantissa: Int, exponent: Int) {
        self._mantissa = Int64(mantissa)
        self._exponent = Int8(exponent)
        Self.fatalValidate(mantissa: self._mantissa, exponent: self._exponent)
    }

    internal init<Bytes: RandomAccessCollection>(bytes: Bytes) where Bytes.Element == UInt8 {
        let elements = bytes.split(separator: asciiPeriod, maxSplits: 1)
        // Precondition is safe, this can only be called from the parser which has already validated the formatting.
        precondition(elements.count == 2)

        var nonSignBytes = bytes.count
        var sign = Int64(1)
        if bytes.first == asciiDash {
            sign = -1
            nonSignBytes &-= 1
        }

        var mantissa = Int64(0)
        var periodOffset = 0
        for (offset, element) in bytes.enumerated() {
            if element == asciiPeriod {
                periodOffset = offset
                continue
            }

            let integerValue = element - asciiZero
            assert(integerValue < 10 && integerValue >= 0)

            mantissa *= 10
            mantissa += Int64(integerValue)
        }

        self._mantissa = mantissa * sign

        // Check where the period was in relation to the rest of the string. We can have anywhere between
        // 1 and 3 digits after the period. Note that if the period was last, offset == nonSignBytes - 1, so
        // the actual values here are 2 to 4.
        switch nonSignBytes - periodOffset {
        case 2:
            self._exponent = -1
        case 3:
            self._exponent = -2
        case 4:
            self._exponent = -3
        default:
            preconditionFailure("Unexpected value of offset: have \(nonSignBytes) bytes and offset \(periodOffset)")
        }
    }

    private static func validate(mantissa: Int64, exponent: Int8) throws {
        // We compare against our upper and lower bounds. The maximum allowable magnitude of the mantissa is contingent
        // on the exponent.
        switch exponent {
        case 0 where mantissa.magnitude <= 999_999_999_999,
            -1 where mantissa.magnitude <= 9_999_999_999_999,
            -2 where mantissa.magnitude <= 99_999_999_999_999,
            -3 where mantissa.magnitude <= 999_999_999_999_999:
            // All acceptable
            ()
        default:
            throw StructuredHeaderError.invalidIntegerOrDecimal
        }
    }

    private static func fatalValidate(mantissa: Int64, exponent: Int8) {
        do {
            try Self.validate(mantissa: mantissa, exponent: exponent)
        } catch {
            preconditionFailure(
                "Invalid value for structured header decimal: mantissa \(mantissa) exponent \(exponent)"
            )
        }
    }

    fileprivate mutating func canonicalise() {
        // This cannonicalises the decimal into a standard format suitable for direct serialisation.
        //
        // Structured headers prefers decimals to be serialized with no leading or trailing zeros. Leading zeros
        // are easily avoided, but trailing zeros are a function of the exponent. As we must have at least one
        // digit after the decimal place, exponent zero is not suitable, so if that's our current exponent we
        // will arrange to have exponent -1. If the exponent is -1, we'll leave it alone. For -3 and -2 exponents
        // we'll try to cascade them down toward exponent -1 if we can divide the mantissa by 10 evenly, as that will
        // eliminate trailing zeros after the decimal place.
        switch self._exponent {
        case 0:
            self._mantissa *= 10
            self._exponent = -1
        case -3 where self._mantissa % 10 == 0:
            self._mantissa /= 10
            self._exponent &+= 1
            fallthrough
        case -2:
            if self._mantissa % 10 == 0 {
                self._mantissa /= 10
                self._exponent &+= 1
            }
        default:
            // These other cases don't require any work.
            ()
        }
    }
}

extension PseudoDecimal: ExpressibleByFloatLiteral {
    public init(_ value: Double) throws {
        // This is kinda dumb, but it's basically good enough: we multiply by 1000 and then round that type
        // to an integer.
        var multiplied = value * 1000
        multiplied.round(.toNearestOrEven)
        let mantissa = Int64(exactly: multiplied)!
        self._mantissa = mantissa
        self._exponent = -3
        try Self.validate(mantissa: self._mantissa, exponent: self._exponent)
    }

    public init(floatLiteral value: Double) {
        do {
            try self.init(value)
        } catch {
            preconditionFailure("Invalid value for structured header decimal: \(value)")
        }
    }
}

extension String {
    public init(_ decimal: PseudoDecimal) {
        var local = decimal
        local.canonicalise()

        // First, serialize the mantissa. We do this with a magnitude because we add a sign later.
        var string = String(local.mantissa.magnitude, radix: 10)

        // Then, based on the exponent, we insert a period. Turns out the offset for
        // where we want to insert this character is exactly the exponent.
        // Before we do this, quick check: we may not even have that many digits! If we don't,
        // we need to pad with leading zeros until we do.
        let neededPadding = Int(local.exponent.magnitude) - string.count
        if neededPadding > 0 {
            string = String(repeating: "0", count: neededPadding) + string
        }

        let periodIndex = string.index(string.endIndex, offsetBy: Int(local.exponent))
        let needLeadingZero = periodIndex == string.startIndex
        string.insert(".", at: periodIndex)

        // One check: did we insert the period at the front? If we did, add a leading zero. Note
        // that the above insert invalidated the indices so we must ask for the new start index.
        if needLeadingZero {
            string.insert("0", at: string.startIndex)
        }
        if local.mantissa < 0 {
            string.insert("-", at: string.startIndex)
        }
        self = string
    }
}

// Swift Numerics would let us do this for all the floating point types.
extension Double {
    public init(_ pseudoDecimal: PseudoDecimal) {
        self = Double(pseudoDecimal.mantissa) * pow(10, Double(pseudoDecimal.exponent))
    }
}
