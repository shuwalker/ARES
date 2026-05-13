import SwiftUI

enum DashboardPage: String, CaseIterable {
    case chat, config, models, sessions, skills, cron, logs, analytics

    var icon: String {
        switch self {
        case .chat:      return "bubble.left.and.bubble.right"
        case .config:    return "gearshape"
        case .models:    return "brain"
        case .sessions:  return "clock.arrow.circlepath"
        case .skills:    return "wrench.and.screwdriver"
        case .cron:      return "timer"
        case .logs:      return "text.badge.star"
        case .analytics: return "chart.bar"
        }
    }

    var label: String {
        switch self {
        case .chat:      return "Chat"
        case .config:    return "Config"
        case .models:    return "Models"
        case .sessions:  return "Sessions"
        case .skills:    return "Skills"
        case .cron:      return "Cron"
        case .logs:      return "Logs"
        case .analytics: return "Analytics"
        }
    }
}
