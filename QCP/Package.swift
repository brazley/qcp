// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QCP",
    platforms: [
            .iOS(.v17),
            .macOS(.v14)
        ],
    products: [
        .library(
            name: "QCP",
            targets: ["QCP"]),
    ],
    dependencies: [
        // Dependencies will go here when we need them
    ],
    targets: [
        .target(
            name: "QCP",
            dependencies: []),
        .testTarget(
            name: "QCPTests",
            dependencies: ["QCP"]),
    ]
)
