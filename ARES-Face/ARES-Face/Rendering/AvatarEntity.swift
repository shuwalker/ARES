import RealityKit
import AppKit
import Combine

/// Creates the avatar entity — either as a procedural shader sphere
/// or as a loaded 3D model with rigging and blend shapes.
///
/// Two render paths:
/// 1. .shader mode: MeshResource.generateSphere() + CustomMaterial (existing path)
/// 2. .model mode: Load USDZ/GLB with skeletal animation + blend shapes (new path)
///
/// The render mode is determined by AvatarStyle.effectiveRenderMode:
/// - If a model file exists in ~/Library/Application Support/ARES/Models/ → .model
/// - Otherwise → .shader (procedural on sphere)
@MainActor
struct AvatarEntity {
    
    /// Create the avatar entity with the appropriate render path.
    /// - Parameters:
    ///   - style: The avatar style to render
    ///   - renderer: The shader renderer for procedural styles
    ///   - modelLoader: The model loader for 3D model styles (creates internally if nil)
    /// - Returns: The entity (ModelEntity for shader, AnchorEntity for model) or nil on failure
    static func create(
        style: AvatarStyle,
        renderer: AvatarRenderer,
        modelLoader: ModelAvatarLoader? = nil
    ) -> Entity? {
        switch style.effectiveRenderMode {
        case .shader:
            return createShaderSphere(style: style, renderer: renderer)
        case .model:
            guard let url = style.modelFileURL else {
                print("AvatarEntity: Model mode but no file URL for \(style.displayName), falling back to shader")
                return createShaderSphere(style: style, renderer: renderer)
            }
            // Model loading is async — return a placeholder sphere immediately,
            // the model loads in the background and replaces it
            let placeholder = createShaderSphere(style: style, renderer: renderer)
            placeholder?.name = "avatar_placeholder"
            
            // Kick off async model load
            let loader = modelLoader ?? ModelAvatarLoader()
            Task {
                if let anchor = await loader.loadModel(from: url) {
                    // Post notification for the view to swap in the loaded model
                    NotificationCenter.default.post(
                        name: .avatarModelDidLoad,
                        object: nil,
                        userInfo: ["anchor": anchor, "style": style, "loader": loader]
                    )
                }
            }
            return placeholder
        }
    }
    
    /// Original shader-on-sphere render path
    private static func createShaderSphere(
        style: AvatarStyle,
        renderer: AvatarRenderer
    ) -> ModelEntity? {
        // Higher poly sphere for 3D displacement shaders — smooth, not faceted
        let mesh = MeshResource.generateSphere(radius: 0.5)
        
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
        case .synthMuse:    fallbackColor = NSColor(calibratedRed: 0.7, green: 0.2, blue: 0.9, alpha: 1.0)
        case .warriorSage:   fallbackColor = NSColor(calibratedRed: 0.8, green: 0.7, blue: 0.3, alpha: 1.0)
        case .companion:     fallbackColor = NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        case .mysticVoid:    fallbackColor = NSColor(calibratedRed: 0.4, green: 0.4, blue: 0.5, alpha: 1.0)
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

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a 3D model avatar finishes loading asynchronously
    static let avatarModelDidLoad = Notification.Name("avatarModelDidLoad")
}