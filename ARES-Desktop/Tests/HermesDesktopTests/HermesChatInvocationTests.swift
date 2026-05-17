import Testing
@testable import HermesDesktop

struct HermesChatInvocationTests {
    @Test
    func resumeInvocationUsesQuietNonInteractiveChat() {
        let invocation = HermesChatInvocation(
            sessionID: "session-123",
            prompt: "Continue from the previous result"
        )

        #expect(invocation.arguments == [
            "--resume",
            "session-123",
            "chat",
            "--quiet",
            "--query",
            "Continue from the previous result"
        ])
    }

    @Test
    func promptIsPassedAsSingleArgument() {
        let prompt = """
        summarize this diff && rm -rf nope
        "quoted" text stays payload, not shell
        """
        let invocation = HermesChatInvocation(sessionID: "abc", prompt: prompt)

        #expect(invocation.arguments.last == prompt)
        #expect(invocation.arguments.count == 6)
    }

    @Test
    func newSessionInvocationOmitsResumeArgument() {
        let invocation = HermesChatInvocation(sessionID: nil, prompt: "Start fresh")

        #expect(invocation.arguments == [
            "chat",
            "--quiet",
            "--query",
            "Start fresh"
        ])
    }

    @Test
    func autoApproveAddsYoloBeforeChatCommand() {
        let invocation = HermesChatInvocation(
            sessionID: "session-123",
            prompt: "Inspect the repo",
            autoApproveCommands: true
        )

        #expect(invocation.arguments == [
            "--resume",
            "session-123",
            "--yolo",
            "chat",
            "--quiet",
            "--query",
            "Inspect the repo"
        ])
    }

    @Test
    func terminalResumeInvocationUsesDefaultHermesCommand() {
        let connection = ConnectionProfile(
            label: "Host",
            sshHost: "example.local"
        )
        let invocation = HermesSessionResumeInvocation(
            sessionID: "20260503_161557_453be2",
            connection: connection
        )

        #expect(invocation.arguments == ["--resume", "20260503_161557_453be2"])
        #expect(invocation.commandLine == "hermes --resume 20260503_161557_453be2")
    }

    @Test
    func terminalResumeInvocationPinsCustomHermesProfile() {
        let connection = ConnectionProfile(
            label: "Host",
            sshHost: "example.local",
            hermesProfile: "researcher"
        )
        let invocation = HermesSessionResumeInvocation(
            sessionID: "debug session's final turn",
            connection: connection
        )

        #expect(invocation.arguments == [
            "--profile",
            "researcher",
            "--resume",
            "debug session's final turn"
        ])
        #expect(invocation.commandLine == "hermes --profile researcher --resume 'debug session'\\''s final turn'")
    }

    @Test
    func terminalResumeInvocationSkipsProfileArgumentForCustomHermesHome() {
        let connection = ConnectionProfile(
            label: "Host",
            sshHost: "example.local",
            hermesProfile: "researcher",
            customHermesHomePath: "~/.hermes-work"
        )
        let invocation = HermesSessionResumeInvocation(
            sessionID: "session-123",
            connection: connection
        )

        #expect(invocation.arguments == ["--resume", "session-123"])
        #expect(invocation.commandLine == "hermes --resume session-123")
        #expect(invocation.startupCommandLine.contains(#"$HERMES_HOME/hermes-agent/venv/bin/hermes"#))
        #expect(invocation.startupCommandLine.contains(#""$HERMES_BIN" --resume session-123"#))
    }
}
