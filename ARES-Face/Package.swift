// swift-tools-version: 6.0
// Package.swift — ARES Face App
// Build with: swift build
// Run with: swift run ARES-Face
// Requires macOS 15+ (Sequoia+) for RealityKit CustomMaterial + withMutableUniforms

import PackageDescription

let package = Package(
    name: "ARES-Face",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "ARES-Face",
            targets: ["ARES-Face"]
        ),
        .executable(
            name: "metal-diagnostics",
            targets: ["metal-diagnostics"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ARES-Face",
            path: "ARES-Face",
            resources: [
                .process("Shaders")
            ]
        ),
        .executableTarget(
            name: "metal-diagnostics",
            dependencies: [],
            path: "Diagnostics",
            resources: [
                .process("Shaders")
            ]
        ),
    ]
)
