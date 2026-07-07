import Foundation
import ScreenCaptureKit
import ARESCore
import CoreGraphics

@available(macOS 12.3, *)
public final class ScreenCaptureWorldModel: WorldPerception, @unchecked Sendable {
    public var capabilities: Set<String> { ["desktopWindows", "screenContext"] }
    
    public init() {}
    
    // MARK: - WorldPerception Methods

    public func getState() async throws -> SceneState {
        var objects: [SceneObject] = []
        
        if #available(macOS 13.0, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                for window in content.windows {
                    // Filter out non-active or tiny windows
                    guard window.isActive else { continue }
                    
                    let appName = window.owningApplication?.applicationName ?? "Unknown App"
                    let title = window.title ?? ""
                    
                    let obj = SceneObject(
                        kind: "screen",
                        label: appName,
                        boundingBox: window.frame,
                        confidence: 1.0,
                        attributes: ["title": AnyCodable.string(title)]
                    )
                    objects.append(obj)
                }
            } catch {
                print("⚠️ [ScreenCaptureWorldModel] Error getting shareable content: \(error)")
            }
        } else {
            print("⚠️ [ScreenCaptureWorldModel] Requires macOS 13.0+")
        }
        
        return SceneState(
            objects: objects,
            relationships: [],
            timestamp: Date(),
            confidence: objects.isEmpty ? 0.0 : 1.0
        )
    }

    public func updateFromPerception(_ landmarks: FaceLandmarks, _ prosody: Prosody) async throws {
        // Ignored for Screen Capture
    }

    public func queryObjects(kind: String) async throws -> [SceneObject] {
        let state = try await getState()
        return state.objects.filter { $0.kind.lowercased() == kind.lowercased() }
    }

    public func getRelationships() async throws -> [SpatialRelationship] {
        return []
    }
}
