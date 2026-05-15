import Foundation

/// Two-position immersion slider controlling how the human relates to ARES.
///
/// **Manual** — ARES is a tool. The human drives; ARES responds.
///   Traditional software/CLI/framework pattern. Sidebar, terminal, sessions,
///   skill inspector — full operator dashboard.
///
/// **Avatar Twin** — ARES is a person. Autonomous, persistent, socially present.
///   The face fills the screen. Voice-first interaction. Minimal UI chrome.
///   The human talks; ARES acts.
enum ImmersionLevel: String, CaseIterable, Codable {
    case manual
    case avatarTwin

    var label: String {
        switch self {
        case .manual:     return "Manual"
        case .avatarTwin:  return "Avatar Twin"
        }
    }

    var icon: String {
        switch self {
        case .manual:     return "terminal"
        case .avatarTwin:  return "person.crop.circle"
        }
    }

    var description: String {
        switch self {
        case .manual:     return "AI as tool — you drive, ARES responds"
        case .avatarTwin:  return "AI as person — autonomous, persistent, socially present"
        }
    }

    /// In manual mode, the operator dashboard (sidebar, tools) is visible.
    /// In avatar twin mode, only the face and voice remain.
    var showsOperatorDashboard: Bool {
        self == .manual
    }

    /// Avatar twin mode uses the full-screen face and prioritizes voice.
    var isFullScreen: Bool {
        self == .avatarTwin
    }
}