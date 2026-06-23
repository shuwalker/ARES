// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ARES",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .executable(name: "ARES", targets: ["ARES"])
    ],
    targets: [
        .executableTarget(
            name: "ARES",
            path: "Sources/ARES",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
