import Foundation

struct DependencyInstaller {
    func install(_ dep: ARESDependency) async throws {
        switch dep.installMethod {
        case .gitClone(let url, let path):
            try await cloneRepo(url: url, path: path)
        case .brew(let formula):
            try await brewInstall(formula: formula)
        case .manual:
            throw InstallError.manualRequired(dep.name)
        }
    }

    private func cloneRepo(url: String, path: String) async throws {
        let expanded = NSString(string: path).expandingTildeInPath
        let parent = (expanded as NSString).deletingLastPathComponent

        // Create parent directory
        try FileManager.default.createDirectory(
            atPath: parent,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", url, expanded]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try await runWithTimeout(process, seconds: 120)
    }

    private func brewInstall(formula: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        process.arguments = ["install", formula]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try await runWithTimeout(process, seconds: 300)
    }

    private func runWithTimeout(_ process: Process, seconds: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            final class State: @unchecked Sendable {
                var done = false
                var resumed = false
            }
            let state = State()
            let lock = NSLock()
            let semaphore = DispatchSemaphore(value: 0)

            func resumeOnce(_ block: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !state.resumed else { return }
                state.resumed = true
                block()
            }

            process.terminationHandler = { _ in
                state.done = true
                semaphore.signal()
            }

            do {
                try process.run()
            } catch {
                resumeOnce { continuation.resume(throwing: error) }
                return
            }

            DispatchQueue.global().async {
                let result = semaphore.wait(timeout: .now() + .seconds(seconds))
                if result == .timedOut, !state.done {
                    process.terminate()
                }
                if process.terminationStatus == 0 {
                    resumeOnce { continuation.resume() }
                } else {
                    resumeOnce {
                        continuation.resume(
                            throwing: InstallError.processFailed(process.terminationStatus)
                        )
                    }
                }
            }
        }
    }
}

enum InstallError: LocalizedError {
    case manualRequired(String)
    case processFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .manualRequired(let name):
            return "\(name) requires manual installation."
        case .processFailed(let code):
            return "Installation failed with exit code \(code)."
        }
    }
}
