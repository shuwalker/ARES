import Foundation

/// Black fire particle system — procedural, driven by agent state.
/// Research-backed approach: subtractive compositing via dark particles
/// with organic noise patterns. GPU budget: well under 1ms on M1.
struct BlackFireSystem {
    // Particle state — evolves each frame
    var particles: [FireParticle] = []
    var intensity: Float = 0.0        // 0.0 (embers) → 1.0 (inferno)
    var targetIntensity: Float = 0.3
    let maxParticles = 40
    
    init() {
        particles = (0..<maxParticles).map { _ in FireParticle.random() }
    }
    
    mutating func update(deltaTime: Float, state: AgentState) {
        // Map agent state to target intensity
        targetIntensity = switch state {
        case .idle:      0.15
        case .awakened:  0.3
        case .listening: 0.35
        case .thinking:  0.7
        case .speaking:  0.5
        case .sleeping:  0.05
        }
        
        // Smooth ramp
        intensity += (targetIntensity - intensity) * min(1.0, deltaTime * 4.0)
        
        // Update particles
        for i in 0..<particles.count {
            particles[i].update(deltaTime: deltaTime, intensity: intensity)
        }
    }
}

struct FireParticle {
    var angle: Float           // radians around center
    var distance: Float        // normalized 0-1 (inner→outer)
    var size: Float            // 0-1
    var life: Float            // 0-1 (birth→death)
    var speed: Float           // angular velocity
    var oscillationPhase: Float
    var oscillationSpeed: Float
    
    static func random() -> FireParticle {
        FireParticle(
            angle: Float.random(in: 0...(2 * .pi)),
            distance: Float.random(in: 0.7...1.3),
            size: Float.random(in: 0.1...0.4),
            life: Float.random(in: 0...1),
            speed: Float.random(in: 0.3...2.0),
            oscillationPhase: Float.random(in: 0...(2 * .pi)),
            oscillationSpeed: Float.random(in: 1.0...4.0)
        )
    }
    
    mutating func update(deltaTime: Float, intensity: Float) {
        angle += speed * intensity * deltaTime * 3.0
        life -= deltaTime * (0.3 + intensity * 0.5)
        if life <= 0 { 
            self = FireParticle.random()
            life = 1.0
        }
    }
}
