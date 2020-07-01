// swift-tools-version:5.2
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
import PackageDescription

let package = Package(
    name: "swift-structured-headers",
    products: [
        .library(
            name: "StructuredHeaders",
            targets: ["StructuredHeaders"]),
    ],
    targets: [
        .target(
            name: "StructuredHeaders",
            dependencies: []),
        .testTarget(
            name: "StructuredHeadersTests",
            dependencies: ["StructuredHeaders"]),
    ]
)
