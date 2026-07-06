// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ARESModules",
    platforms: [.macOS(.v14), .iOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "ARESModules", targets: ["ARESModules"]),
    ],
    targets: [
        .target(
            name: "ARESModules",
            path: "Sources/ARESModules",
            exclude: ["Extractions"]
        ),
    ]
)
