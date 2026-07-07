// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ARES",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "ARESCore", targets: ["ARESCore"]),
        .executable(name: "ARES", targets: ["ARES"]),
        .executable(name: "ARESLegacy", targets: ["ARESLegacy"]),
        .executable(name: "arestask", targets: ["AresTaskCLI"])
    ],
    dependencies: [
        .package(path: "ARES-Modules"),
        .package(path: "ARES-Desktop/Vendor/SwiftTerm"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.19.0")
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
                .product(name: "MLX", package: "mlx-swift")
            ],
            path: "ARES-Desktop/Sources/ARES",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "ARESLegacy",
            dependencies: [.product(name: "ARESModules", package: "ARES-Modules")],
            path: "Sources/ARES",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "AresTaskCLI",
            dependencies: [.product(name: "ARESModules", package: "ARES-Modules")],
            path: "Sources/AresTaskCLI"
        ),
        .testTarget(
            name: "ARESTests",
            dependencies: ["ARESCore", "ARES"],
            path: "ARES-Desktop/Tests/ARESTests"
        )
    ]
)
