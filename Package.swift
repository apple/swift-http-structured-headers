// swift-tools-version:5.2

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
