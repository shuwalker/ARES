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
        .package(path: "Vendor/SwiftTerm"),
        .package(path: "Vendor/SAM")
    ],
    targets: [
        .executableTarget(
            name: "ARES",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "UserInterface", package: "SAM"),
                .product(name: "APIFramework", package: "SAM"),
                .product(name: "ConfigurationSystem", package: "SAM"),
                .product(name: "ConversationEngine", package: "SAM")
            ],
            path: "Sources/ARES",
            exclude: [],
            sources: nil,
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ARESTests",
            dependencies: ["ARES"],
            path: "Tests/ARESTests"
        )
    ]
)
