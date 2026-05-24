import Foundation

struct DependencyScanner {
    struct DependencyResult {
        let dependency: ARESDependency
        let status: DependencyStatus
    }

    func scanAll() async -> [DependencyResult] {
        var results: [DependencyResult] = []
        for dep in ARESDependency.allCases {
            let status = await check(dep)
            results.append(DependencyResult(dependency: dep, status: status))
        }
        return results
    }

    private func check(_ dep: ARESDependency) async -> DependencyStatus {
        switch dep {
        case .dodoRepo:
            return checkRepo("~/GitHub/hermes-desktop")
        case .hermesAgent:
            // Hermes Agent = process running + port 9119 (dashboard)
            let proc = runAndCheck("/bin/sh", args: ["-c", "ps -ax | grep -i hermes | grep -v grep"])
            let port = runAndCheck("/usr/sbin/lsof", args: ["-i", ":9119"])
            // If either check passes, consider it installed
            if proc == .installed || port == .installed {
                return .installed
            }
            return .missing
        case .ollama:
            return checkBinary("ollama")
        case .searxng:
            return runAndCheck("/usr/sbin/lsof", args: ["-i", ":8080"])
        }
    }

    private func checkRepo(_ path: String) -> DependencyStatus {
        let expanded = NSString(string: path).expandingTildeInPath
        let packagePath = expanded + "/Package.swift"
        return FileManager.default.fileExists(atPath: packagePath) ? .installed : .missing
    }

    private func checkBinary(_ name: String) -> DependencyStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let semaphore = DispatchSemaphore(value: 0)
        final class CodeBox: @unchecked Sendable { var code: Int32 = 1 }
        let box = CodeBox()
        process.terminationHandler = { p in
            box.code = p.terminationStatus
            semaphore.signal()
        }

        do { try process.run() } catch { return .missing }
        _ = semaphore.wait(timeout: .now() + .seconds(3))

        return box.code == 0 ? .installed : .missing
    }

    /// Runs a command and returns .installed if it produces any stdout (non-empty),
    /// .missing if stdout is empty, .failed on error/timeout.
    private func runAndCheck(_ executable: String, args: [String]) -> DependencyStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var data: Data? }
        let box = Box()

        process.terminationHandler = { p in
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return .failed(error.localizedDescription)
        }

        let result = semaphore.wait(timeout: .now() + .seconds(3))
        if result == .timedOut {
            process.terminate()
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
        }

        guard let data = box.data, !data.isEmpty else {
            return .missing
        }

        return .installed
    }
}
