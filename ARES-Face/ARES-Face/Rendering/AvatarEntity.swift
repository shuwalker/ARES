import RealityKit
import AppKit

/// Creates the avatar ModelEntity with sphere mesh and CustomMaterial
@MainActor
struct AvatarEntity {
    /// Create the avatar entity with a sphere mesh and the given material.
    /// Falls back to a SimpleMaterial with an emissive color if CustomMaterial creation fails.
    static func create(style: AvatarStyle, renderer: AvatarRenderer) -> ModelEntity? {
        let mesh = MeshResource.generateSphere(radius: 0.15)
        
        if let material = renderer.createMaterial(style: style) {
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = "avatar"
            return entity
        }
        
        print("WARNING: CustomMaterial creation failed for \(style.displayName). Falling back to SimpleMaterial.")
        
        let fallbackColor: NSColor
        switch style {
        case .blackFire:     fallbackColor = NSColor(calibratedRed: 0.15, green: 0.02, blue: 0.35, alpha: 1.0)
        case .anime:         fallbackColor = NSColor(calibratedRed: 0.8, green: 0.3, blue: 0.5, alpha: 1.0)
        case .hologram:      fallbackColor = NSColor(calibratedRed: 0.2, green: 0.7, blue: 0.9, alpha: 1.0)
        case .blob:          fallbackColor = NSColor(calibratedRed: 0.5, green: 0.8, blue: 0.3, alpha: 1.0)
        case .pixelVolume:   fallbackColor = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.8, alpha: 1.0)
        case .constellation: fallbackColor = NSColor(calibratedRed: 0.9, green: 0.8, blue: 0.2, alpha: 1.0)
        }
        
        let material = SimpleMaterial(color: fallbackColor, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "avatar_fallback"
        return entity
    }
    
    /// Update the material on an existing entity when switching styles
    static func updateStyle(entity: ModelEntity, style: AvatarStyle, renderer: AvatarRenderer) {
        guard let material = renderer.createMaterial(style: style) else {
            print("WARNING: Could not create material for style \(style.displayName)")
            return
        }
        entity.model?.materials = [material]
    }
}
