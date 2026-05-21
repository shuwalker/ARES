import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    // ── System ────────────────────────────────
    case connections
    case overview
    case terminal
    case config
    case logs

    // ── AI & Models ───────────────────────────
    case chat
    case models
    case profiles
    case keys
    case memory
    case skills
    case avatar

    // ── Orchestration ─────────────────────────
    case sessions
    case workflows
    case cronjobs
    case kanban
    case swarm
    case conductor
    case operations
    case crewStatus
    case jobs

    // ── Data & Tools ──────────────────────────
    case files
    case mcp
    case plugins
    case tools
    case office
    case analytics
    case usage

    // ── Coming Soon ───────────────────────────
    case secondBrain
    case youtubePipeline
    case physicsSim
    case soul
    case docs

    var id: String { rawValue }

    var title: String {
        L10n.string(rawTitle)
    }

    private var rawTitle: String {
        switch self {
        case .connections: "Connections"
        case .overview: "Overview"
        case .terminal: "Terminal"
        case .config: "Config"
        case .logs: "Logs"
        case .chat: "Chat"
        case .models: "Models"
        case .profiles: "Profiles"
        case .keys: "Keys"
        case .memory: "Memory"
        case .skills: "Skills"
        case .avatar: "Avatar"
        case .sessions: "Sessions"
        case .workflows: "Workflows"
        case .cronjobs: "Cron Jobs"
        case .kanban: "Kanban"
        case .swarm: "Swarm"
        case .conductor: "Conductor"
        case .operations: "Operations"
        case .crewStatus: "Crew"
        case .jobs: "Jobs"
        case .files: "Files"
        case .mcp: "MCP"
        case .plugins: "Plugins"
        case .tools: "Tools"
        case .office: "Office"
        case .analytics: "Analytics"
        case .usage: "Usage"
        case .secondBrain: "Second Brain"
        case .youtubePipeline: "YouTube"
        case .physicsSim: "Physics"
        case .soul: "Soul"
        case .docs: "Documentation"
        }
    }

    var systemImage: String {
        switch self {
        case .connections: "network"
        case .overview: "waveform.path.ecg"
        case .terminal: "terminal"
        case .config: "gearshape"
        case .logs: "doc.plaintext"
        case .chat: "bubble.left.and.bubble.right"
        case .models: "cpu"
        case .profiles: "person.crop.rectangle"
        case .keys: "key"
        case .memory: "brain"
        case .skills: "book.closed"
        case .avatar: "person.crop.circle.badge.checkmark"
        case .sessions: "clock.arrow.circlepath"
        case .workflows: "bookmark.square"
        case .cronjobs: "calendar.badge.clock"
        case .kanban: "rectangle.3.group"
        case .swarm: "person.3.fill"
        case .conductor: "wand.and.stars"
        case .operations: "building.2"
        case .crewStatus: "person.badge.shield.checkmark"
        case .jobs: "clock.badge.checkmark"
        case .files: "doc.text"
        case .mcp: "server.rack"
        case .plugins: "puzzlepiece"
        case .tools: "wrench.and.screwdriver"
        case .office: "cube.transparent"
        case .analytics: "chart.bar.xaxis"
        case .usage: "chart.bar.xaxis"
        case .secondBrain: "brain"
        case .youtubePipeline: "play.rectangle"
        case .physicsSim: "atom"
        case .soul: "person.text.rectangle"
        case .docs: "book"
        }
    }

    /// Returns `true` for sections that are functional without a network connection.
    var isAvailableOffline: Bool {
        switch self {
        case .connections, .config, .workflows, .profiles, .physicsSim, .docs:
            return true
        default:
            return false
        }
    }

    /// Non-numeric keyboard shortcut for sidebar navigation.
    var navigationShortcutKey: KeyEquivalent? {
        switch self {
        case .terminal: return "0"
        default: return nil
        }
    }

    // ── Grouping ──────────────────────────────

    var group: SectionGroup {
        switch self {
        case .connections, .overview, .terminal, .config, .logs:
            return .system
        case .chat, .models, .profiles, .keys, .skills, .avatar:
            return .aiModels
        case .sessions, .workflows, .cronjobs:
            return .orchestration
        case .files, .usage:
            return .dataTools
        // ── Coming Soon (non-functional / no backend) ──
        case .kanban, .swarm, .conductor, .operations, .crewStatus, .jobs,
             .mcp, .plugins, .memory, .tools, .office, .analytics,
             .secondBrain, .youtubePipeline, .physicsSim, .soul, .docs:
            return .comingSoon
        }
    }

    var status: SectionStatus {
        switch self {
        case .kanban, .swarm, .conductor, .operations, .crewStatus, .jobs,
             .mcp, .plugins, .memory, .tools, .office, .analytics,
             .secondBrain, .youtubePipeline, .physicsSim, .soul, .docs:
            return .comingSoon
        default:
            return .live
        }
    }
}

// ── Grouping Types ──────────────────────────────

enum SectionGroup: String, CaseIterable, Identifiable {
    case system
    case aiModels
    case orchestration
    case dataTools
    case comingSoon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .aiModels: return "AI & Models"
        case .orchestration: return "Orchestration"
        case .dataTools: return "Data & Tools"
        case .comingSoon: return "Coming Soon"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "gearshape.2"
        case .aiModels: return "brain.head.profile"
        case .orchestration: return "square.grid.3x3.topleft.filled"
        case .dataTools: return "cylinder.split.1x2"
        case .comingSoon: return "hourglass"
        }
    }

    /// Ordered sections for each group
    static func sections(in group: SectionGroup) -> [AppSection] {
        AppSection.allCases.filter { $0.group == group }
    }
}

enum SectionStatus {
    case live
    case comingSoon
}
