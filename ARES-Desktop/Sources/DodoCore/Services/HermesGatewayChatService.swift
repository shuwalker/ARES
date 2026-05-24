import Foundation

enum HermesGatewayError: LocalizedError, Equatable, Sendable {
    case notConnected
    case timedOut(String)
    case invalidFrame(String)
    case closed
    case remote(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "The Hermes gateway is not connected."
        case .timedOut(let operation):
            return "\(operation) timed out."
        case .invalidFrame(let details):
            return "Received an invalid gateway frame: \(details)"
        case .closed:
            return "The Hermes gateway session closed."
        case .remote(_, let message):
            return message
        }
    }
}

struct HermesChatBootstrapStatus: Equatable, Sendable {
    var sshConnected = false
    var pythonAvailable = false
    var hermesCLIAvailable = false
    var hermesVersion: String?
    var tuiGatewayAvailable = false
    var canUseNativeChat = false
    var fallbackReason: String?

    var preferredTransportMode: HermesChatTransportMode {
        canUseNativeChat ? .native : .fallback
    }
}

struct HermesGatewayEvent: Identifiable, Hashable, Sendable {
    let id = UUID()
    let type: String
    let sessionID: String?
    let payload: [String: JSONValue]
    let rawLine: String?
}

struct HermesGatewayRPCErrorPayload: Codable, Hashable, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?
}

enum HermesGatewayRequestID: Codable, Hashable, Sendable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported request identifier"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .string(let value):
            return Int(value)
        }
    }
}

private struct HermesGatewayOutgoingRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: [String: JSONValue]
}

private struct HermesGatewayIncomingFrame: Decodable {
    let jsonrpc: String?
    let id: HermesGatewayRequestID?
    let result: JSONValue?
    let error: HermesGatewayRPCErrorPayload?
    let method: String?
    let params: HermesGatewayIncomingEventParams?
}

private struct HermesGatewayIncomingEventParams: Decodable {
    let type: String
    let sessionID: String?
    let payload: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "session_id"
        case payload
    }
}

