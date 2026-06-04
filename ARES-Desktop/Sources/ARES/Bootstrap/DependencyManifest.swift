import Foundation
import SwiftUI

// MARK: - ARES Dependency Manifest

enum ARESDependency: String, CaseIterable, Identifiable {
    case hermesAgent
    case ollama
    case searxng

    var id: String { rawValue }

    var name: String {
        switch self {
        case .hermesAgent: return "Hermes Agent"
        case .ollama:      return "Ollama"
        case .searxng:     return "SearXNG"
        }
    }

    var installMethod: InstallMethod {
        switch self {
        case .hermesAgent:
            return .manual(message: "Run hermes setup to install.")
        case .ollama:
            return .brew(formula: "ollama")
        case .searxng:
            return .manual(message: "SearXNG must be configured separately.")
        }
    }
}

enum InstallMethod {
    case gitClone(url: String, path: String)
    case brew(formula: String)
    case manual(message: String)

    var isManual: Bool {
        if case .manual = self { return true }
        return false
    }
}

enum DependencyStatus: Equatable {
    case installed
    case missing
    case checking
    case failed(String)

    var systemImage: String {
        switch self {
        case .installed: return "checkmark.circle.fill"
        case .missing:   return "circle"
        case .checking:  return "arrow.triangle.2.circlepath"
        case .failed:    return "xmark.circle.fill"
        }
    }
}