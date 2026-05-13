import Foundation

enum AgentState: String, CaseIterable, Codable {
    case idle
    case awakened
    case listening
    case thinking
    case speaking
    case sleeping
    
    var displayName: String {
        rawValue.capitalized
    }
    
    var stateColor: String {
        switch self {
        case .idle:      return "blue"
        case .awakened:  return "cyan"
        case .listening: return "green"
        case .thinking:  return "orange"
        case .speaking:  return "purple"
        case .sleeping:  return "gray"
        }
    }
}