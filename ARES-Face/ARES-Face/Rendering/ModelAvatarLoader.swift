import RealityKit
import AppKit
import Combine
import ModelIO
import MetalKit

// MARK: - 3D Model Avatar Loading

/// Loads and manages rigged 3D model avatars (USDZ, GLB/GLTF) in RealityKit.
/// This is a separate render path from the procedural shader sphere — 
/// model avatars use skeletal animation, blend shapes, and textured meshes
/// while shader avatars use CustomMaterial on a generated sphere.
///
/// Supported formats:
/// - .usdz (Apple's preferred, best RealityKit support)
/// - .glb / .gltf (via ModelIO conversion)
/// - .obj (static mesh, no rigging)
///
/// Model hierarchy after loading:
///   anchorEntity
///   └── modelEntity (root of loaded model)
///       ├── skeletal rig (SkeletalPoseComponent)
///       ├── blend shapes (BlendShapeWeightsComponent)
///       └── collision shapes
@MainActor
class ModelAvatarLoader: ObservableObject {
    
    /// Currently loaded model entity, if any
    private(set) var currentModel: ModelEntity?
    
    /// Anchor entity for the model in the scene
    private(set) var anchor: AnchorEntity?
    
    /// Available animations from the loaded model
    private(set) var animations: [AnimationResource] = []
    
    /// Available blend shape weights
    private(set) var blendShapes: [String: Float] = [:]
    
    /// Skinning data for skeletal animation — placeholder until RealityKit skeleton API solidifies
    private(set) var skeleton: Any? // SkeletonDefinition
    
