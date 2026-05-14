import RealityKit
import Metal
import QuartzCore
import Foundation

// MARK: - Swift Uniform Structs
// These must match the C struct layout in SharedHeader.h exactly.
// CustomMaterial.withMutableUniforms uses the struct's memory layout
// to copy bytes into the Metal buffer — so the field order and types
// must be identical to what the vertex/fragment shaders expect.

struct SurfaceCustomUniforms {
    var intensity: Float        // 0.0 - 1.0
    var expression: Float       // 0=neutral, 1=happy, 2=curious...
    var isSpeaking: Float       // 0.0 or 1.0
    var time: Float             // elapsed seconds
    // Cognition uniforms — must match SharedHeader.h ordering.
    var noiseScale: Float
    var emissivePulse: Float
    var vertexJitter: Float
    var glitchAmplitude: Float
}

struct GeometryCustomUniforms {
    var vertexAnimationSpeed: Float
    var vertexAnimationAmplitude: Float
    var displacementScale: Float
    var normalInfluence: Float
}

/// Creates and manages CustomMaterial for the avatar, including uniform updates and style switching.
class AvatarRenderer {
    private var library: MTLLibrary?
    private var currentStyle: AvatarStyle = .blackFire
    private var startTime: Double = CACurrentMediaTime()
    
    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("ERROR: Metal device not available")
            return
        }
        
        var loadedLibrary: MTLLibrary?
        
        // Strategy 1: default library compiled into the executable
        loadedLibrary = device.makeDefaultLibrary()
        if loadedLibrary != nil {
            print("AvatarRenderer: Loaded default Metal library")
        } else {
            print("AvatarRenderer: device.makeDefaultLibrary() returned nil")
        }
        
        // Strategy 2: main app bundle
        if loadedLibrary == nil {
            do {
                loadedLibrary = try device.makeDefaultLibrary(bundle: .main)
                if loadedLibrary != nil {
                    print("AvatarRenderer: Loaded Metal library from main bundle")
                }
            } catch {
                print("AvatarRenderer: makeDefaultLibrary(bundle: .main) failed: \(error)")
            }
        }
        
        // Strategy 3: SPM module bundle (for processed resources)
        if loadedLibrary == nil {
            do {
                loadedLibrary = try device.makeDefaultLibrary(bundle: Bundle.module)
                if loadedLibrary != nil {
                    print("AvatarRenderer: Loaded Metal library from module bundle")
                }
            } catch {
                print("AvatarRenderer: makeDefaultLibrary(bundle: Bundle.module) failed: \(error)")
            }
        }
        
        self.library = loadedLibrary
        
        if let lib = loadedLibrary {
            let functions = Array(lib.functionNames).sorted()
            print("AvatarRenderer: Library loaded with \(functions.count) functions:")
            for name in functions {
                print("  - \(name)")
            }
        } else {
            print("ERROR: Could not load Metal library from any source. Shaders will not be available.")
        }
    }
    
    /// Create a CustomMaterial for the given style
    func createMaterial(style: AvatarStyle) -> CustomMaterial? {
        guard let library = library else {
            print("ERROR: No Metal library available when creating material for \(style.displayName)")
            return nil
        }
        
        print("AvatarRenderer: Creating material for style: \(style.displayName)")
        print("AvatarRenderer: Looking for surface shader: \(style.surfaceShaderName)")
        print("AvatarRenderer: Looking for geometry modifier: \(style.geometryModifierName)")
        
        let hasSurface = library.functionNames.contains(style.surfaceShaderName)
        let hasGeometry = library.functionNames.contains(style.geometryModifierName)
        
        print("AvatarRenderer: Found '\(style.surfaceShaderName)': \(hasSurface)")
        print("AvatarRenderer: Found '\(style.geometryModifierName)': \(hasGeometry)")
        
        guard hasSurface && hasGeometry else {
            print("ERROR: Missing required shader functions for \(style.displayName)")
            return nil
        }
        
        let surfaceShader = CustomMaterial.SurfaceShader(
            named: style.surfaceShaderName, in: library
        )
        
        let geometryModifier = CustomMaterial.GeometryModifier(
            named: style.geometryModifierName, in: library
        )
        
        do {
            let baseMaterial = SimpleMaterial(color: .black, isMetallic: false)
            let material = try CustomMaterial(
                from: baseMaterial,
                surfaceShader: surfaceShader,
                geometryModifier: geometryModifier
            )
            currentStyle = style
            print("AvatarRenderer: Successfully created CustomMaterial for \(style.displayName)")
            return material
        } catch {
            print("ERROR: Failed to create CustomMaterial for \(style.displayName): \(error)")
            return nil
        }
    }
    
    /// Update surface shader uniforms per frame
    func updateSurfaceUniforms(
        material: inout CustomMaterial,
        intensity: Float,
        expression: Float,
        isSpeaking: Float,
        time: Float,
        cognition: CognitiveUniformValues = .neutral
    ) {
        material.withMutableUniforms(ofType: SurfaceCustomUniforms.self, stage: .surfaceShader) { params, _ in
            params.intensity = intensity
            params.expression = expression
            params.isSpeaking = isSpeaking
            params.time = time
            params.noiseScale = cognition.noiseScale
            params.emissivePulse = cognition.emissivePulse
            params.vertexJitter = cognition.vertexJitter
            params.glitchAmplitude = cognition.glitchAmplitude
        }
    }
    
    /// Update geometry modifier uniforms per frame
    func updateGeometryUniforms(material: inout CustomMaterial, speed: Float, amplitude: Float, displacementScale: Float, normalInfluence: Float, time: Float) {
        material.withMutableUniforms(ofType: GeometryCustomUniforms.self, stage: .geometryModifier) { params, _ in
            params.vertexAnimationSpeed = speed
            params.vertexAnimationAmplitude = amplitude
            params.displacementScale = displacementScale
            params.normalInfluence = normalInfluence
        }
    }
    
    /// Get current elapsed time for shader animation
    var elapsedTime: Float {
        Float(CACurrentMediaTime() - startTime)
    }
    
    /// Compute geometry uniforms based on agent state
    func geometryParams(for state: AgentState) -> (speed: Float, amplitude: Float, displacementScale: Float, normalInfluence: Float) {
        switch state {
        case .idle:      return (0.5, 0.005, 1.0, 0.8)
        case .awakened:  return (1.0, 0.01, 1.2, 0.9)
        case .listening: return (1.5, 0.008, 1.0, 0.85)
        case .thinking:  return (2.0, 0.02, 1.5, 1.0)
        case .speaking:  return (3.0, 0.025, 1.3, 0.9)
        case .sleeping:  return (0.3, 0.002, 0.8, 0.5)
        }
    }
}
