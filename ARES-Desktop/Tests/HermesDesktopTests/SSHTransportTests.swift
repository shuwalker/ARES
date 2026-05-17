import Foundation
import Testing

@testable import HermesDesktop

struct SSHTransportTests {
    @Test
    func serviceArgumentsUseControlSocketAndExplicitDestination() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let transport = SSHTransport(paths: makeTestAppPaths(root: root))
        let connection = ConnectionProfile(
            label: "Prod",
            sshAlias: "prod-box",
            sshPort: 2222,
            sshUser: "alice"
        ).updated()

        let arguments = transport.serviceArguments(
            for: connection,
            remoteCommand: "python3 -"
        )

        #expect(arguments.contains("-T"))
        #expect(arguments.contains("-p"))
        #expect(arguments.contains("2222"))
        #expect(arguments.contains("--"))
        #expect(arguments.contains("alice@prod-box"))
        #expect(arguments.contains("python3 -"))
        #expect(arguments.contains("ControlMaster=auto"))
        #expect(arguments.contains("ControlPersist=300"))
        #expect(arguments.contains(where: { $0.hasPrefix("ControlPath=") }))
    }

    @Test
    func shellArgumentsKeepInteractiveTabsOffSharedControlMaster() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let transport = SSHTransport(paths: makeTestAppPaths(root: root))
        let connection = ConnectionProfile(
            label: "Prod",
            sshHost: "example.com",
            sshUser: "alice",
            hermesProfile: "research"
        ).updated()

        let arguments = transport.shellArguments(for: connection)

        #expect(arguments.contains("-tt"))
        #expect(arguments.contains("ControlMaster=no"))
        #expect(arguments.contains("-S"))
        #expect(arguments.contains("none"))
        #expect(arguments.last == connection.remoteShellBootstrapCommand)
    }

    @Test
    func executeUsesInjectedProcessRunner() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = RecordingSSHProcessRunner(
            result: SSHCommandResult(stdout: "ok", stderr: "", exitCode: 0)
        )
        let transport = SSHTransport(
            paths: makeTestAppPaths(root: root),
            processRunner: runner
        )
        let connection = ConnectionProfile(
            label: "Prod",
            sshHost: "example.com",
            sshUser: "alice"
        ).updated()

        let stdin = Data("payload".utf8)
        let result = try await transport.execute(
            on: connection,
            remoteCommand: "printf ok",
            standardInput: stdin,
            allocateTTY: false
        )

        let invocation = try #require(await runner.lastInvocation)
        #expect(invocation.executableURL.path == "/usr/bin/ssh")
        #expect(invocation.arguments.contains("alice@example.com"))
        #expect(invocation.arguments.contains("printf ok"))
        #expect(invocation.standardInput == stdin)
        #expect(result.stdout == "ok")
    }

    @Test
    func remoteFailureMentionsNonInteractivePythonPath() {
        let transport = SSHTransport(paths: AppPaths())
        let connection = ConnectionProfile(
            label: "Prod",
            sshHost: "example.com"
        ).updated()

        let message = transport.describeRemoteFailure(
            stdout: "",
            stderr: "zsh:1: command not found: python3",
            exitCode: 127,
            connection: connection
        )

        #expect(message.contains("non-interactive SSH shell PATH"))
        #expect(message.contains("python3"))
    }

    @Test
    func executeJSONFlagsShellStartupNoiseBeforeJSON() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let runner = RecordingSSHProcessRunner(
            result: SSHCommandResult(
                stdout: "Welcome to staging\n{\"ok\": true}",
                stderr: "",
                exitCode: 0
            )
        )
        let transport = SSHTransport(
            paths: makeTestAppPaths(root: root),
            processRunner: runner
        )
        let connection = ConnectionProfile(
            label: "Prod",
            sshHost: "example.com"
        ).updated()

        do {
            let _: OKResponse = try await transport.executeJSON(
                on: connection,
                pythonScript: "print('noop')",
                responseType: OKResponse.self
            )
            Issue.record("Expected JSON decoding to fail")
        } catch let error as SSHTransportError {
            guard case .invalidResponse(let message) = error else {
                Issue.record("Expected invalidResponse, got \(error)")
                return
            }
            #expect(message.contains("shell startup file printed text"))
            #expect(message.contains("Welcome to staging"))
        }
    }
}

private struct OKResponse: Decodable {
    let ok: Bool
}

private struct SSHProcessInvocation {
    let executableURL: URL
    let arguments: [String]
    let standardInput: Data?
}

private actor RecordingSSHProcessRunner: SSHProcessRunning {
    private let result: SSHCommandResult
    private(set) var lastInvocation: SSHProcessInvocation?

    init(result: SSHCommandResult) {
        self.result = result
    }

    func run(
        executableURL: URL,
        arguments: [String],
        standardInput: Data?
    ) async throws -> SSHCommandResult {
        lastInvocation = SSHProcessInvocation(
            executableURL: executableURL,
            arguments: arguments,
            standardInput: standardInput
        )
        return result
    }
}
