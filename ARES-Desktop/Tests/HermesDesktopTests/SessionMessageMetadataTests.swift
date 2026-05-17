import Foundation
import Testing
@testable import HermesDesktop

struct SessionMessageMetadataTests {
    @Test
    func assistantRoleDisplaysAsAgent() {
        #expect(SessionMessageRole.assistant.displayTitle == "Agent")
    }

    @Test
    func displayMetadataHidesDuplicateReasoningContent() throws {
        let message = try decodeMessage("""
        {
          "id": "1",
          "role": "assistant",
          "content": "hello",
          "metadata": {
            "finish_reason": "stop",
            "reasoning": "Same thought.",
            "reasoning_content": "Same thought."
          }
        }
        """)

        #expect(message.displayMetadata?["reasoning"] == .string("Same thought."))
        #expect(message.displayMetadata?["reasoning_content"] == nil)
        #expect(message.displayMetadata?["finish_reason"] == .string("stop"))
    }

    @Test
    func displayMetadataKeepsReasoningContentWhenDistinct() throws {
        let message = try decodeMessage("""
        {
          "id": "1",
          "role": "assistant",
          "content": "hello",
          "metadata": {
            "reasoning": "Short thought.",
            "reasoning_content": "Expanded reasoning content."
          }
        }
        """)

        #expect(message.displayMetadata?["reasoning"] == .string("Short thought."))
        #expect(message.displayMetadata?["reasoning_content"] == .string("Expanded reasoning content."))
    }

    @Test
    func toolDisplayBuildsCompactSummaryFromStructuredOutput() throws {
        let message = try decodeMessage("""
        {
          "id": "tool-1",
          "role": "tool",
          "content": "{\\"success\\":true,\\"files_modified\\":[\\"/home/edoardo/hermes-agent/agent/auxiliary_client.py\\"],\\"diff\\":\\"--- a/agent/auxiliary_client.py\\\\n+++ b/agent/auxiliary_client.py\\\\n@@ -1 +1 @@\\\\n-old\\\\n+new\\"}"
        }
        """)

        let display = SessionMessageDisplay(message: message)

        #expect(display.isToolMessage)
        #expect(display.toolSummary?.statusKind == .success)
        #expect(display.toolSummary?.statusText == "Succeeded")
        #expect(display.toolSummary?.title == "Modified auxiliary_client.py")
        #expect(display.toolSummary?.preview?.contains("auxiliary_client.py") == true)
        #expect(display.toolSummary?.isDetailPreviewTruncated == false)
    }

    @Test
    func toolDisplayTruncatesLargeOutputUntilExpanded() throws {
        let content = String(repeating: "tool output line\n", count: 500)
        let message = try decodeMessagePayload([
            "id": "tool-2",
            "role": "tool_result",
            "content": content
        ])

        let display = SessionMessageDisplay(message: message)

        #expect(display.isToolMessage)
        #expect(display.toolSummary?.title == "Tool output")
        #expect(display.toolSummary?.preview?.hasPrefix("tool output line") == true)
        #expect(SessionToolMessageSummary.detailPreview(from: display.content)?.count == 5_000)
        #expect(display.toolSummary?.isDetailPreviewTruncated == true)
        #expect(display.content == content)
    }

    private func decodeMessage(_ json: String) throws -> SessionMessage {
        try JSONDecoder().decode(SessionMessage.self, from: Data(json.utf8))
    }

    private func decodeMessagePayload(_ payload: [String: Any]) throws -> SessionMessage {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(SessionMessage.self, from: data)
    }
}
