import Foundation
import ARESCore

struct TerminalWorkspaceContext {
    let activeConnection: ConnectionProfile?
    let activeWorkspaceScopeFingerprint: String?
    let isTerminalSectionActive: Bool
    let terminalTheme: TerminalThemePreference
}
