import Foundation

enum ImmersionLevel: String, CaseIterable, Codable {
    case light
    case medium
    case full
    
    var label: String {
        switch self {
        case .light:  return "Desktop"
        case .medium: return "Window"
        case .full:   return "Room"
        }
    }
    
    var icon: String {
        switch self {
        case .light:  return "square.stack.3d.up"
        case .medium: return "rectangle.center.inset.filled"
        case .full:   return "cube.transparent"
        }
    }
    
    var description: String {
        switch self {
        case .light:  return "Sits on top of desktop"
        case .medium: return "Focused agent window"
        case .full:   return "Enter the agent's room"
        }
    }
}