// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "iCloudBridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "iCloudBridgeCore", targets: ["iCloudBridgeCore"]),
        .executable(name: "iCloudBridge", targets: ["iCloudBridge"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/Cocoanetics/SwiftMCP.git",
            exact: "1.10.4"
        )
    ],
    targets: [
        .target(
            name: "iCloudBridgeCore",
            dependencies: [
                .product(name: "SwiftMCP", package: "SwiftMCP")
            ]
        ),
        .executableTarget(
            name: "iCloudBridge",
            dependencies: ["iCloudBridgeCore"]
        ),
        .testTarget(
            name: "iCloudBridgeCoreTests",
            dependencies: ["iCloudBridgeCore"]
        )
    ]
)
