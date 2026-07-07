import Foundation

public enum ARESEnvironment: Sendable {
    
    /// The default directory for ARES data: `~/.hermes`
    public static var defaultHomeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes", isDirectory: true)
    }
    
    /// The directory where companion chat sessions are persisted
    public static var sessionsDirectory: URL {
        defaultHomeDirectory
            .appendingPathComponent("memory", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }
    
    /// The directory where companion skills are stored
    public static var skillsDirectory: URL {
        defaultHomeDirectory
            .appendingPathComponent("skills", isDirectory: true)
    }
    
    /// The directory where the companion memory state is stored
    public static var memoriesDirectory: URL {
        defaultHomeDirectory
            .appendingPathComponent("memories", isDirectory: true)
    }
    
    /// The file path to the companion memory file
    public static var memoryFilePath: URL {
        memoriesDirectory
            .appendingPathComponent("MEMORY.md", isDirectory: false)
    }
    
    /// The directory where the companion state is stored
    public static var stateDirectory: URL {
        defaultHomeDirectory
            .appendingPathComponent("state", isDirectory: true)
    }
    
    /// The file path to the self model file
    public static var selfModelFilePath: URL {
        stateDirectory
            .appendingPathComponent("self_model.md", isDirectory: false)
    }
    
    /// The file path to the kanban database
    public static var kanbanDatabasePath: String {
        "~/.hermes/kanban.db"
    }
    
    /// The file path to the cron jobs database
    public static var cronJobsPath: String {
        "~/.hermes/cron/jobs.json"
    }
    
    /// A helper function to safely resolve a tilde path to an absolute path string
    public static func expandTildeInPath(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }
}
