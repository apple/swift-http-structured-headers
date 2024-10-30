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
import Foundation

private let base32DecoderAlphabet: [UnicodeScalar: UInt64] = [
    "A": 0, "B": 1, "C": 2, "D": 3, "E": 4, "F": 5, "G": 6, "H": 7,
    "I": 8, "J": 9, "K": 10, "L": 11, "M": 12, "N": 13, "O": 14, "P": 15,
    "Q": 16, "R": 17, "S": 18, "T": 19, "U": 20, "V": 21, "W": 22, "X": 23,
    "Y": 24, "Z": 25, "2": 26, "3": 27, "4": 28, "5": 29, "6": 30, "7": 31,
]

extension Data {
    init(base32Encoded data: Data) {
        self = Data()

        for start in stride(from: data.startIndex, to: data.endIndex, by: 8) {
            let bytes = data[start..<(start + 8)]
            precondition(bytes.count == 8)
            var seenEquals = 0

            var rawValue = UInt64(0)
            for character in bytes {
                // Each character encodes 5 bits. The equals pad with zeros _on the right_, so we must shift for every
                // character we see.
                rawValue <<= 5

                if character == UInt8(ascii: "=") {
                    seenEquals += 1
                    continue
                }

                let underlyingValue = base32DecoderAlphabet[UnicodeScalar(character)]!
                rawValue |= underlyingValue
            }

            let ignoredBytes: Int
            switch seenEquals {
            case 0:
                ignoredBytes = 0
            case 1:
                ignoredBytes = 1
            case 3:
                ignoredBytes = 2
            case 4:
                ignoredBytes = 3
            case 6:
                ignoredBytes = 4
            default:
                fatalError("Impossible equals count: \(seenEquals)")
            }

            for byteNumber in (ignoredBytes..<5).reversed() {
                let byte = UInt8(truncatingIfNeeded: rawValue >> (byteNumber * 8))
                self.append(byte)
            }
        }
    }
}
