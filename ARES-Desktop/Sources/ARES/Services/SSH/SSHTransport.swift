import Foundation
import ARESCore

/// SSH transport for remote connections via /usr/bin/ssh.
/// Requires a running SSH agent or key-based auth. If SSH binary is missing
/// or the connection cannot be established, methods throw descriptive errors.

// MARK: - SSHTransportError

enum SSHTransportError: LocalizedError {
    case invalidResponse(String)
    case remoteFailure(String)
    case launchFailure(String)
    case sshUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message): return message
        case .remoteFailure(let message): return message
        case .launchFailure(let message): return message
        case .sshUnavailable(let message): return message
        }
    }
}

// MARK: - SSHTransportResult

struct SSHTransportResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

// MARK: - SSHTransport

final class SSHTransport: @unchecked Sendable {
    let paths: AppPaths
    private let sshBinary = "/usr/bin/ssh"

    init(paths: AppPaths) {
        self.paths = paths
    }

    // MARK: - Execute (raw command)

    func execute(
        on connection: ConnectionProfile,
        remoteCommand: String,
        standardInput: Data? = nil,
        allocateTTY: Bool = false
    ) async throws -> SSHTransportResult {
        guard FileManager.default.isExecutableFile(atPath: sshBinary) else {
            throw SSHTransportError.sshUnavailable("SSH binary not found at \(sshBinary). Install OpenSSH or enable Remote Login in Sharing preferences.")
        }

        let args = shellArguments(for: connection, startupCommandLine: remoteCommand)
        return try await runProcess(arguments: args, standardInput: standardInput)
    }

    // MARK: - Execute JSON (typed response)

    func executeJSON<T: Decodable>(
        on connection: ConnectionProfile,
        pythonScript: String,
        responseType: T.Type
    ) async throws -> T {
        let pythonCommand = "python3 \(pythonScript)"
        let result = try await execute(on: connection, remoteCommand: pythonCommand)

        guard result.exitCode == 0 else {
            throw SSHTransportError.remoteFailure("Python script exited with code \(result.exitCode): \(result.stderr)")
        }

        let data = Data(result.stdout.utf8)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SSHTransportError.invalidResponse("Failed to decode JSON response: \(error.localizedDescription)")
        }
    }

    // MARK: - Validation helpers

    func validateSuccessfulExit(
        _ result: SSHTransportResult,
        for connection: ConnectionProfile
    ) throws {
        if result.exitCode != 0 {
            throw SSHTransportError.remoteFailure("Process failed with exit code \(result.exitCode)")
        }
    }

    // MARK: - Terminal / shell arguments

    func shellArguments(
        for connection: ConnectionProfile,
        startupCommandLine: String? = nil
    ) -> [String] {
        var args = [sshBinary]

        // Key-based auth: disable password prompts, use default keys
        args += ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new"]

        if let port = connection.sshPort, port != 22 {
            args += ["-p", "\(port)"]
        }

        // Build the remote target
        let target: String
        if let user = connection.trimmedUser {
            target = "\(user)@\(connection.effectiveTarget)"
        } else {
            target = connection.effectiveTarget
        }
        args.append(target)

        // Append the command (or interactive shell if nil)
        if let cmd = startupCommandLine {
            args.append(cmd)
        }

        return args
    }

    // MARK: - Service arguments (for Process-based SSH)

    func serviceArguments(
        for connection: ConnectionProfile,
        remoteCommand: String,
        allocateTTY: Bool = false
    ) -> [String] {
        var args = [sshBinary]
        args += ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new"]

        if let port = connection.sshPort, port != 22 {
            args += ["-p", "\(port)"]
        }

        let target: String
        if let user = connection.trimmedUser {
            target = "\(user)@\(connection.effectiveTarget)"
        } else {
            target = connection.effectiveTarget
        }
        args.append(target)
        args.append(remoteCommand)

        return args
    }

    // MARK: - Diagnostics

    func describeRemoteFailure(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        connection: ConnectionProfile
    ) -> String {
        if exitCode == 255 {
            return "SSH connection failed to \(connection.effectiveTarget). Check that Remote Login is enabled, keys are configured, and the host is reachable.\nstderr: \(stderr)"
        }
        return "Remote failure: exit \(exitCode)\nstdout: \(stdout)\nstderr: \(stderr)"
    }

    // MARK: - Process runner

    private func runProcess(arguments: [String], standardInput: Data?) async throws -> SSHTransportResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let input = standardInput {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            try process.run()
            if let handle = stdinPipe.fileHandleForWriting as? FileHandle {
                try handle.write(contentsOf: input)
                try handle.close()
            }
        } else {
            try process.run()
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return SSHTransportResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }
}