import SwiftUI

enum FaceState: Equatable, CustomStringConvertible {
    case idle
    case awakened
    case listening
    case thinking
    case speaking
    case sleeping
    
    var color: Color {
        switch self {
        case .idle: return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .awakened: return Color(red: 0.3, green: 0.8, blue: 1.0)
        case .listening: return Color(red: 0.4, green: 0.9, blue: 0.5)
        case .thinking: return Color(red: 1.0, green: 0.7, blue: 0.2)
        case .speaking: return Color(red: 0.8, green: 0.4, blue: 1.0)
        case .sleeping: return Color(red: 0.1, green: 0.2, blue: 0.4)
        }
    }
    
    var opacity: Double {
        switch self {
        case .idle: return 0.3
        case .awakened: return 0.6
        case .listening: return 0.7
        case .thinking: return 0.8
        case .speaking: return 0.9
        case .sleeping: return 0.15
        }
    }
    
    var pulseSpeed: Double {
        switch self {
        case .idle: return 1.5
        case .sleeping: return 0.5
        case .thinking: return 3.0
        default: return 2.0
        }
    }
    
    var pulseAmount: Double {
        switch self {
        case .idle: return 3
        case .sleeping: return 2
        case .speaking: return 5
        default: return 4
        }
    }
    
    var pupilOffset: Double {
        switch self {
        case .listening: return 2
        case .thinking: return -2
        case .speaking: return 0
        default: return 0
        }
    }
    
    var description: String {
        switch self {
        case .idle: return "Idle"
        case .awakened: return "Awake"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        case .sleeping: return "Sleeping"
        }
    }
}
