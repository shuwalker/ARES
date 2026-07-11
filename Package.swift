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
        .package(path: "ARES-Desktop/Vendor/SwiftTerm"),
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
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "ARES-Desktop/Sources/ARES",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ARESTests",
            dependencies: ["ARESCore", "ARES"],
            path: "ARES-Desktop/Tests/ARESTests"
        ),
    ]
)
