import Foundation

final class HermesChatService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    // MARK: - Streaming via HTTP SSE

    /// Stream a chat message via the Hermes /v1/chat/completions SSE endpoint.
    /// Returns the full accumulated assistant text once streaming completes.
    func streamMessage(
        _ prompt: String,
        sessionID: String?,
        baseURL: URL,
        thinkingBudgetTokens: Int? = nil,
        fastMode: Bool = false,
        onChunk: @escaping @Sendable (String) -> Void,
        onSessionID: @escaping @Sendable (String) -> Void,
        onToolCall: (@escaping @Sendable (ChatToolCall) -> Void)? = nil,
        onToolCallDone: (@escaping @Sendable (String) -> Void)? = nil,
        onThinkingDelta: (@escaping @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if fastMode {
            request.setValue("true", forHTTPHeaderField: "X-Fast-Mode")
        }

        var bodyObject: [String: Any] = [
            "model": "current",
            "messages": [["role": "user", "content": prompt]],
            "stream": true
        ]
        if let sessionID {
            bodyObject["session_id"] = sessionID
        }
        if let budget = thinkingBudgetTokens {
            bodyObject["thinking"] = ["type": "enabled", "budget_tokens": budget]
        }
        if fastMode {
            bodyObject["fast_mode"] = true
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyObject)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StreamingChatError.invalidResponse
        }

        // Extract session ID from response header if present
        if let headerSessionID = httpResponse.value(forHTTPHeaderField: "x-hermes-session-id") {
            onSessionID(headerSessionID)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line + "\n"
            }
            throw StreamingChatError.httpError(httpResponse.statusCode, errorBody.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var accumulated = ""
        var sessionIDReported = false
        // Accumulate tool call data across chunks: index -> (id, name, arguments)
        var pendingToolCalls: [Int: (id: String, name: String, arguments: String)] = [:]

        for try await line in bytes.lines {
            // Skip empty lines and event: lines
            if line.isEmpty || line.hasPrefix("event:") { continue }

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8) else { continue }

            // Check for extended thinking delta before trying OpenAI-style decoding
            if let onThinkingDelta,
               let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let deltaObj = raw["delta"] as? [String: Any],
               let deltaType = deltaObj["type"] as? String,
               deltaType == "thinking_delta",
               let thinkingText = deltaObj["thinking"] as? String,
               !thinkingText.isEmpty {
                onThinkingDelta(thinkingText)
                continue
            }

            let decoder = JSONDecoder()
            guard let chunk = try? decoder.decode(ChatStreamChunk.self, from: data) else { continue }

            if !sessionIDReported, let sid = chunk.sessionID, !sid.isEmpty {
                sessionIDReported = true
                onSessionID(sid)
            }

            // Process tool call deltas
            for tcDelta in chunk.toolCallDeltas {
                let idx = tcDelta.index ?? 0
                let callID = tcDelta.id ?? ""
                let funcName = tcDelta.function?.name ?? ""
                let funcArgs = tcDelta.function?.arguments ?? ""

                if var existing = pendingToolCalls[idx] {
                    if !funcArgs.isEmpty { existing.arguments += funcArgs }
                    pendingToolCalls[idx] = existing
                } else {
                    let newID = callID.isEmpty ? "tool-\(idx)" : callID
                    pendingToolCalls[idx] = (id: newID, name: funcName, arguments: funcArgs)
                    // Emit a running tool call
                    let toolCall = ChatToolCall(id: newID, name: funcName, input: funcArgs, output: nil, status: .running)
                    onToolCall?(toolCall)
                }
            }

            // When finish_reason indicates tool_calls are complete, mark them done
            if chunk.finishReason == "tool_calls" {
                for (_, tc) in pendingToolCalls {
                    onToolCallDone?(tc.id)
                }
                pendingToolCalls.removeAll()
            }

            let delta = chunk.textDelta
            if !delta.isEmpty {
                accumulated += delta
                onChunk(delta)
            }
        }

        return accumulated
    }

    // MARK: - Blocking SSH chat

    func sendMessage(
        _ prompt: String,
        sessionID: String?,
        connection: ConnectionProfile,
        autoApproveCommands: Bool
    ) async throws -> HermesChatTurnResult {
        let invocation = HermesChatInvocation(
            sessionID: sessionID,
            prompt: prompt,
            autoApproveCommands: autoApproveCommands
        )
        let script = try RemotePythonScript.wrap(
            HermesChatRequest(
                hermesHome: connection.remoteHermesHomePath,
                sessionID: sessionID,
                timeoutSeconds: 1800,
                autoApproveCommands: autoApproveCommands,
                arguments: invocation.arguments
            ),
            body: chatBody
        )

        return try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: HermesChatTurnResult.self
        )
    }

    private var chatBody: String {
        """
        import os
        import selectors
        import shutil
        import subprocess
        import time

        def compact_output(stdout, stderr, exit_code):
            merged = "\\n".join([
                stringify(stderr).strip() if stringify(stderr) else "",
                stringify(stdout).strip() if stringify(stdout) else "",
            ]).strip()
            if not merged:
                return f"Hermes chat exited with code {exit_code}."
            if len(merged) <= 4000:
                return merged
            return merged[-4000:]

        def compact_text(value, limit=12000):
            text = stringify(value)
            if text is None or len(text) <= limit:
                return text
            return text[-limit:]

        def looks_like_approval_request(text):
            lowered = (text or "").lower()
            approval_markers = [
                "approval required",
                "requires confirmation",
                "requires approval",
                "command approval",
                "approve command",
                "approve this command",
                "confirm command",
                "do you want to proceed",
                "allow command",
                "authorization required",
            ]
            if any(marker in lowered for marker in approval_markers):
                return True
            if "dangerous command" in lowered and "choice [o/s/a/d]" in lowered:
                return True
            if all(marker in lowered for marker in ["[o]nce", "[s]ession", "[a]lways", "[d]eny"]):
                return True
            return (
                "approve" in lowered and
                "deny" in lowered and
                any(marker in lowered for marker in ["command", "choice", "permission", "approval", "request"])
            )

        def looks_like_approval_denial_stop(text):
            lowered = (text or "").lower()
            denial_markers = [
                "command denied. stopping",
                "command denied. stopped",
                "permission denied. stopping",
                "request denied. stopping",
            ]
            if any(marker in lowered for marker in denial_markers):
                return True
            return "✗ denied" in lowered and "stopping" in lowered

        def looks_like_approval_denial(text):
            lowered = (text or "").lower()
            return "✗ denied" in lowered or "command denied" in lowered

        def approval_error(message):
            return (
                "Hermes requested command approval, but this chat turn cannot collect manual approvals. "
                "Retry this turn with Auto-approve enabled, or resume the session in Terminal to review the command yourself."
                + ("\\n\\n" + message if message else "")
            )

        def stop_process(process):
            if process.poll() is not None:
                return
            try:
                process.terminate()
                process.wait(timeout=5)
            except Exception:
                try:
                    process.kill()
                    process.wait(timeout=2)
                except Exception:
                    pass

        def run_hermes_chat(command, cwd, env, timeout_seconds, auto_approve_commands):
            process = subprocess.Popen(
                command,
                cwd=cwd,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            selector = selectors.DefaultSelector()
            stdout_chunks = []
            stderr_chunks = []
            started_at = time.monotonic()
            approval_seen_at = None
            last_output_at = started_at
            approval_grace_seconds = 8.0
            denial_seen_at = None
            denial_grace_seconds = 30.0

            if process.stdout is not None:
                selector.register(process.stdout, selectors.EVENT_READ, "stdout")
            if process.stderr is not None:
                selector.register(process.stderr, selectors.EVENT_READ, "stderr")

            def append_chunk(stream_name, data):
                text = stringify(data)
                if stream_name == "stderr":
                    stderr_chunks.append(text)
                else:
                    stdout_chunks.append(text)

            try:
                while True:
                    now = time.monotonic()
                    if now - started_at > timeout_seconds:
                        stdout = "".join(stdout_chunks)
                        stderr = "".join(stderr_chunks)
                        partial = compact_output(stdout, stderr, 124)
                        stop_process(process)
                        if looks_like_approval_request(partial):
                            fail(approval_error(partial))
                        fail(
                            "Hermes did not finish within the allotted time. The turn was stopped so the app would not remain blocked indefinitely."
                            + ("\\n\\n" + partial if partial else "")
                        )

                    events = selector.select(timeout=0.2)
                    for key, _ in events:
                        try:
                            data = key.fileobj.read1(4096)
                        except AttributeError:
                            data = key.fileobj.read(4096)
                        if data:
                            append_chunk(key.data, data)
                            last_output_at = time.monotonic()
                        else:
                            try:
                                selector.unregister(key.fileobj)
                            except Exception:
                                pass

                    exit_code = process.poll()
                    if exit_code is not None:
                        for pipe, stream_name in ((process.stdout, "stdout"), (process.stderr, "stderr")):
                            if pipe is None:
                                continue
                            try:
                                remaining = pipe.read()
                            except Exception:
                                remaining = b""
                            if remaining:
                                append_chunk(stream_name, remaining)
                        return "".join(stdout_chunks), "".join(stderr_chunks), exit_code

                    if not auto_approve_commands:
                        partial = compact_output("".join(stdout_chunks), "".join(stderr_chunks), None)
                        if looks_like_approval_denial_stop(partial):
                            approval_seen_at = None
                            denial_seen_at = None
                        elif looks_like_approval_denial(partial):
                            approval_seen_at = None
                            if denial_seen_at is None:
                                denial_seen_at = now
                            elif (
                                now - denial_seen_at >= denial_grace_seconds and
                                now - last_output_at >= denial_grace_seconds
                            ):
                                stop_process(process)
                                fail(approval_error(partial))
                        elif looks_like_approval_request(partial):
                            denial_seen_at = None
                            if approval_seen_at is None:
                                approval_seen_at = now
                            elif (
                                now - approval_seen_at >= approval_grace_seconds and
                                now - last_output_at >= approval_grace_seconds
                            ):
                                stop_process(process)
                                fail(approval_error(partial))
                        else:
                            approval_seen_at = None
                            denial_seen_at = None
            finally:
                selector.close()

        try:
            hermes_home = resolved_hermes_home()
            home = pathlib.Path.home()
            env = os.environ.copy()
            env["HERMES_HOME"] = str(hermes_home)
            env.setdefault("NO_COLOR", "1")
            env.setdefault("TERM", "dumb")

            env["PATH"] = hermes_search_path()

            hermes_path = find_hermes_binary()
            if hermes_path is None:
                fail("Hermes CLI was not found in the remote SSH environment. Verify that `hermes` is installed and available on PATH for non-interactive SSH commands.")

            arguments = payload.get("arguments") or []
            if not isinstance(arguments, list) or not all(isinstance(item, str) for item in arguments):
                fail("Invalid Hermes chat invocation.")

            timeout_seconds = int(payload.get("timeout_seconds") or 1800)
            auto_approve_commands = bool(payload.get("auto_approve_commands"))

            stdout, stderr, exit_code = run_hermes_chat(
                [hermes_path] + arguments,
                cwd=str(home),
                env=env,
                timeout_seconds=timeout_seconds,
                auto_approve_commands=auto_approve_commands,
            )

            message = compact_output(stdout, stderr, exit_code)
            if not auto_approve_commands and looks_like_approval_denial_stop(message):
                fail(approval_error(message))

            if exit_code != 0:
                if not auto_approve_commands and looks_like_approval_request(message):
                    fail(approval_error(message))
                fail(message)

            print(json.dumps({
                "ok": True,
                "session_id": payload.get("session_id"),
                "stdout": compact_text(stdout),
                "stderr": compact_text(stderr),
            }, ensure_ascii=False))
        except Exception as exc:
            fail(f"Unable to run Hermes chat over SSH: {exc}")
        """
    }
}

// MARK: - Streaming errors

enum StreamingChatError: LocalizedError {
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response from the Hermes API."
        case .httpError(let code, let body):
            return "Hermes API returned HTTP \(code)\(body.isEmpty ? "." : ": \(body)")"
        }
    }
}

private struct HermesChatRequest: Encodable {
    let hermesHome: String
    let sessionID: String?
    let timeoutSeconds: Int
    let autoApproveCommands: Bool
    let arguments: [String]

    enum CodingKeys: String, CodingKey {
        case hermesHome = "hermes_home"
        case sessionID = "session_id"
        case timeoutSeconds = "timeout_seconds"
        case autoApproveCommands = "auto_approve_commands"
        case arguments
    }
}
