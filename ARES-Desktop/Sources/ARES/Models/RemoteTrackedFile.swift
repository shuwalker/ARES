import Foundation

enum RemoteTrackedFile: String, CaseIterable, Identifiable, Sendable {
    case user
    case memory
    case soul

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user:
            "USER.md"
        case .memory:
            "MEMORY.md"
        case .soul:
            "SOUL.md"
        }
    }

    var fileName: String { title }

    var relativePathFromARESHome: String {
        switch self {
        case .user:
            "memories/USER.md"
        case .memory:
            "memories/MEMORY.md"
        case .soul:
            "SOUL.md"
        }
    }

    func resolvedRemotePath(using paths: RemoteARESPaths?) -> String? {
        guard let paths else { return nil }

        switch self {
        case .user:
            return paths.user
        case .memory:
            return paths.memory
        case .soul:
            return paths.soul
        }
    }
}
