// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ARES",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "ARESCore", targets: ["ARESCore"]),
        .executable(name: "ARES", targets: ["ARES"]),
        .executable(name: "ARESNativeMCP", targets: ["ARESNativeMCP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
    ],
    targets: [
        .target(
            name: "ARESCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "ARES-Mac_os/Sources/ARESCore"
        ),
        .executableTarget(
            name: "ARES",
            dependencies: [
                "ARESCore",
            ],
            path: "ARES-Mac_os/Sources/ARES",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "ARESNativeMCP",
            dependencies: ["ARESCore"],
            path: "ARES-Mac_os/Sources/ARESNativeMCP"
        ),
        .testTarget(
            name: "ARESTests",
            dependencies: ["ARESCore", "ARES"],
            path: "ARES-Mac_os/Tests/ARESTests"
        ),
    ]
)
