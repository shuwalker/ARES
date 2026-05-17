import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case connections
    case overview
    case files
    case sessions
    case workflows
    case cronjobs
    case kanban
    case usage
    case skills
    case terminal
    case avatar
    case secondBrain
    case youtubePipeline
    case physicsSim

    var id: String { rawValue }

    var title: String {
        L10n.string(rawTitle)
    }

    private var rawTitle: String {
        switch self {
        case .connections:
            "Connections"
        case .overview:
            "Overview"
        case .files:
            "Files"
        case .sessions:
            "Sessions"
        case .workflows:
            "Workflows"
        case .cronjobs:
            "Cron Jobs"
        case .kanban:
            "Kanban"
        case .usage:
            "Usage"
        case .skills:
            "Skills"
        case .terminal:
            "Terminal"
        case .avatar:
            "Avatar"
        case .secondBrain:
            "Second Brain"
        case .youtubePipeline:
            "YouTube"
        case .physicsSim:
            "Physics"
        }
    }

    var systemImage: String {
        switch self {
        case .connections:
            "network"
        case .overview:
            "waveform.path.ecg"
        case .files:
            "doc.text"
        case .sessions:
            "clock.arrow.circlepath"
        case .workflows:
            "bookmark.square"
        case .cronjobs:
            "calendar.badge.clock"
        case .kanban:
            "rectangle.3.group"
        case .usage:
            "chart.bar.xaxis"
        case .skills:
            "book.closed"
        case .terminal:
            "terminal"
        case .avatar:
            "person.crop.circle.badge.checkmark"
        case .secondBrain:
            "brain"
        case .youtubePipeline:
            "play.rectangle"
        case .physicsSim:
            "atom"
        }
    }

    var navigationShortcutKey: KeyEquivalent? {
        switch self {
        case .connections:
            return "1"
        case .overview:
            return "2"
        case .sessions:
            return "3"
        case .workflows:
            return "4"
        case .cronjobs:
            return "5"
        case .kanban:
            return "6"
        case .files:
            return "7"
        case .usage:
            return "8"
        case .skills:
            return "9"
        case .terminal:
            return "0"
        case .avatar, .secondBrain, .youtubePipeline, .physicsSim:
            return nil
        }
    }
}
