import SwiftUI

/// Sidebar pages for the operator dashboard (Manual mode only).
///
/// In Avatar Twin mode, the sidebar is hidden entirely — only the face,
/// voice, and chat remain. These pages represent the "AI as tool" paradigm:
/// the human has full control over ARES's configuration, history, and tools.
enum DashboardPage: String, CaseIterable {
    case chat
    case orchestration
    case tasks
    case memory
    case feeds
    case activity
    case avatar
    case sessions
    case skills
    case cron
    case persona
    case config
    case logs

    var icon: String {
        switch self {
        case .chat:           return "bubble.left.and.bubble.right"
        case .orchestration:  return "arrow.triangle.2.circlepath"
        case .tasks:          return "bolt.horizontal.fill"
        case .memory:         return "brain.head.profile"
        case .feeds:          return "square.grid.2x2"
        case .activity:       return "timeline.view"
        case .avatar:         return "person.crop.rectangle"
        case .sessions:       return "clock.arrow.circlepath"
        case .skills:         return "wrench.and.screwdriver"
        case .cron:           return "timer"
        case .persona:        return "person.fill.questionmark"
        case .config:         return "gearshape"
        case .logs:           return "text.badge.star"
        }
    }

    var label: String {
        switch self {
        case .chat:           return "Chat"
        case .orchestration:  return "Live"
        case .tasks:          return "Tasks"
        case .memory:         return "Memory"
        case .feeds:          return "Feeds"
        case .activity:       return "Activity"
        case .avatar:         return "Avatar"
        case .sessions:       return "Sessions"
        case .skills:         return "Skills"
        case .cron:           return "Cron"
        case .persona:        return "Persona"
        case .config:         return "Config"
        case .logs:           return "Logs"
        }
    }
}