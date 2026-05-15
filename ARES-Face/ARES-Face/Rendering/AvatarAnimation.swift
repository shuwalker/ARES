import RealityKit
import AppKit
import QuartzCore

// MARK: - ARES Avatar Animation System
// Ported from AIAvatarKit vrm-idle.js
// Provides: body sway, breathing, blinking, expression mapping, viseme lip sync
//
// This works with ANY 3D model loaded via ModelAvatarLoader — VRM, USDZ, GLB, OBJ.
// Uses the VRM/ARKit standard bone naming convention so rigged models work out of the box.

// MARK: - Expression Mapping
// Maps ARES expression states to ARKit/VRM blend shape names.
// Any rigged model with these blend shapes will animate correctly.
// Source: AIAvatarKit VRMIdle.EXPRESSION_MAP

struct AvatarExpressionMap {
    // VRM 0.x → 1.0 expression name mapping (from vrm-idle.js)
    static let vrmExpressionMap: [String: String] = [
        "joy": "happy",
        "fun": "relaxed",
        "sorrow": "sad",
        "angry": "angry",
        "surprise": "surprised",
        "a": "aa",
        "i": "ih",
        "u": "ou",
        "e": "ee",
        "o": "oh",
        "blink_l": "blinkLeft",
        "blink_r": "blinkRight",
    ]
    
    // ARES AgentState → ARKit blend shape weights
    // These follow the ARKit Face Tracking blend shape convention
    // so any model created in Blender/VRoid/ReadyPlayerMe will work
    static let stateBlendShapes: [AgentState: [String: Float]] = [
        .idle: [:],
        .awakened: [
            "eyeWideLeft": 0.3,
            "eyeWideRight": 0.3,
            "browInnerUpLeft": 0.4,
            "browInnerUpRight": 0.4,
        ],
        .listening: [
            "eyeLookDownLeft": 0.3,
            "eyeLookDownRight": 0.3,
            "mouthFrownLeft": 0.1,
            "mouthFrownRight": 0.1,
        ],
        .thinking: [
            "browDownLeft": 0.4,
            "browDownRight": 0.4,
            "eyeSquintLeft": 0.2,
            "eyeSquintRight": 0.2,
            "mouthFrownLeft": 0.3,
            "mouthFrownRight": 0.3,
        ],
        .speaking: [
            "mouthOpen": 0.4,
            "jawOpen": 0.3,
            "mouthSmileLeft": 0.2,
            "mouthSmileRight": 0.2,
        ],
        .sleeping: [
            "eyeBlinkLeft": 0.8,
            "eyeBlinkRight": 0.8,
            "browDownLeft": 0.2,
            "browDownRight": 0.2,
        ],
    ]
}

// MARK: - Viseme System
// Maps mouth shapes to blend shape weights for lip sync.
// Source: AIAvatarKit VRMIdle.VISEMES + MOUTH_TO_VISEME

struct VisemeSystem {
    static let visemes = ["aa", "ih", "ou", "ee", "oh"]
    
    static let mouthToViseme: [String: [String: Float]] = [
        "closed": [:],
        "half": ["aa": 0.4],
        "open": ["aa": 1.0],
        "u": ["ou": 0.8],
        "e": ["ee": 0.7],
    ]
    
    // Smoothing speed (lerp factor per second)
    static let lerpSpeed: Float = 25.0
    
    // Current smoothed viseme weights
    private var currentWeights: [String: Float] = [:]
    private var targetWeights: [String: Float] = [:]
    
    init() {
        for v in Self.visemes {
            currentWeights[v] = 0
            targetWeights[v] = 0
        }
    }
    
    /// Set target mouth shape
    mutating func setMouthShape(_ shape: String) {
        for v in Self.visemes { targetWeights[v] = 0 }
        if let mapping = Self.mouthToViseme[shape] {
            for (viseme, value) in mapping { targetWeights[viseme] = value }
        }
    }
    
    /// Update viseme smoothing (call each frame with delta time)
    mutating func update(delta: Float) -> [String: Float] {
        let t = min(1.0, Self.lerpSpeed * delta)
        for v in Self.visemes {
            let cur = currentWeights[v] ?? 0
            let tgt = targetWeights[v] ?? 0
            currentWeights[v] = abs(cur + (tgt - cur) * t - tgt) < 0.005 ? tgt : cur + (tgt - cur) * t
        }
        return currentWeights
    }
    
    /// Reset all viseme targets to 0
    mutating func clear() {
        for v in Self.visemes { targetWeights[v] = 0 }
    }
}

// MARK: - Blink System
// Natural random blink with smooth close/open phases.
// Source: AIAvatarKit VRMIdle._updateBlink + _scheduleNextBlink

struct BlinkSystem {
    private var phase: BlinkPhase = .idle
    private var blinkValue: Float = 0
    private var nextBlinkTime: Double = 0
    private var currentTime: Double = 0
    
    enum BlinkPhase {
        case idle
        case closing
        case opening
    }
    
    /// Schedule next blink (random 3-6 second interval)
    private mutating func scheduleNextBlink() {
        nextBlinkTime = currentTime + 3.0 + Double.random(in: 0...3.0)
    }
    
