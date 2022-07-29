// swift-tools-version:5.5
//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the SwiftNIO project authors
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
    name: "swift-http-structured-headers",
    products: [
        .library(
            name: "StructuredFieldValues",
            targets: ["StructuredFieldValues"]
        ),
        .library(
            name: "RawStructuredFieldValues",
            targets: ["RawStructuredFieldValues"]
        ),
    ],
    targets: [
        .target(
            name: "RawStructuredFieldValues",
            dependencies: []
        ),
        .target(
            name: "StructuredFieldValues",
            dependencies: ["RawStructuredFieldValues"]
        ),
        .executableTarget(
            name: "sh-parser",
            dependencies: ["RawStructuredFieldValues"]
        ),
        .testTarget(
            name: "StructuredFieldValuesTests",
            dependencies: ["RawStructuredFieldValues", "StructuredFieldValues"]
        ),
    ]
)