actor HermesGatewayRPCClient {
    typealias Sender = @Sendable (String) async throws -> Void

    nonisolated let events: AsyncStream<HermesGatewayEvent>

    private let eventContinuation: AsyncStream<HermesGatewayEvent>.Continuation
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var sender: Sender?
    private var nextRequestID = 0
    private var readyPayload: [String: JSONValue]?
    private var readyWaiters: [UUID: CheckedContinuation<[String: JSONValue], Error>] = [:]
    private var readyTimeouts: [UUID: Task<Void, Never>] = [:]
    private var pendingRequests: [Int: CheckedContinuation<JSONValue?, Error>] = [:]
    private var pendingTimeouts: [Int: Task<Void, Never>] = [:]
    private var isClosed = false

    init() {
        let stream = AsyncStream<HermesGatewayEvent>.makeStream()
        events = stream.stream
        eventContinuation = stream.continuation
    }

    func attachSender(_ sender: @escaping Sender) {
        self.sender = sender
    }

    func awaitReady(timeout: TimeInterval = 12) async throws -> [String: JSONValue] {
        if let readyPayload {
            return readyPayload
        }

        let waiterID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            readyWaiters[waiterID] = continuation
            readyTimeouts[waiterID] = Task {
                try? await Task.sleep(nanoseconds: timeout.nanosecondsFromSeconds)
                self.failReadyWaiter(waiterID, error: HermesGatewayError.timedOut("Waiting for gateway.ready"))
            }
        }
    }

    func request(
        method: String,
        params: [String: JSONValue] = [:],
        timeout: TimeInterval = 45
    ) async throws -> JSONValue? {
        guard let sender else {
            throw HermesGatewayError.notConnected
        }
        guard !isClosed else {
            throw HermesGatewayError.closed
        }

        nextRequestID += 1
        let requestID = nextRequestID
        let request = HermesGatewayOutgoingRequest(id: requestID, method: method, params: params)
        let data = try encoder.encode(request)
        guard let line = String(data: data, encoding: .utf8) else {
            throw HermesGatewayError.invalidFrame("Failed to UTF-8 encode request")
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestID] = continuation
            pendingTimeouts[requestID] = Task {
                try? await Task.sleep(nanoseconds: timeout.nanosecondsFromSeconds)
                self.failPendingRequest(
                    requestID,
                    error: HermesGatewayError.timedOut("Gateway request \(method)")
                )
            }

            Task {
                do {
                    try await sender(line)
                } catch {
                    self.failPendingRequest(requestID, error: error)
                }
            }
        }
    }

    func handleStdoutLine(_ line: String) async {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        do {
            let frame = try decoder.decode(HermesGatewayIncomingFrame.self, from: Data(line.utf8))
            if let requestID = frame.id?.intValue {
                pendingTimeouts[requestID]?.cancel()
                pendingTimeouts[requestID] = nil

                guard let continuation = pendingRequests.removeValue(forKey: requestID) else {
                    return
                }

                if let error = frame.error {
                    continuation.resume(throwing: HermesGatewayError.remote(error.code, error.message))
                } else {
                    continuation.resume(returning: frame.result)
                }
                return
            }

            if frame.method == "event", let params = frame.params {
                let event = HermesGatewayEvent(
                    type: params.type,
                    sessionID: params.sessionID,
                    payload: params.payload ?? [:],
                    rawLine: line
                )
                if params.type == "gateway.ready" {
                    readyPayload = params.payload ?? [:]
                    completeReadyWaiters(with: readyPayload ?? [:])
                }
                eventContinuation.yield(event)
                return
            }

            eventContinuation.yield(
                HermesGatewayEvent(
                    type: "gateway.unknown_frame",
                    sessionID: nil,
                    payload: ["line": .string(line)],
                    rawLine: line
                )
            )
        } catch {
            eventContinuation.yield(
                HermesGatewayEvent(
                    type: "gateway.parse_error",
                    sessionID: nil,
                    payload: [
                        "line": .string(line),
                        "error": .string(error.localizedDescription)
                    ],
                    rawLine: line
                )
            )
        }
    }

    func handleStderrText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        eventContinuation.yield(
            HermesGatewayEvent(
                type: "gateway.stderr",
                sessionID: nil,
                payload: ["text": .string(trimmed)],
                rawLine: trimmed
            )
        )
    }

    func finish(throwing error: Error? = nil) {
        guard !isClosed else { return }
        isClosed = true

        for (_, timeoutTask) in pendingTimeouts {
            timeoutTask.cancel()
        }
        pendingTimeouts.removeAll()

        for (_, timeoutTask) in readyTimeouts {
            timeoutTask.cancel()
        }
        readyTimeouts.removeAll()

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: error ?? HermesGatewayError.closed)
        }
        pendingRequests.removeAll()

        for (_, continuation) in readyWaiters {
            continuation.resume(throwing: error ?? HermesGatewayError.closed)
        }
        readyWaiters.removeAll()

        eventContinuation.yield(
            HermesGatewayEvent(
                type: "gateway.closed",
                sessionID: nil,
                payload: error.map { ["error": .string($0.localizedDescription)] } ?? [:],
                rawLine: nil
            )
        )
        eventContinuation.finish()
    }

    private func completeReadyWaiters(with payload: [String: JSONValue]) {
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for (key, continuation) in waiters {
            readyTimeouts[key]?.cancel()
            readyTimeouts.removeValue(forKey: key)
            continuation.resume(returning: payload)
        }
    }

    private func failPendingRequest(_ requestID: Int, error: Error) {
        pendingTimeouts[requestID]?.cancel()
        pendingTimeouts[requestID] = nil
        guard let continuation = pendingRequests.removeValue(forKey: requestID) else {
            return
        }
        continuation.resume(throwing: error)
    }

    private func failReadyWaiter(_ waiterID: UUID, error: Error) {
        readyTimeouts[waiterID]?.cancel()
        readyTimeouts.removeValue(forKey: waiterID)
        guard let continuation = readyWaiters.removeValue(forKey: waiterID) else {
            return
        }
        continuation.resume(throwing: error)
    }
}