    /// Update blink state (call each frame with delta time).
    /// Returns blink weight 0-1 (0=open, 1=closed)
    mutating func update(delta: Float, isSpeaking: Bool = false, currentExpression: String = "neutral") -> Float {
        currentTime += Double(delta)
        
        // Don't blink during non-neutral expressions
        if currentExpression != "neutral" && phase == .idle {
            scheduleNextBlink()
            return 0
        }
        
        switch phase {
        case .idle:
            if currentTime >= nextBlinkTime && !isSpeaking {
                phase = .closing
            }
        case .closing:
            blinkValue = min(1.0, blinkValue + 18.0 * delta)
            if blinkValue >= 1.0 { phase = .opening }
        case .opening:
            blinkValue = max(0.0, blinkValue - 12.0 * delta)
            if blinkValue <= 0.0 {
                blinkValue = 0
                phase = .idle
                scheduleNextBlink()
            }
        }
        return blinkValue
    }
}

// MARK: - Body Sway System
// fBm noise-driven body motion with smooth damping.
// Source: AIAvatarKit VRMIdle._updateSway + _fbm + _smoothDamp

struct BodySwaySystem {
    // Per-bone sway parameters
    struct SwayTarget {
        let bone: String
        var params: SwayParams
        var state: SwayState
    }
    
    struct SwayParams {
        var globalAmp: Float = 1.0     // 0-3
        var yawAmp: Float = 12.5        // degrees
        var yawSpeed: Float = 0.3       // Hz
        var yawSmooth: Float = 0.4      // seconds
        var rollAmp: Float = 1.5        // degrees
        var rollSpeed: Float = 0.3       // Hz
        var rollSmooth: Float = 0.4      // seconds
        var octaves: Int = 2            // 1-6
        var lacunarity: Float = 2.0     // 1-4
        var persistence: Float = 0.5     // 0.1-1.0
        var convAmp: Float = 0.2         // conversation weight
        var fadeTime: Float = 0.5        // seconds
    }
    
    struct SwayState {
        var yaw: Float = 0
        var roll: Float = 0
        var yawVel: Float = 0
        var rollVel: Float = 0
        var weight: Float = 1.0
        var weightVel: Float = 0
        var lastJerkTime: Double = -10
        var seedYaw: Float
        var seedRoll: Float
        
        init() {
            seedYaw = Float.random(in: 0...1000)
            seedRoll = Float.random(in: 0...1000)
        }
    }
    
    // Available bones for sway (VRM humanoid bone names)
    static let availableBones = [
        "hips", "spine", "chest", "upperChest", "neck", "head",
        "leftShoulder", "rightShoulder"
    ]
    
    // Standard bones map for RealityKit entities
    static let boneEntityNames: [String: String] = [
        "hips": "hips",
        "spine": "spine",
        "chest": "chest",
        "upperChest": "upperChest",
        "neck": "neck",
        "head": "head",
        "leftShoulder": "leftShoulder",
        "rightShoulder": "rightShoulder",
    ]
    
    var targets: [SwayTarget] = []
    var isEnabled: Bool = true
    private var elapsedTime: Double = 0
    
    init() {
        // Default: sway the spine
        addTarget(bone: "spine")
    }
    
    mutating func addTarget(bone: String) {
        targets.append(SwayTarget(
            bone: bone,
            params: SwayParams(),
            state: SwayState()
        ))
    }
    
    private static func nhash(_ n: Float) -> Float {
        let s = sin(n * 127.1 + 311.7) * 43758.5453
        return s - floor(s)
    }
    
    private static func noise1d(_ x: Float) -> Float {
        let i = floor(x)
        let f = x - i
        let u = f * f * (3 - 2 * f)
        return nhash(i) * (1 - u) + nhash(i + 1) * u
    }
    
    private static func fbm(_ t: Float, octaves: Int, lacunarity: Float, persistence: Float) -> Float {
        var value: Float = 0
        var amp: Float = 1
        var freq: Float = 1
        var maxAmp: Float = 0
        for _ in 0..<octaves {
            value += amp * (noise1d(t * freq) * 2 - 1)
            maxAmp += amp
            amp *= persistence
            freq *= lacunarity
        }
        return value / maxAmp
    }
    
    private static func smoothDamp(current: Float, target: Float, velocity: inout Float, smoothTime: Float, dt: Float) -> Float {
        let st = max(0.0001, smoothTime)
        let w = 2.0 / st
        let x = w * dt
        let e = 1.0 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let d = current - target
        let tmp = (velocity + w * d) * dt
        velocity = (velocity - w * tmp) * e
        var r = target + (d + tmp) * e
        if (target > current) == (r > target) { r = target; velocity = 0 }
        return r
    }
    
