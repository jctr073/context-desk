import XCTest
@testable import ContextDesk

/// The replay helper isn't wired into any code path in this branch — it's
/// the seam the future tool branch will hook into. Tests pin the shape it
/// produces so that branch can iterate against a known interface.
final class ToolCallReplayTests: XCTestCase {

    // MARK: - Anthropic

    func testProseOnlyAssistantCollapsesToSingleMessage() {
        let msg = assistant(blocks: [.paragraph(text: "hello")])
        let messages = ToolCallReplay.anthropicMessages(from: msg)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, "assistant")
    }

    func testInterleavedToolActivityProducesAssistantUserAssistantSequence() throws {
        let msg = assistant(blocks: [
            .paragraph(text: "Let me look that up."),
            .toolCall(id: "c1", name: "web_search", argumentsJSON: #"{"q":"swift"}"#),
            .toolResult(callID: "c1", content: "1 result", isError: false),
            .paragraph(text: "Found it."),
        ])
        let messages = ToolCallReplay.anthropicMessages(from: msg)
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0].role, "assistant")
        XCTAssertEqual(messages[1].role, "user")
        XCTAssertEqual(messages[2].role, "assistant")

        // Spot-check the encoded shape (text + tool_use, then tool_result, then text).
        let encoder = JSONEncoder()
        let first = try JSONSerialization.jsonObject(with: encoder.encode(messages[0])) as? [String: Any]
        let firstContent = try XCTUnwrap(first?["content"] as? [[String: Any]])
        XCTAssertEqual(firstContent.count, 2)
        XCTAssertEqual(firstContent[0]["type"] as? String, "text")
        XCTAssertEqual(firstContent[1]["type"] as? String, "tool_use")
        XCTAssertEqual(firstContent[1]["id"] as? String, "c1")
        XCTAssertEqual(firstContent[1]["name"] as? String, "web_search")

        let second = try JSONSerialization.jsonObject(with: encoder.encode(messages[1])) as? [String: Any]
        let secondContent = try XCTUnwrap(second?["content"] as? [[String: Any]])
        XCTAssertEqual(secondContent.count, 1)
        XCTAssertEqual(secondContent[0]["type"] as? String, "tool_result")
        XCTAssertEqual(secondContent[0]["tool_use_id"] as? String, "c1")
        XCTAssertEqual(secondContent[0]["content"] as? String, "1 result")
        XCTAssertEqual(secondContent[0]["is_error"] as? Bool, false)
    }

    func testParallelToolCallsCollapseIntoOneAssistantMessage() {
        let msg = assistant(blocks: [
            .toolCall(id: "c1", name: "a", argumentsJSON: "{}"),
            .toolCall(id: "c2", name: "b", argumentsJSON: "{}"),
            .toolResult(callID: "c1", content: "ok1", isError: false),
            .toolResult(callID: "c2", content: "ok2", isError: false),
            .paragraph(text: "done"),
        ])
        let messages = ToolCallReplay.anthropicMessages(from: msg)
        // assistant(2 tool_use) + user(2 tool_result) + assistant(text)
        XCTAssertEqual(messages.count, 3)
    }

    // MARK: - OpenAI

    func testOpenAIProseOnlyCollapsesToOneMessageItem() {
        let msg = assistant(blocks: [
            .paragraph(text: "hi"),
            .heading(text: "Section"),
        ])
        let items = ToolCallReplay.openAIInputItems(from: msg)
        XCTAssertEqual(items.count, 1)
        guard case .message(let role, _) = items[0] else {
            return XCTFail("expected .message item")
        }
        XCTAssertEqual(role, "assistant")
    }

    func testOpenAIToolCallProducesFunctionCallItem() {
        let msg = assistant(blocks: [
            .paragraph(text: "checking..."),
            .toolCall(id: "c1", name: "web_search", argumentsJSON: #"{"q":"x"}"#),
            .toolResult(callID: "c1", content: "ok", isError: false),
            .paragraph(text: "done"),
        ])
        let items = ToolCallReplay.openAIInputItems(from: msg)
        XCTAssertEqual(items.count, 4)
        if case .message = items[0] {} else { XCTFail("0 should be .message") }
        if case .functionCall(let callID, let name, _) = items[1] {
            XCTAssertEqual(callID, "c1")
            XCTAssertEqual(name, "web_search")
        } else {
            XCTFail("1 should be .functionCall")
        }
        if case .functionCallOutput(let callID, let output) = items[2] {
            XCTAssertEqual(callID, "c1")
            XCTAssertEqual(output, "ok")
        } else {
            XCTFail("2 should be .functionCallOutput")
        }
        if case .message = items[3] {} else { XCTFail("3 should be .message") }
    }

    func testOpenAIRequestInputItemEncodesFunctionCall() throws {
        let item = OpenAIRequestInputItem.functionCall(
            callID: "c_abc",
            name: "search",
            argumentsJSON: #"{"q":"x"}"#
        )
        let data = try JSONEncoder().encode(item)
        let dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(dict["type"] as? String, "function_call")
        XCTAssertEqual(dict["call_id"] as? String, "c_abc")
        XCTAssertEqual(dict["name"] as? String, "search")
        XCTAssertEqual(dict["arguments"] as? String, #"{"q":"x"}"#)
    }

    func testOpenAIRequestInputItemEncodesFunctionCallOutput() throws {
        let item = OpenAIRequestInputItem.functionCallOutput(callID: "c_abc", output: "1 result")
        let data = try JSONEncoder().encode(item)
        let dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(dict["type"] as? String, "function_call_output")
        XCTAssertEqual(dict["call_id"] as? String, "c_abc")
        XCTAssertEqual(dict["output"] as? String, "1 result")
    }

    // MARK: - Helpers

    private func assistant(blocks: [OutputBlock]) -> ChatMessage {
        ChatMessage(role: .assistant, text: "", blocks: blocks)
    }
}