actor HermesGatewayChatService {
    nonisolated let events: AsyncStream<HermesGatewayEvent>

    private let connection: ConnectionProfile
    private let sshTransport: SSHTransport
    private let gatewayCommand: String
    private let rpcClient: HermesGatewayRPCClient

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var runnerTask: Task<Void, Never>?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var isClosed = false

    init(
        connection: ConnectionProfile,
        sshTransport: SSHTransport,
        gatewayCommand: String = "python3 -m tui_gateway.entry"
    ) {
        self.connection = connection
        self.sshTransport = sshTransport
        self.gatewayCommand = gatewayCommand
        let rpcClient = HermesGatewayRPCClient()
        self.rpcClient = rpcClient
        events = rpcClient.events
    }

    func start(timeout: TimeInterval = 12) async throws {
        if runnerTask == nil {
            runnerTask = Task {
                await self.runGatewayLoop()
            }
        }

        await rpcClient.attachSender { line in
            try await self.writeLine(line)
        }

        _ = try await rpcClient.awaitReady(timeout: timeout)
    }

    func request(
        method: String,
        params: [String: JSONValue] = [:],
        timeout: TimeInterval = 45
    ) async throws -> JSONValue? {
        try await rpcClient.request(method: method, params: params, timeout: timeout)
    }

    func close() async {
        guard !isClosed else { return }
        isClosed = true

        process?.terminate()
        stdinHandle?.closeFile()
        stdinHandle = nil
        process = nil
        runnerTask?.cancel()
        runnerTask = nil
        await rpcClient.finish()
    }

    private func runGatewayLoop() async {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let stdinHandle = stdinPipe.fileHandleForWriting

        self.process = process
        self.stdinHandle = stdinHandle

        stdoutHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            Task {
                await self.handleStdoutChunk(chunk)
            }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            Task {
                await self.handleStderrChunk(chunk)
            }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            }
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = sshTransport.serviceArguments(
            for: connection,
            remoteCommand: connection.remoteServiceCommand(gatewayCommand),
            allocateTTY: false
        )
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            let exitCode = try await run(process)
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            await flushStdoutRemainder()
            self.process = nil
            self.stdinHandle = nil
            runnerTask = nil

            if isClosed || Task.isCancelled {
                return
            }

            if exitCode == 0 {
                await rpcClient.finish()
            } else {
                let message = sshTransport.describeRemoteFailure(
                    stdout: stdoutBuffer,
                    stderr: stderrBuffer,
                    exitCode: exitCode,
                    connection: connection
                )
                await rpcClient.finish(
                    throwing: SSHTransportError.remoteFailure(message)
                )
            }
        } catch {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            self.process = nil
            self.stdinHandle = nil
            runnerTask = nil
            if isClosed || Task.isCancelled {
                return
            }
            await rpcClient.finish(throwing: error)
        }
    }

    private func run(_ process: Process) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(
                    throwing: SSHTransportError.launchFailure(error.localizedDescription)
                )
            }
        }
    }

    private func writeLine(_ line: String) async throws {
        guard let stdinHandle else {
            throw HermesGatewayError.notConnected
        }

        guard let data = "\(line)\n".data(using: .utf8) else {
            throw HermesGatewayError.invalidFrame("Failed to UTF-8 encode request")
        }

        try stdinHandle.write(contentsOf: data)
    }

    private func handleStdoutChunk(_ data: Data) async {
        guard !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        stdoutBuffer.append(chunk)

        while let newlineRange = stdoutBuffer.range(of: "\n") {
            let line = String(stdoutBuffer[..<newlineRange.lowerBound])
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex ... newlineRange.lowerBound)
            await rpcClient.handleStdoutLine(line)
        }
    }

    private func flushStdoutRemainder() async {
        let remainder = stdoutBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        stdoutBuffer.removeAll(keepingCapacity: false)
        guard !remainder.isEmpty else { return }
        await rpcClient.handleStdoutLine(remainder)
    }

    private func handleStderrChunk(_ data: Data) async {
        guard !data.isEmpty else { return }
        let text = String(decoding: data, as: UTF8.self)
        stderrBuffer.append(text)
        trimBuffer(&stderrBuffer)
        await rpcClient.handleStderrText(text)
    }

    private func trimBuffer(_ text: inout String, limit: Int = 12_000) {
        guard text.count > limit else { return }
        text = String(text.suffix(limit))
    }
}

