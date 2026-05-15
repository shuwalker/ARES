import SwiftUI

// MARK: - Render Mode
// Every style can render in TWO ways:
// 1. .shader = procedural Metal on a sphere (what we have now)
// 2. .model = load a USDZ/GLB file with skeleton, blend shapes, animations

enum AvatarRenderMode: String, Codable, CaseIterable {
    case shader    // Procedural Metal shader on generated sphere
    case model     // Loaded 3D model with rig, blend shapes, animations
}

enum AvatarStyle: String, CaseIterable, Codable {
    // --- Original shader styles ---
    case blackFire
    case anime
    case hologram
    case blob
    case pixelVolume
    case constellation
    // --- New shader styles ---
    case synthMuse       // Primary: cyberpunk-muse, slit eyes, cheek stripes, cel-shaded
    case warriorSage     // Secondary: blonde beard, golden eyes, cool palette
    case companion       // Ball creature in glass dome, transformation states
    case mysticVoid      // Environment: monolithic stone, sacred geometry, floating tablets
    
    // MARK: - Render Mode
    
    /// Whether this style uses a procedural shader or a loaded 3D model.
    /// Shader styles render on the sphere via Metal shaders.
    /// Model styles load a USDZ/GLB and apply skeletal animation + blend shapes.
    /// A model style can ALSO have its shader applied on top via ModelAvatarLoader.applyShaderStyle().
    var renderMode: AvatarRenderMode {
        // Currently all styles default to .shader — switch to .model
        // when a model file is provided for that style via config or drag-and-drop.
        // This is dynamic: any shader style can become a model style if the user
        // drops a rigged model file that matches the character.
        return .shader
    }
    
    /// If this style has an associated 3D model file, return its URL.
    /// Nil means use procedural shader on sphere.
    var modelFileURL: URL? {
        // Check for model files in ARES Models directory
        let modelsDir = AvatarStyle.modelsDirectory()
        let modelNames: [AvatarStyle: String] = [
            .synthMuse: "synthMuse.usdz",
            .warriorSage: "warriorSage.usdz",
            .companion: "companion.usdz",
            .mysticVoid: "mysticVoid.usdz",
            .anime: "anime.usdz",
            .blackFire: "blackFire.usdz",
        ]
        guard let filename = modelNames[self] else { return nil }
        let url = modelsDir.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    /// The effective render mode — if a model file exists, use .model; otherwise .shader
    var effectiveRenderMode: AvatarRenderMode {
        return modelFileURL != nil ? .model : .shader
    }
    
    // MARK: - Shader Names
    
    var surfaceShaderName: String {
        switch self {
        case .blackFire:      return "blackFireSurface"
        case .anime:          return "animeSurface"
        case .hologram:       return "hologramSurface"
        case .blob:           return "blobSurface"
        case .pixelVolume:   return "pixelVolumeSurface"
        case .constellation:  return "constellationSurface"
        case .synthMuse:     return "synthMuseSurface"
        case .warriorSage:    return "warriorSageSurface"
        case .companion:      return "companionSurface"
        case .mysticVoid:     return "mysticVoidSurface"
        }
    }
    
    var geometryModifierName: String {
        switch self {
        case .blackFire:      return "blackFireGeometry"
        case .anime:          return "animeGeometry"
        case .hologram:       return "hologramGeometry"
        case .blob:           return "blobGeometry"
        case .pixelVolume:   return "pixelVolumeGeometry"
        case .constellation:  return "constellationGeometry"
        case .synthMuse:     return "synthMuseGeometry"
        case .warriorSage:    return "warriorSageGeometry"
        case .companion:      return "companionGeometry"
        case .mysticVoid:     return "mysticVoidGeometry"
        }
    }
    
    // MARK: - Display
    
    var displayName: String {
        switch self {
        case .blackFire:      return "Black Fire"
        case .anime:          return "Anime"
        case .hologram:       return "Hologram"
        case .blob:           return "Blob"
        case .pixelVolume:   return "Pixel Volume"
        case .constellation:  return "Constellation"
        case .synthMuse:     return "Synth Muse"
        case .warriorSage:    return "Warrior Sage"
        case .companion:      return "Companion"
        case .mysticVoid:     return "Mystic Void"
        }
    }

    var category: String {
        switch self {
        case .blackFire:      return "dramatic"
        case .anime:          return "character"
        case .hologram:       return "scifi"
        case .blob:           return "organic"
        case .pixelVolume:   return "retro"
        case .constellation:  return "abstract"
        case .synthMuse:     return "character"
        case .warriorSage:    return "character"
        case .companion:      return "creature"
        case .mysticVoid:     return "environment"
        }
    }
    
    var icon: String {
        switch self {
        case .blackFire:      return "flame"
        case .anime:          return "sparkles.tv"
        case .hologram:       return "wave.3.forward"
        case .blob:           return "circle.circle"
        case .pixelVolume:   return "cube"
        case .constellation:  return "staroflife"
        case .synthMuse:     return "eye"
        case .warriorSage:    return "person.fill"
        case .companion:      return "sphere.fill"
        case .mysticVoid:     return "building.columns.fill"
        }
    }

    var previewGradient: LinearGradient {
        switch self {
        case .blackFire:      return LinearGradient(colors: [.black, .cyan.opacity(0.6), .orange.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .anime:          return LinearGradient(colors: [.pink.opacity(0.6), .purple.opacity(0.5), .blue.opacity(0.4)], startPoint: .top, endPoint: .bottom)
        case .hologram:       return LinearGradient(colors: [.cyan.opacity(0.3), .blue.opacity(0.4), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .blob:           return LinearGradient(colors: [.green.opacity(0.5), .cyan.opacity(0.4)], startPoint: .top, endPoint: .bottom)
        case .pixelVolume:   return LinearGradient(colors: [.yellow.opacity(0.5), .red.opacity(0.4), .purple.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .constellation:  return LinearGradient(colors: [.indigo.opacity(0.8), .white.opacity(0.3)], startPoint: .top, endPoint: .bottom)
        case .synthMuse:     return LinearGradient(colors: [.purple.opacity(0.7), .cyan.opacity(0.6), .pink.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .warriorSage:    return LinearGradient(colors: [.yellow.opacity(0.5), .teal.opacity(0.4), .gray.opacity(0.3)], startPoint: .top, endPoint: .bottom)
        case .companion:      return LinearGradient(colors: [.gray.opacity(0.3), .white.opacity(0.5), .gray.opacity(0.4)], startPoint: .top, endPoint: .bottom)
        case .mysticVoid:     return LinearGradient(colors: [.gray.opacity(0.6), .indigo.opacity(0.4), .gray.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        }
    }
    
    // MARK: - Static Helpers
    
    /// Get the models directory where USDZ/GLB files are stored
    static func modelsDirectory() -> URL {
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ARES")
            .appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }
    
    /// List all available model files in the models directory
    static func availableModels() -> [URL] {
        let modelsDir = modelsDirectory()
        let extensions = ["usdz", "glb", "gltf", "obj", "reality"]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: modelsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        return urls.filter { extensions.contains($0.pathExtension.lowercased()) }
    }
}