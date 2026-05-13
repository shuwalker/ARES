import RealityKit
import AppKit

/// Sets up lighting and environment for the RealityKit scene
/// Uses macOS 15+ RealityKit API
@MainActor
struct SceneSetup {
    
    /// Create lighting entities for the scene
    static func createLighting() -> Entity {
        let root = Entity()
        root.name = "lighting_root"
        
        // Primary directional light — slightly above and in front
        var directionalComponent = DirectionalLightComponent()
        directionalComponent.intensity = 2000
        directionalComponent.color = .white
        
        let directionalEntity = Entity()
        directionalEntity.name = "directional_light"
        directionalEntity.components.set(directionalComponent)
        directionalEntity.transform.rotation = simd_quatf(angle: -.pi / 4, axis: SIMD3(x: 1, y: 0, z: 0))
        root.addChild(directionalEntity)
        
        // Fill light — violet tint for dark fire atmosphere
        var fillLight = DirectionalLightComponent()
        fillLight.intensity = 600
        fillLight.color = NSColor(calibratedRed: 0.15, green: 0.1, blue: 0.25, alpha: 1.0)
        
        let fillEntity = Entity()
        fillEntity.name = "fill_light"
        fillEntity.components.set(fillLight)
        fillEntity.transform.rotation = simd_quatf(angle: .pi / 3, axis: SIMD3(x: -1, y: 1, z: 0))
        root.addChild(fillEntity)
        
        // Point light above the avatar for dramatic violet accent
        var pointLight = PointLightComponent()
        pointLight.intensity = 1500
        pointLight.color = NSColor(calibratedRed: 0.4, green: 0.2, blue: 0.8, alpha: 1.0)
        
        let pointEntity = Entity()
        pointEntity.name = "point_light"
        pointEntity.components.set(pointLight)
        pointEntity.position = SIMD3<Float>(0, 0.5, 0.3)
        root.addChild(pointEntity)
        
        return root
    }
}