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
    dependencies: [],
    targets: [
        .target(
            name: "QCP",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "QCPTests",
            dependencies: ["QCP"],
            path: "Tests"
        ),
    ]
)
