import Foundation

class Logger {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "ares.logger")
    
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }
    
    init() {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ARES-Mac")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        fileURL = logs.appendingPathComponent("ares-\(formatter.string(from: Date())).log")
    }
    
    func debug(_ msg: String) { write(.debug, msg) }
    func info(_ msg: String) { write(.info, msg) }
    func warn(_ msg: String) { write(.warn, msg) }
    func error(_ msg: String) { write(.error, msg) }
    func thought(_ msg: String) { write(.info, "[THOUGHT] \(msg)") }
    
    private func write(_ level: Level, _ msg: String) {
        queue.async { [fileURL] in
            let formatter = ISO8601DateFormatter()
            let line = "\(formatter.string(from: Date())) [\(level.rawValue)] \(msg)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }
    }
}
