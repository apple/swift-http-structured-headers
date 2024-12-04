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

/// A `StructuredFieldValue` is a `Codable` representation of a HTTP Structured
/// Header Field.
///
/// This protocol is a helper protocol that refines `Codable` to indicate what kind
/// of header field a given field uses.
public protocol StructuredFieldValue: Codable {
    static var structuredFieldType: StructuredFieldType { get }
}

/// The kinds of header fields used in HTTP Structured Headers.
public enum StructuredFieldType: Sendable {
    /// An item field consists of a single item, optionally with parameters.
    case item

    /// A list field consists of a list made up of inner lists or items.
    case list

    /// A dictionary field is an ordered collection of key-value pairs.
    case dictionary
}
