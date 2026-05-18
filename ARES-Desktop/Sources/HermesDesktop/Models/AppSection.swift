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
        case .avatar, .secondBrain, .youtubePipeline, .physicsSim, .plugins: return nil
        }
    }
}