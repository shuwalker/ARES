import SwiftUI
import RealityKit
import Metal

struct AvatarSceneView: View {
    @EnvironmentObject var brain: BrainConnection
    @Binding var style: AvatarStyle
    @State private var avatarEntity: ModelEntity?
    @State private var renderer: AvatarRenderer?
    @State private var currentMaterial: CustomMaterial?
    
    var body: some View {
        RealityView { content in
            let renderer = AvatarRenderer()
            self.renderer = renderer
            
            let entity: ModelEntity
            if let avatar = AvatarEntity.create(style: style, renderer: renderer) {
                entity = avatar
                self.avatarEntity = entity
                self.currentMaterial = entity.model?.materials.first as? CustomMaterial
                content.add(entity)
            } else {
                print("WARNING: CustomMaterial creation failed for \(style.displayName). Using fallback SimpleMaterial.")
                let fallback = createFallbackEntity()
                entity = fallback
                self.avatarEntity = fallback
                content.add(fallback)
            }
            
            let lighting = SceneSetup.createLighting()
            content.add(lighting)
            
        } update: { content in
            updateAvatarUniforms()
        }
        .gesture(
            TapGesture()
                .onEnded { _ in
                    cycleStyle()
                }
        )
    }
    
    private func createFallbackEntity() -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 0.15)
        let material = SimpleMaterial(
            color: .systemPurple,
            isMetallic: false
        )
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "avatar_fallback"
        return entity
    }
    
    private func updateAvatarUniforms() {
        guard var material = currentMaterial else { return }
        
        let stateConfig = FaceConfig.config(for: brain.agentState)
        let intensity = stateConfig.intensity
        let expression = brain.avatarExpression.floatValue
        let isSpeaking: Float = brain.agentState == .speaking ? 1.0 : 0.0
        let time = renderer?.elapsedTime ?? 0
        
        renderer?.updateSurfaceUniforms(
            material: &material,
            intensity: intensity,
            expression: expression,
            isSpeaking: isSpeaking,
            time: time
        )
        
        if let geoParams = renderer?.geometryParams(for: brain.agentState) {
            renderer?.updateGeometryUniforms(
                material: &material,
                speed: geoParams.speed,
                amplitude: geoParams.amplitude,
                displacementScale: geoParams.displacementScale,
                normalInfluence: geoParams.normalInfluence,
                time: time
            )
        }
        
        // Apply updated material back to entity
        avatarEntity?.model?.materials = [material]
        currentMaterial = material
    }
    
    private func cycleStyle() {
        let allStyles = AvatarStyle.allCases
        guard let currentIndex = allStyles.firstIndex(of: style) else { return }
        let nextIndex = allStyles.index(after: currentIndex) % allStyles.count
        style = allStyles[nextIndex]
        
        guard let renderer = renderer else { return }
        
        if let material = renderer.createMaterial(style: style) {
            currentMaterial = material
            if avatarEntity?.name == "avatar_fallback" {
                // Replace fallback with real entity
                if let newEntity = AvatarEntity.create(style: style, renderer: renderer) {
                    avatarEntity = newEntity
                }
            }
            avatarEntity?.model?.materials = [material]
        } else {
            print("WARNING: Could not create material for \(style.displayName) during style switch. Entity unchanged.")
        }
    }
}
