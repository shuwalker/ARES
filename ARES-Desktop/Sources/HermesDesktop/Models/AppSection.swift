import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case connections
    case overview
    case sessions
    case workflows
    case cronjobs
    case kanban
    case files
    case usage
    case skills
    case models
    case config
    case logs
    case keys
    case profiles
    case terminal
    case avatar
    case secondBrain
    case youtubePipeline
    case physicsSim
    case plugins
    case docs
    case chat
    case memory
    case soul
    case tools
    case office
    case analytics
    case jobs
    case mcp
    case swarm
    case conductor
    case operations
    case crewStatus

    var id: String { rawValue }

    var title: String {
        L10n.string(rawTitle)
    }

    private var rawTitle: String {
        switch self {
        case .connections: "Connections"
        case .overview: "Overview"
        case .sessions: "Sessions"
        case .workflows: "Workflows"
        case .cronjobs: "Cron Jobs"
        case .kanban: "Kanban"
        case .files: "Files"
        case .usage: "Usage"
        case .skills: "Skills"
        case .models: "Models"
        case .config: "Config"
        case .logs: "Logs"
        case .keys: "Keys"
        case .profiles: "Profiles"
        case .terminal: "Terminal"
        case .avatar: "Avatar"
        case .secondBrain: "Second Brain"
        case .youtubePipeline: "YouTube"
        case .physicsSim: "Physics"
        case .plugins: "Plugins"
        case .docs: "Documentation"
        case .chat: "Chat"
        case .memory: "Memory"
        case .soul: "Soul"
        case .tools: "Tools"
        case .office: "Office"
        case .analytics: "Analytics"
        case .jobs: "Jobs"
        case .mcp: "MCP"
        case .swarm: "Swarm"
        case .conductor: "Conductor"
        case .operations: "Operations"
        case .crewStatus: "Crew"
        }
    }

    var systemImage: String {
        switch self {
        case .connections: "network"
        case .overview: "waveform.path.ecg"
        case .sessions: "clock.arrow.circlepath"
        case .workflows: "bookmark.square"
        case .cronjobs: "calendar.badge.clock"
        case .kanban: "rectangle.3.group"
        case .files: "doc.text"
        case .usage: "chart.bar.xaxis"
        case .skills: "book.closed"
        case .models: "cpu"
        case .config: "gearshape"
        case .logs: "doc.plaintext"
        case .keys: "key"
        case .profiles: "person.crop.rectangle"
        case .terminal: "terminal"
        case .avatar: "person.crop.circle.badge.checkmark"
        case .secondBrain: "brain"
        case .youtubePipeline: "play.rectangle"
        case .physicsSim: "atom"
        case .plugins: "puzzlepiece"
        case .docs: "book"
        case .chat: "bubble.left.and.bubble.right"
        case .memory: "brain"
        case .soul: "person.text.rectangle"
        case .tools: "wrench.and.screwdriver"
        case .office: "cube.transparent"
        case .analytics: "chart.bar.xaxis"
        case .jobs: "clock.badge.checkmark"
        case .mcp: "server.rack"
        case .swarm: "person.3.fill"
        case .conductor: "wand.and.stars"
        case .operations: "building.2"
        case .crewStatus: "person.badge.shield.checkmark"
        }
    }

    var navigationShortcutKey: KeyEquivalent? {
        switch self {
        case .connections: return "1"
        case .overview: return "2"
        case .sessions: return "3"
        case .workflows: return "4"
        case .cronjobs: return "5"
        case .kanban: return "6"
        case .files: return "7"
        case .usage: return "8"
        case .skills: return "9"
        case .models: return nil
        case .config: return nil
        case .logs: return nil
        case .keys: return nil
        case .profiles: return nil
        case .terminal: return "0"
        case .avatar, .secondBrain, .youtubePipeline, .physicsSim, .plugins, .docs: return nil
        case .chat, .memory, .soul, .tools, .office: return nil
        case .analytics: return nil
        case .jobs, .mcp, .swarm: return nil
        case .conductor, .operations, .crewStatus: return nil
        }
    }
}
