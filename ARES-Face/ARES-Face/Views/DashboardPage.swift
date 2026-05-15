import SwiftUI

/// Sidebar pages for the operator dashboard (Manual mode only).
///
/// In Avatar Twin mode, the sidebar is hidden entirely — only the face,
/// voice, and chat remain. These pages represent the "AI as tool" paradigm:
/// the human has full control over ARES's configuration, history, and tools.
///
/// Grouped like Hermes Web UI:
///   - Conversation: Chat, Sessions
///   - Tools: Tasks, Cron, Skills
///   - System: Config, Logs, Memory
enum DashboardPage: String, CaseIterable, Identifiable {
    case chat
    case sessions
    case tasks
    case cron
    case skills
    case config
    case logs
    case memory

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chat:      return "bubble.left.and.bubble.right.fill"
        case .sessions:  return "clock.arrow.circlepath"
        case .tasks:     return "bolt.horizontal.fill"
        case .cron:      return "timer"
        case .skills:    return "wrench.and.screwdriver.fill"
        case .config:    return "gearshape.2.fill"
        case .logs:      return "text.badge.star"
        case .memory:    return "brain.head.profile"
        }
    }

    var label: String {
        switch self {
        case .chat:      return "Chat"
        case .sessions:  return "Sessions"
        case .tasks:     return "Tasks"
        case .cron:      return "Cron"
        case .skills:    return "Skills"
        case .config:    return "Config"
        case .logs:      return "Logs"
        case .memory:    return "Memory"
        }
    }

    var group: SidebarGroup {
        switch self {
        case .chat, .sessions:
            return .conversation
        case .tasks, .cron, .skills:
            return .tools
        case .config, .logs, .memory:
            return .system
        }
    }
}

enum SidebarGroup: String, CaseIterable {
    case conversation = "Conversation"
    case tools = "Tools"
    case system = "System"

    var pages: [DashboardPage] {
        DashboardPage.allCases.filter { $0.group == self }
    }
}
