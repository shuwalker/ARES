// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ARES",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .executable(name: "ARES", targets: ["ARES"]),
        .executable(name: "arestask", targets: ["AresTaskCLI"])
    ],
    dependencies: [
        .package(path: "ARES-Modules")
    ],
    targets: [
        .executableTarget(
            name: "ARES",
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
        )
    ]
)
