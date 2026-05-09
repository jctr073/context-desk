import XCTest
@testable import ContextDesk

/// Pins the wire format of Anthropic request bodies. Adding more tools later
/// only mutates the `tools` array and `tool_choice`; everything else here is
/// the regression gate.
final class AnthropicRequestEncodingTests: XCTestCase {

    // MARK: - Single-turn (AnthropicSubmitRequest)

    func testSubmitRequestPinsToolsArray() throws {
        let prompt = makePrompt(model: .claudeSonnet46, input: "Hello")
        let payload = try encode(AnthropicSubmitRequest(prompt: prompt, stream: false))

        XCTAssertEqual(payload["model"] as? String, "claude-sonnet-4-6")
        XCTAssertNotNil(payload["max_tokens"] as? Int)
        XCTAssertNil(payload["stream"], "stream omitted when false")
        XCTAssertNotNil(payload["system"] as? String)
        XCTAssertNil(payload["thinking"], "no extended thinking on Sonnet 4.6")
        XCTAssertNil(payload["output_config"])

        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 3)

        // First tool: emit_output (custom).
        let emit = tools[0]
        XCTAssertNil(emit["type"], "custom emit_output tool has no type discriminator")
        XCTAssertEqual(emit["name"] as? String, StructuredOutputSchema.toolName)
        XCTAssertEqual(emit["description"] as? String, StructuredOutputSchema.description)
        let schemaObj = try XCTUnwrap(emit["input_schema"])
        let reencoded = try JSONSerialization.data(withJSONObject: schemaObj, options: [.sortedKeys])
        XCTAssertEqual(reencoded, StructuredOutputSchema.schemaData)

        // Second tool: web_search server tool.
        XCTAssertEqual(tools[1]["type"] as? String, "web_search_20260209")
        XCTAssertEqual(tools[1]["name"] as? String, "web_search")
        XCTAssertEqual(tools[1]["max_uses"] as? Int, 5)

        // Third tool: web_fetch server tool.
        XCTAssertEqual(tools[2]["type"] as? String, "web_fetch_20260209")
        XCTAssertEqual(tools[2]["name"] as? String, "web_fetch")
        XCTAssertEqual(tools[2]["max_uses"] as? Int, 5)
    }

    func testSubmitRequestForceEmitOutputWhenThinkingOff() throws {
        // Sonnet 4.6 has no reasoningEffort → thinking is off → tool_choice
        // pins emit_output by name. Server tools (web_search/web_fetch)
        // execute autonomously regardless.
        let prompt = makePrompt(model: .claudeSonnet46, input: "Hi")
        let payload = try encode(AnthropicSubmitRequest(prompt: prompt, stream: false))
        let toolChoice = try XCTUnwrap(payload["tool_choice"] as? [String: Any])
        XCTAssertEqual(toolChoice["type"] as? String, "tool")
        XCTAssertEqual(toolChoice["name"] as? String, StructuredOutputSchema.toolName)
        XCTAssertEqual(toolChoice["disable_parallel_tool_use"] as? Bool, true)
    }

    func testSubmitRequestAutoWhenThinkingOn() throws {
        // Opus 4.7 with reasoning effort → thinking on → tool_choice auto and
        // adaptive thinking config present.
        let prompt = makePrompt(model: .claudeOpus47Medium, input: "Hi")
        let payload = try encode(AnthropicSubmitRequest(prompt: prompt, stream: false))

        let thinking = try XCTUnwrap(payload["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["type"] as? String, "adaptive")

        let outputConfig = try XCTUnwrap(payload["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "medium")

        let toolChoice = try XCTUnwrap(payload["tool_choice"] as? [String: Any])
        XCTAssertEqual(toolChoice["type"] as? String, "auto")
        XCTAssertNil(toolChoice["disable_parallel_tool_use"],
                     "auto mode does not pin disable_parallel_tool_use")
    }

    func testSubmitRequestStreamFlag() throws {
        let prompt = makePrompt(model: .claudeSonnet46, input: "Hi")
        let payload = try encode(AnthropicSubmitRequest(prompt: prompt, stream: true))
        XCTAssertEqual(payload["stream"] as? Bool, true)
    }

    // MARK: - Multi-turn (AnthropicChatRequest)

    func testChatRequestPinsToolsArray() throws {
        let chat = ChatSubmitPrompt(
            model: .claudeSonnet46,
            operation: WritingOp.rephrase,
            customInstructions: "",
            turns: [
                ChatTurn(role: .user, text: "first"),
                ChatTurn(role: .assistant, text: "ack"),
                ChatTurn(role: .user, text: "second"),
            ]
        )
        let payload = try encode(AnthropicChatRequest(prompt: chat, stream: true))

        XCTAssertEqual(payload["model"] as? String, "claude-sonnet-4-6")
        XCTAssertEqual(payload["stream"] as? Bool, true)

        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        XCTAssertEqual(messages[2]["role"] as? String, "user")

        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools[0]["name"] as? String, StructuredOutputSchema.toolName)
        XCTAssertEqual(tools[1]["name"] as? String, "web_search")
        XCTAssertEqual(tools[2]["name"] as? String, "web_fetch")

        let schemaObj = try XCTUnwrap(tools[0]["input_schema"])
        let reencoded = try JSONSerialization.data(withJSONObject: schemaObj, options: [.sortedKeys])
        XCTAssertEqual(reencoded, StructuredOutputSchema.schemaData)

        let toolChoice = try XCTUnwrap(payload["tool_choice"] as? [String: Any])
        XCTAssertEqual(toolChoice["type"] as? String, "tool")
        XCTAssertEqual(toolChoice["name"] as? String, StructuredOutputSchema.toolName)
        XCTAssertEqual(toolChoice["disable_parallel_tool_use"] as? Bool, true)
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any])
    }

    private func makePrompt(model: AIModel, input: String) -> SubmitPrompt {
        SubmitPrompt(
            model: model,
            operation: WritingOp.rephrase,
            input: input,
            context: "",
            customInstructions: ""
        )
    }
}
