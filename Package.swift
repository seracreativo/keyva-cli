// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyvaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // Library for shared code (used by app and CLI)
        .library(
            name: "KeyvaCore",
            targets: ["KeyvaCore"]
        ),
        // CLI executable
        .executable(
            name: "keyva",
            targets: ["keyvacli"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // Core library with Models and Services
        .target(
            name: "KeyvaCore",
            dependencies: [],
            path: "Sources/KeyvaCore"
        ),
        // CLI tool
        .executableTarget(
            name: "keyvacli",
            dependencies: [
                "KeyvaCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/keyvacli"
        ),
    ]
)