    /// Load a 3D model from file URL
    /// - Parameters:
    ///   - url: File URL to .usdz, .glb, .gltf, or .obj
    ///   - scale: Uniform scale factor (default 1.0)
    ///   - position: World position for the anchor
    ///   - rotation: Initial rotation in radians
    /// - Returns: The anchor entity added to the scene, or nil on failure
    func loadModel(
        from url: URL,
        scale: Float = 1.0,
        position: SIMD3<Float> = [0, 0, 0],
        rotation: Float = 0
    ) async -> AnchorEntity? {
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "usdz":
            return await loadUSDZ(from: url, scale: scale, position: position, rotation: rotation)
        case "glb", "gltf":
            return await loadGLB(from: url, scale: scale, position: position, rotation: rotation)
        case "obj":
            return await loadOBJ(from: url, scale: scale, position: position, rotation: rotation)
        default:
            print("ModelAvatarLoader: Unsupported format: .\(ext)")
            return nil
        }
    }
    
    /// Load a USDZ model (Apple's native format)
    private func loadUSDZ(
        from url: URL,
        scale: Float,
        position: SIMD3<Float>,
        rotation: Float
    ) async -> AnchorEntity? {
        do {
            let entity = try await ModelEntity.loadModel(contentsOf: url)
            
            // Apply scale
            entity.scale = SIMD3<Float>(repeating: scale)
            
            // Extract animations — API varies by RealityKit version
            if let animationRes = try? entity.availableAnimations.first {
                animations = [animationRes]
                print("ModelAvatarLoader: Found 1 animation")
            }
            
            // Extract skeleton if available — RealityKit API may differ per SDK version
            #if os(iOS)
            if #available(iOS 18, *) {
                // SkeletalPoseComponent API available
            }
            #endif
            
            // Create anchor
            let anchor = AnchorEntity(world: position)
            anchor.name = "model_avatar_anchor"
            anchor.orientation = simd_quatf(angle: rotation, axis: [0, 1, 0])
            anchor.addChild(entity)
            
            currentModel = entity
            self.anchor = anchor
            
            print("ModelAvatarLoader: Loaded USDZ model '\(url.lastPathComponent)' with \(animations.count) animations")
            return anchor
            
        } catch {
            print("ModelAvatarLoader: Failed to load USDZ: \(error)")
            return nil
        }
    }
    
    /// Load a GLB/GLTF model via ModelIO conversion to USDZ
    private func loadGLB(
        from url: URL,
        scale: Float,
        position: SIMD3<Float>,
        rotation: Float
    ) async -> AnchorEntity? {
        // RealityKit on macOS 15+ can load GLB directly in some cases,
        // but reliable path is ModelIO → USDZ
        // Try direct load first, fall back to conversion
        do {
            let entity = try await ModelEntity.loadModel(contentsOf: url)
            entity.scale = SIMD3<Float>(repeating: scale)
            
            let anchor = AnchorEntity(world: position)
            anchor.name = "model_avatar_anchor_glb"
            anchor.orientation = simd_quatf(angle: rotation, axis: [0, 1, 0])
            anchor.addChild(entity)
            
            currentModel = entity
            self.anchor = anchor
            
            print("ModelAvatarLoader: Loaded GLB model '\(url.lastPathComponent)'")
            return anchor
            
        } catch {
            // Direct load failed — convert via ModelIO
            print("ModelAvatarLoader: Direct GLB load failed, attempting ModelIO conversion: \(error)")
            return await convertAndLoadGLB(from: url, scale: scale, position: position, rotation: rotation)
        }
    }
    
    /// Convert GLB to USDZ via ModelIO, then load
    private func convertAndLoadGLB(
        from url: URL,
        scale: Float,
        position: SIMD3<Float>,
        rotation: Float
    ) async -> AnchorEntity? {
        // Use MDLAsset for conversion
        guard let asset = try? MDLAsset(url: url) else {
            print("ModelAvatarLoader: Could not open GLB with ModelIO")
            return nil
        }
        
        // Export to temporary USDZ
        let tempDir = FileManager.default.temporaryDirectory
        let usdzName = url.deletingPathExtension().lastPathComponent + "_converted"
        let usdzURL = tempDir.appendingPathComponent(usdzName + ".usdz")
        
        do {
            try asset.export(to: usdzURL)
            print("ModelAvatarLoader: Converted GLB to USDZ at \(usdzURL.path)")
            return await loadUSDZ(from: usdzURL, scale: scale, position: position, rotation: rotation)
        } catch {
            print("ModelAvatarLoader: ModelIO conversion failed: \(error)")
            return nil
        }
    }
    
    /// Load a static OBJ mesh (no rigging)
    private func loadOBJ(
        from url: URL,
        scale: Float,
        position: SIMD3<Float>,
        rotation: Float
    ) async -> AnchorEntity? {
        do {
            let entity = try await ModelEntity.loadModel(contentsOf: url)
            entity.scale = SIMD3<Float>(repeating: scale)
            
            let anchor = AnchorEntity(world: position)
            anchor.name = "model_avatar_anchor_obj"
            anchor.orientation = simd_quatf(angle: rotation, axis: [0, 1, 0])
            anchor.addChild(entity)
            
            currentModel = entity
            self.anchor = anchor
            
            // OBJ has no animations or skeleton
            animations = []
            skeleton = nil
            
            print("ModelAvatarLoader: Loaded OBJ model '\(url.lastPathComponent)' (static, no rig)")
            return anchor
            
        } catch {
            print("ModelAvatarLoader: Failed to load OBJ: \(error)")
            return nil
        }
    }
    
    // MARK: - Animation Playback
    
    /// Play an animation by index
    func playAnimation(index: Int, loop: Bool = true) {
        guard index < animations.count else {
            print("ModelAvatarLoader: Animation index \(index) out of range (0..\(animations.count))")
            return
        }
        // TODO: Implement animation playback via RealityKit's AnimationPlaybackController
    }
    
    /// Set blend shape weight (for facial expressions)
    /// - Parameters:
    ///   - name: Blend shape name (e.g., "mouthSmile", "eyeBlinkLeft")
    ///   - weight: 0.0 to 1.0
    func setBlendShape(name: String, weight: Float) {
        blendShapes[name] = weight
        // TODO: Apply to BlendShapeWeightsComponent when available
    }
    
    /// Apply a facial expression preset from the existing FaceConfig system
    func applyExpression(_ expression: AvatarExpression) {
        // Map our expression enum to blend shape weights
        let mapping: [String: Float] = expressionToBlendShapes(expression)
        for (name, weight) in mapping {
            blendShapes[name] = weight
        }
    }
    
    // MARK: - Expression → Blend Shape Mapping
    
    /// Convert ARES avatar expression to standard blend shape weights
    /// These follow the ARKit/Facial Action Coding System conventions
    /// so any rigged model with standard blend shapes will work
    private func expressionToBlendShapes(_ expression: AvatarExpression) -> [String: Float] {
        switch expression {
        case .neutral:
            return [:]  // all weights at 0
        case .happy:
            return [
                "mouthSmileLeft": 0.8,
                "mouthSmileRight": 0.8,
                "cheekPuffLeft": 0.3,
                "cheekPuffRight": 0.3,
                "eyeSquintLeft": 0.3,
                "eyeSquintRight": 0.3
            ]
        case .curious:
            return [
                "eyeWideLeft": 0.5,
                "eyeWideRight": 0.5,
                "browInnerUpLeft": 0.6,
                "browInnerUpRight": 0.6,
                "mouthFunnel": 0.2
            ]
        case .thinking:
            return [
                "browDownLeft": 0.4,
                "eyeSquintLeft": 0.2,
                "mouthFrownLeft": 0.3,
                "jawOpen": 0.1,
                "eyeLookDownLeft": 0.4,
                "eyeLookDownRight": 0.4
            ]
        case .surprised:
            return [
                "eyeWideLeft": 0.9,
                "eyeWideRight": 0.9,
                "browInnerUpLeft": 0.8,
                "browInnerUpRight": 0.8,
                "jawOpen": 0.6,
                "mouthOpen": 0.5
            ]
        case .concerned:
            return [
                "browDownLeft": 0.3,
                "browDownRight": 0.3,
                "mouthFrownLeft": 0.4,
                "mouthFrownRight": 0.4,
                "eyeSquintLeft": 0.2,
                "eyeSquintRight": 0.2
            ]
        case .excited:
            return [
                "mouthSmileLeft": 1.0,
                "mouthSmileRight": 1.0,
                "eyeWideLeft": 0.6,
                "eyeWideRight": 0.6,
                "browInnerUpLeft": 0.7,
                "browInnerUpRight": 0.7,
                "cheekPuffLeft": 0.5,
                "cheekPuffRight": 0.5
            ]
        case .sleepy:
            return [
                "eyeBlinkLeft": 0.7,
                "eyeBlinkRight": 0.7,
                "browDownLeft": 0.2,
                "browDownRight": 0.2,
                "mouthFrownLeft": 0.1,
                "mouthFrownRight": 0.1
            ]
        }
    }
    
    // MARK: - Style Transition
    
    /// Swap the current model's material to match an AvatarStyle
    /// This applies a CustomMaterial (from the shader system) onto a 3D model,
    /// allowing procedural shader effects on loaded meshes
    func applyShaderStyle(
        _ style: AvatarStyle,
        renderer: AvatarRenderer,
        on entity: ModelEntity
    ) {
        guard let material = renderer.createMaterial(style: style) else {
            print("ModelAvatarLoader: Could not create material for \(style.displayName)")
            return
        }
        // Replace all materials on the model with the custom shader
        entity.model?.materials = [material]
        print("ModelAvatarLoader: Applied \(style.displayName) shader to model")
    }
    
    // MARK: - Utility
    
    /// List available models in the ARES models directory
    static func availableModels() -> [URL] {
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ARES")
            .appendingPathComponent("Models")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        
        let extensions = ["usdz", "glb", "gltf", "obj", "reality"]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: modelsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        
        return urls.filter { extensions.contains($0.pathExtension.lowercased()) }
    }
    
    /// Get the models directory path (for external tools to save to)
    static func modelsDirectory() -> URL {
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ARES")
            .appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }
}