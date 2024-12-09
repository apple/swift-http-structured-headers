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
public struct DisplayString: Codable, Equatable {
    /// The value of this Display String.
    public private(set) var description: String

    /// Initializes a new Display String.
    ///
    /// - parameters:
    ///   - description: The value of this Display String.
    public init(_ description: String) {
        self.description = description
    }
}
