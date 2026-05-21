// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ARES",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ARES",
            targets: ["ARES"]
        )
    ],
    dependencies: [
        .package(path: "Vendor/SwiftTerm")
    ],
    targets: [
        .executableTarget(
            name: "ARES",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/HermesDesktop",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // Swift 5 language mode while codebase is audited for Swift 6 concurrency.
                // Remove this line once all Sendable / actor-isolation warnings are resolved.
                .swiftLanguageVersion(.v5)
            ]
        ),
        .testTarget(
            name: "ARESTests",
            dependencies: ["ARES"],
            path: "Tests/HermesDesktopTests"
        )
    ]
)
