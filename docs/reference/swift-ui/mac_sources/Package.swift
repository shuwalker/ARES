// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARES",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "ARES",
            path: "Sources/ARES-Mac"
        ),
        .testTarget(
            name: "ARESTests",
            dependencies: ["ARES"],
            path: "Tests/ARES-MacTests"
        )
    ]
)
