import Foundation

/// Manages an SSH local port-forward tunnel for a single connection.
///
/// Spawns:
///   ssh -N -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30
///        -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes
///        -L localPort:127.0.0.1:9119
///        [user@]host [-p sshPort]
///
/// Then polls localhost:localPort every 400 ms up to 10 seconds for the port to open.
final class SSHTunnelService: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?
    private var _localPort: Int?

    /// Thread-safe synchronous access
    private func withLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }

    /// The forwarded local port, or nil if no tunnel is active.
    var localPort: Int? {
        withLock { _localPort }
    }
    // MARK: - Public API

    /// Starts an SSH local port-forward tunnel for the given connection profile.
    ///
    /// Only acts when `connection.transportKind == .ssh`. Picks a free local port
    /// starting at 19119, spawns the tunnel process, and polls until the port is
    /// reachable (up to 10 seconds).
    ///
    /// - Throws: If no free port can be found, if the SSH process fails to launch,
    ///   or if the port never becomes reachable within the timeout.
    func start(connection: ConnectionProfile) async throws {
        guard connection.transportKind == .ssh else { return }

        // Stop any existing tunnel first.
        stop()

        let port = try findFreePort(starting: 19119, maxTries: 10)
        let arguments = tunnelArguments(for: connection, localPort: port)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        proc.arguments = arguments
        // Discard output — tunnel runs silently in background.
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        try proc.run()

        withLock {
            _process = proc
            _localPort = port
        }

        // Poll until the port is open or timeout.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if isPortOpen(port) { return }
            try await Task.sleep(for: .milliseconds(400))
        }

        // Final check after loop.
        if isPortOpen(port) { return }

        // Tunnel did not become ready in time — clean up.
        stop()
        throw SSHTunnelError.tunnelNotReady(port)
    }

    /// Terminates the active tunnel process and clears state.
    func stop() {
        lock.lock()
        let proc = _process
        _process = nil
        _localPort = nil
        lock.unlock()

        guard let proc else { return }
        proc.terminate()
        // Reap the child process on a background thread so we never block the
        // caller (which may be on the main actor) and avoid leaving a zombie.
        Task.detached { proc.waitUntilExit() }
    }

    // MARK: - Private helpers

    private func tunnelArguments(for connection: ConnectionProfile, localPort: Int) -> [String] {
        var arguments: [String] = [
            "-N",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes",
            "-L", "\(localPort):127.0.0.1:9119"
        ]

        if let port = connection.resolvedPort {
            arguments.append(contentsOf: ["-p", String(port)])
        }

        arguments.append("--")
        let target = connection.effectiveTarget
        let dest = connection.trimmedUser.map { "\($0)@\(target)" } ?? target
        arguments.append(dest)

        return arguments
    }

    /// Attempts to connect a TCP socket to `127.0.0.1:port`.
    /// Returns `true` if the connection succeeds (port is open / tunnel is up).
    /// Returns `false` if the connection is refused or fails.
    private func isPortOpen(_ port: Int) -> Bool {
        let sockfd = socket(AF_INET, SOCK_STREAM, 0)
        guard sockfd >= 0 else { return false }
        defer { close(sockfd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        // 127.0.0.1 expressed as a big-endian network-order UInt32.
        addr.sin_addr.s_addr = UInt32(0x7F000001).bigEndian

        // Use a short connect timeout via SO_SNDTIMEO.
        var tv = timeval(tv_sec: 0, tv_usec: 300_000) // 300 ms
        setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sockfd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }

    /// Finds a free local port by checking whether a port is currently in use.
    /// A port is considered free if `connect()` refuses (i.e., nothing is listening).
    private func findFreePort(starting: Int, maxTries: Int) throws -> Int {
        for offset in 0 ..< maxTries {
            let port = starting + offset
            if !isPortOpen(port) {
                return port
            }
        }
        throw SSHTunnelError.noFreePort(starting: starting, tried: maxTries)
    }
}

// MARK: - Errors

enum SSHTunnelError: LocalizedError {
    case noFreePort(starting: Int, tried: Int)
    case tunnelNotReady(Int)

    var errorDescription: String? {
        switch self {
        case .noFreePort(let start, let tried):
            return "Could not find a free local port in range \(start)–\(start + tried - 1) for the SSH dashboard tunnel."
        case .tunnelNotReady(let port):
            return "The SSH dashboard tunnel did not become ready on port \(port) within 10 seconds."
        }
    }
}