extension SSHTransport {
    func probeNativeChatAvailability(on connection: ConnectionProfile) async -> HermesChatBootstrapStatus {
        var status = HermesChatBootstrapStatus()

        do {
            let probe = try await execute(
                on: connection,
                remoteCommand: connection.remoteServiceCommand("printf '__hermes_ssh_ok__'"),
                allocateTTY: false
            )
            status.sshConnected = probe.stdout.contains("__hermes_ssh_ok__")
        } catch {
            status.fallbackReason = error.localizedDescription
            return status
        }

        do {
            let pythonProbe = try await execute(
                on: connection,
                remoteCommand: connection.remoteServiceCommand(
                    "if command -v python3 >/dev/null 2>&1; then printf '1'; else printf '0'; fi"
                ),
                allocateTTY: false
            )
            status.pythonAvailable = pythonProbe.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        } catch {
            status.fallbackReason = error.localizedDescription
        }

        do {
            let versionResult = try await execute(
                on: connection,
                remoteCommand: connection.remoteServiceCommand(
                    connection.remoteHermesCommandLine(arguments: ["--version"])
                ),
                allocateTTY: false
            )
            if versionResult.exitCode == 0 {
                status.hermesCLIAvailable = true
                let version = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                status.hermesVersion = version.isEmpty ? nil : version
            }
        } catch {
            if status.fallbackReason == nil {
                status.fallbackReason = error.localizedDescription
            }
        }

        if status.pythonAvailable {
            do {
                let gatewayProbe = try await execute(
                    on: connection,
                    remoteCommand: connection.remoteServiceCommand(
                        """
                        python3 - <<'PY'
                        import importlib.util
                        print("1" if importlib.util.find_spec("tui_gateway.entry") else "0")
                        PY
                        """
                    ),
                    allocateTTY: false
                )
                status.tuiGatewayAvailable = gatewayProbe.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
            } catch {
                if status.fallbackReason == nil {
                    status.fallbackReason = error.localizedDescription
                }
            }
        }

        status.canUseNativeChat =
            status.sshConnected &&
            status.pythonAvailable &&
            status.hermesCLIAvailable &&
            status.tuiGatewayAvailable

        if status.fallbackReason == nil && !status.canUseNativeChat {
            if !status.pythonAvailable {
                status.fallbackReason = "python3 is not available on the remote host."
            } else if !status.hermesCLIAvailable {
                status.fallbackReason = "Hermes CLI is not available on the remote host."
            } else if !status.tuiGatewayAvailable {
                status.fallbackReason = "The Hermes TUI gateway is not importable on the remote host."
            }
        }

        return status
    }
}

extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            switch value.lowercased() {
            case "true", "1", "yes", "y":
                return true
            case "false", "0", "no", "n":
                return false
            default:
                return nil
            }
        case .int(let value):
            return value != 0
        case .number(let value):
            return value != 0
        default:
            return nil
        }
    }
}

private extension TimeInterval {
    var nanosecondsFromSeconds: UInt64 {
        UInt64((self * 1_000_000_000).rounded())
    }
}
