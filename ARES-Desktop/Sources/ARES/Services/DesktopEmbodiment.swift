import Foundation
import CoreGraphics
import ARESCore

/// Native Desktop Embodiment for ARES.
/// This connects the backend reasoning engine's requests (like setting expressions or speaking)
/// directly to the native ARES UI and Voice Engine via the EventBus.
public final class DesktopEmbodiment: Embodiment, @unchecked Sendable {
    private var _state: EmbodimentState = .idle
    private let eventBus: any EventBus
    private let voiceEngine: any VoiceEngine
    
    public let capabilities: Set<String> = ["expression", "gaze", "speech", "approval", "desktop_ui"]
    public let kind: String = "desktop"
    
    public var state: EmbodimentState {
        get async { _state }
    }
    
    public init(eventBus: any EventBus, voiceEngine: any VoiceEngine) {
        self.eventBus = eventBus
        self.voiceEngine = voiceEngine
        print("✅ [WIRING] DesktopEmbodiment initialized")
    }
    
    public func setFaceExpression(_ expr: FaceExpression) async throws {
        _state = .thinking
        
        let event = EmbodimentEvent(action: "expression", success: true)
        try await eventBus.publish(event)
    }
    
    public func setEyeGaze(_ target: EyeGazeTarget) async throws {
        let event = EmbodimentEvent(action: "gaze", success: true)
        try await eventBus.publish(event)
    }
    
    public func speak(text: String, prosody: Prosody) async throws {
        _state = .speaking
        
        // Let the UI know we are speaking
        let eventStart = EmbodimentEvent(action: "speaking_start", success: true)
        try await eventBus.publish(eventStart)
        
        // Route to the actual VoiceEngine
        _ = try await voiceEngine.synthesize(text: text, prosody: prosody)
        
        _state = .idle
        let eventEnd = EmbodimentEvent(action: "speaking_end", success: true)
        try await eventBus.publish(eventEnd)
    }
    
    public func requestApproval(_ action: ApprovalRequest) async throws -> Bool {
        // Broadcast an approval request to the UI. The UI should show a modal.
        let event = EmbodimentEvent(action: "approval_request", success: true)
        try await eventBus.publish(event)
        
        // For now, auto-approve after publishing since we don't have a blocking UI delegate yet.
        return true
    }
    
    nonisolated public func getCapabilityInfo(name: String) -> [String: AnyCodable]? {
        switch name {
        case "expression":
            return ["emotions": AnyCodable.string("happy, sad, thinking, confused, neutral")]
        case "gaze":
            return ["range": AnyCodable.string("Screen coordinate space")]
        case "speech":
            return ["synthesizer": AnyCodable.string("Native VoiceEngine")]
        case "approval":
            return ["timeout": AnyCodable.number(30)]
        default:
            return nil
        }
    }
}
