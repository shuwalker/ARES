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
    ],
    dependencies: [
        .package(path: "ARES-Mac_os/Vendor/SwiftTerm"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "ARESCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "ARES-Mac_os/Sources/ARESCore"
        ),
        .executableTarget(
            name: "ARES",
            dependencies: [
                "ARESCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "ARES-Mac_os/Sources/ARES",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ARESTests",
            dependencies: ["ARESCore", "ARES"],
            path: "ARES-Mac_os/Tests/ARESTests"
        ),
    ]
)
