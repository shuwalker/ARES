// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARES",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ARES", targets: ["ARES"])],
    targets: [
        .executableTarget(name: "ARES", path: "Sources")
    ]
)