    /// Update body sway (call each frame with delta time).
    /// Returns array of (boneName, yaw, roll) tuples to apply to entity bones.
    mutating func update(delta: Float, isSpeaking: Bool = false) -> [(bone: String, yaw: Float, roll: Float)] {
        if delta <= 0 { return [] }
        elapsedTime += Double(delta)
        
        let degToRad = Float.pi / 180
        var results: [(bone: String, yaw: Float, roll: Float)] = []
        
        for i in targets.indices {
            let t = Float(elapsedTime)
            let bi = targets[i].state
            let params = targets[i].params
            let gAmp = params.globalAmp
            
            // Conversation weight: reduce sway amplitude when speaking
            let targetW = isSpeaking ? params.convAmp : 1.0
            targets[i].state.weight = Self.smoothDamp(
                current: targets[i].state.weight,
                target: targetW,
                velocity: &targets[i].state.weightVel,
                smoothTime: params.fadeTime,
                dt: delta
            )
            
            // fBm noise targets
            let tgtYaw = Self.fbm(
                t * params.yawSpeed + targets[i].state.seedYaw,
                octaves: params.octaves,
                lacunarity: params.lacunarity,
                persistence: params.persistence
            ) * params.yawAmp
            
            let tgtRoll = Self.fbm(
                t * params.rollSpeed + targets[i].state.seedRoll,
                octaves: params.octaves,
                lacunarity: params.lacunarity,
                persistence: params.persistence
            ) * params.rollAmp
            
            // SmoothDamp
            targets[i].state.yaw = Self.smoothDamp(
                current: targets[i].state.yaw,
                target: tgtYaw,
                velocity: &targets[i].state.yawVel,
                smoothTime: params.yawSmooth,
                dt: delta
            )
            targets[i].state.roll = Self.smoothDamp(
                current: targets[i].state.roll,
                target: tgtRoll,
                velocity: &targets[i].state.rollVel,
                smoothTime: params.rollSmooth,
                dt: delta
            )
            
            let w = gAmp * targets[i].state.weight
            results.append((
                bone: targets[i].bone,
                yaw: targets[i].state.yaw * degToRad * w,
                roll: targets[i].state.roll * degToRad * w
            ))
        }
        
        return results
    }
}

// MARK: - Breathing System
// Simple sinusoidal chest/shoulder movement.
// Source: AIAvatarKit VRMIdle._updateBreathing

struct BreathingSystem {
    var breathScale: Float = 2.0  // 0-5, intensity multiplier
    private var elapsedTime: Double = 0
    
    /// Update breathing (call each frame with delta time).
    /// Returns breath factor (-1 to 1) for scaling chest/shoulders
    mutating func update(delta: Float) -> Float {
        elapsedTime += Double(delta)
        return Float(sin(elapsedTime * 1.5)) * (breathScale / 100.0)
    }
}

// MARK: - Unified Animation Controller
// Ties together all animation subsystems for a loaded 3D model

@MainActor
class AvatarAnimationController {
    private(set) var visemes = VisemeSystem()
    private(set) var blink = BlinkSystem()
    private(set) var sway = BodySwaySystem()
    private(set) var breathing = BreathingSystem()
    
    private(set) var currentExpression: String = "neutral"
    private(set) var currentBlendShapes: [String: Float] = [:]
    
    /// Update all animation subsystems (call each frame)
    func update(delta: Float, isSpeaking: Bool = false, agentState: AgentState = .idle) {
        // 1. Update visemes
        let visemeWeights = visemes.update(delta: delta)
        
        // 2. Update blink
        let blinkWeight = blink.update(delta: delta, isSpeaking: isSpeaking, currentExpression: currentExpression)
        
        // 3. Update body sway
        let swayBones = sway.update(delta: delta, isSpeaking: isSpeaking)
        
        // 4. Update breathing
        let breathFactor = breathing.update(delta: delta)
        
        // 5. Blend expression from agent state
        let expressionWeights = AvatarExpressionMap.stateBlendShapes[agentState] ?? [:]
        
        // 6. Combine all blend shape weights
        // Priority: expression > viseme > blink
        var combined = expressionWeights
        for (name, weight) in visemeWeights {
            combined[name] = max(combined[name] ?? 0, weight)
        }
        combined["blink"] = max(combined["blink"] ?? 0, blinkWeight)
        
        currentBlendShapes = combined
        
        // Note: Applying sway/breathing transforms and blend shapes to the entity
        // is done by AvatarSceneDelegate or similar, which reads these computed values
        // and applies them to the loaded model's skeleton and blend shape components.
        // This separation keeps the animation logic pure and testable.
    }
    
    /// Set the current facial expression
    func setExpression(_ name: String) {
        currentExpression = name.lowercased()
        // Map VRM expression names
        if let mapped = AvatarExpressionMap.vrmExpressionMap[currentExpression] {
            currentExpression = mapped
        }
    }
    
    /// Set mouth shape for lip sync
    func setMouthShape(_ shape: String) {
        visemes.setMouthShape(shape)
    }
    
    /// Play a named animation clip (if VRMA animations are loaded)
    func playAnimation(named name: String, duration: Float = 0) {
        // TODO: VRMA animation playback — requires AnimationResource from loaded model
        print("AvatarAnimationController: playAnimation(\(name), duration: \(duration)) — not yet connected to VRMA")
    }
}