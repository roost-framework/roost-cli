// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "roost-cli",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "roost", targets: ["RoostCLI"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.2.0"
        ),
        .package(
            url: "https://github.com/tuist/Noora",
            .upToNextMajor(from: "0.15.0")
        ),
    ],
    targets: [
        .executableTarget(
            name: "RoostCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Noora", package: "Noora"),
            ]
        ),
        .testTarget(name: "RoostCLITests", dependencies: ["RoostCLI"]),
    ]
)
