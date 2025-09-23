// swift-tools-version:6.0
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

let strictConcurrencyDevelopment = false

let strictConcurrencySettings: [SwiftSetting] = {
    var initialSettings: [SwiftSetting] = []

    if strictConcurrencyDevelopment {
        // -warnings-as-errors here is a workaround so that IDE-based development can
        // get tripped up on -require-explicit-sendable.
        initialSettings.append(.unsafeFlags(["-require-explicit-sendable", "-warnings-as-errors"]))
    }

    return initialSettings
}()

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
            dependencies: [],
            swiftSettings: strictConcurrencySettings
        ),
        .target(
            name: "StructuredFieldValues",
            dependencies: ["RawStructuredFieldValues"],
            swiftSettings: strictConcurrencySettings
        ),
        .executableTarget(
            name: "sh-parser",
            dependencies: ["RawStructuredFieldValues"],
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "StructuredFieldValuesTests",
            dependencies: ["RawStructuredFieldValues", "StructuredFieldValues"],
            swiftSettings: strictConcurrencySettings
        ),
    ]
)

// ---    STANDARD CROSS-REPO SETTINGS DO NOT EDIT   --- //
for target in package.targets {
    switch target.type {
    case .regular, .test, .executable:
        var settings = target.swiftSettings ?? []
        // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
        settings.append(.enableUpcomingFeature("MemberImportVisibility"))
        target.swiftSettings = settings
    case .macro, .plugin, .system, .binary:
        ()  // not applicable
    @unknown default:
        ()  // we don't know what to do here, do nothing
    }
}
// --- END: STANDARD CROSS-REPO SETTINGS DO NOT EDIT --- //
