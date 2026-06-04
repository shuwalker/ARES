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
        // SAM — local path dependency
        // Development: reference copy at ~/Desktop/reference/SAM
        // Production: switch to Git URL dependency once SAM publishes version tags
        .package(path: "../SAM"),
        // SwiftTerm — local path dependency  
        // Reference copy at ~/Desktop/reference/SwiftTerm
        // Symlink or copy to Vendor/SwiftTerm for builds
        .package(path: "Vendor/SwiftTerm")
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