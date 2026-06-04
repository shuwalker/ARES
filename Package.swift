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
        .package(path: "ARES-Desktop/Vendor/SwiftTerm"),
        .package(path: "ARES-Desktop/Vendor/SAM")
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
            path: "ARES-Desktop/Sources/ARES",
            exclude: [],
            sources: nil,
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ARESTests",
            dependencies: ["ARES"],
            path: "ARES-Desktop/Tests/ARESTests"
        )
    ]
)
