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
import RawStructuredFieldValues

struct _StructuredHeaderCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }

    init<Key: CodingKey>(_ key: Key, keyDecodingStrategy: StructuredFieldValueDecoder.KeyDecodingStrategy?) {
        switch keyDecodingStrategy {
        case .none:
            self.stringValue = key.stringValue
        case .some(.lowercase):
            self.stringValue = key.stringValue.lowercased()
        default:
            preconditionFailure("Invalid key decoding strategy")
        }

        self.intValue = key.intValue
    }
}
