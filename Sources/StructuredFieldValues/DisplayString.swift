//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020-2024 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// A type that represents the Display String Structured Type.
public struct DisplayString: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public typealias RawValue = String
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
