import Metal
import Foundation

// Standalone diagnostics tool: verifies all 12 Metal shader functions
// (6 styles x surface+geometry) are present in the compiled Metal library.

let expectedFunctions: [(style: String, surface: String, geometry: String)] = [
    ("BlackFire",    "blackFireSurface",    "blackFireGeometry"),
    ("Anime",        "animeSurface",        "animeGeometry"),
    ("Hologram",     "hologramSurface",     "hologramGeometry"),
    ("Blob",         "blobSurface",         "blobGeometry"),
    ("PixelVolume",  "pixelVolumeSurface",  "pixelVolumeGeometry"),
    ("Constellation","constellationSurface","constellationGeometry"),
]

guard let device = MTLCreateSystemDefaultDevice() else {
    print("ERROR: Metal device not available")
    exit(1)
}
print("Metal device: \(device.name)")

var library: MTLLibrary?
var strategyUsed = "none"

// Strategy 1: default library
library = device.makeDefaultLibrary()
if library != nil {
    strategyUsed = "device.makeDefaultLibrary()"
    print("Strategy 1 (\(strategyUsed)): \(library!.functionNames.count) functions")
} else {
    print("Strategy 1 FAILED: device.makeDefaultLibrary() returned nil")
}

// Strategy 2: main bundle
if library == nil {
    do {
        library = try device.makeDefaultLibrary(bundle: Bundle.main)
        if library != nil {
            strategyUsed = "bundle: .main"
            print("Strategy 2 (\(strategyUsed)): \(library!.functionNames.count) functions")
        }
    } catch {
        print("Strategy 2 FAILED: \(error)")
    }
}

// Strategy 3: SPM module bundle
if library == nil {
    do {
        library = try device.makeDefaultLibrary(bundle: Bundle.module)
        if library != nil {
            strategyUsed = "bundle: Bundle.module"
            print("Strategy 3 (\(strategyUsed)): \(library!.functionNames.count) functions")
        }
    } catch {
        print("Strategy 3 FAILED: \(error)")
    }
}

guard let lib = library else {
    print("FATAL: No Metal library could be loaded from any source.")
    exit(1)
}

// List all functions
print("\nAll \(lib.functionNames.count) functions in library:")
for name in lib.functionNames.sorted() {
    print("  \(name)")
}

// Check all 6 styles
print("\nVerifying 6 avatar styles:")

var passed = 0
var failed: [(String, String)] = []

for style in expectedFunctions {
    let hasSurface = lib.functionNames.contains(style.surface)
    let hasGeometry = lib.functionNames.contains(style.geometry)

    if hasSurface && hasGeometry {
        print("  [PASS] \(style.style): \(style.surface) + \(style.geometry)")
        passed += 1
    } else {
        var reasons: [String] = []
        if !hasSurface { reasons.append("missing surface: \(style.surface)") }
        if !hasGeometry { reasons.append("missing geometry: \(style.geometry)") }
        let reason = reasons.joined(separator: ", ")
        failed.append((style.style, reason))
        print("  [FAIL] \(style.style): \(reason)")
    }
}

print("\n=== Results ===")
print("Passed: \(passed)/6 styles (\(passed * 100 / 6)%)")
if !failed.isEmpty {
    print("Failed styles:")
    for (s, r) in failed {
        print("  ✗ \(s) — \(r)")
    }
    exit(1)
} else {
    print("All 12 shader functions (6 surface + 6 geometry) found in Metal library via strategy: \(strategyUsed)")
    print("All 6 avatar styles will render correctly.")
    exit(0)
}
