// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ARES",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "ARESCore",
            targets: ["ARESCore"]
        ),
        .executable(
            name: "ARES",
            targets: ["ARES"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.13.0")
    ],
    targets: [
        .target(
            name: "ARESCore",
            dependencies: [],
            path: "ARES-Desktop/Sources/ARESCore"
        ),
        .executableTarget(
            name: "ARES",
            dependencies: [
                "ARESCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "ARES-Desktop/Sources/ARES",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ARESTests",
            dependencies: ["ARES", "ARESCore"],
            path: "ARES-Desktop/Tests/ARESTests"
        )
    ]
)
