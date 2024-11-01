// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MADNetworking",
    platforms: [
        .macOS(.v10_14),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MADNetworking",
            targets: ["MADNetworking"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Pulse", from: "5.1.2")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MADNetworking",
            dependencies: [
                .product(name: "Pulse", package: "Pulse"),
            ]
        ),
        .testTarget(
            name: "MADNetworkingTests",
            dependencies: ["MADNetworking"]),
    ]
)
