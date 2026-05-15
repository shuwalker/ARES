import Foundation

enum AvatarExpression: String, CaseIterable, Codable {
    case neutral
    case happy
    case curious
    case thinking
    case surprised
    case concerned
    case excited
    case sleepy
    
    /// Numeric value passed to Metal shader as the expression uniform
    var floatValue: Float {
        switch self {
        case .neutral:   return 0.0
        case .happy:     return 1.0
        case .curious:   return 2.0
        case .thinking:  return 3.0
        case .surprised: return 4.0
        case .concerned: return 5.0
        case .excited:   return 6.0
        case .sleepy:    return 7.0
        }
    }
    
    var displayName: String {
        rawValue.capitalized
    }

    /// SF Symbol for the configurator expression pills
    var icon: String {
        switch self {
        case .neutral:   return "face.dashed"
        case .happy:     return "face.smiling"
        case .curious:   return "eye"
        case .thinking:  return "brain"
        case .surprised: return "exclamationmark.face"
        case .concerned: return "face.cloudish"
        case .excited:   return "star"
        case .sleepy:    return "moon.zzz"
        }
    }
}