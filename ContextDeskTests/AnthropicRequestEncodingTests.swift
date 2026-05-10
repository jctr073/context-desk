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
        // system is now a typed array of text blocks (required for cache_control).
        let system = try XCTUnwrap(payload["system"] as? [[String: Any]])
        XCTAssertEqual(system.count, 1)
        XCTAssertEqual(system[0]["type"] as? String, "text")
        XCTAssertNotNil(system[0]["text"] as? String)
        let cacheControl = try XCTUnwrap(system[0]["cache_control"] as? [String: Any])
        XCTAssertEqual(cacheControl["type"] as? String, "ephemeral")
        XCTAssertNil(payload["thinking"], "no extended thinking on Sonnet 4.6")
        XCTAssertNil(payload["output_config"])

        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)

        // emit_output (custom) is always present, and is the only tool here so
        // it carries the cache breakpoint.
        let emit = tools[0]
        XCTAssertNil(emit["type"], "custom emit_output tool has no type discriminator")
        XCTAssertEqual(emit["name"] as? String, StructuredOutputSchema.toolName)
        XCTAssertEqual(emit["description"] as? String, StructuredOutputSchema.description)
        let schemaObj = try XCTUnwrap(emit["input_schema"])
        let reencoded = try JSONSerialization.data(withJSONObject: schemaObj, options: [.sortedKeys])
        XCTAssertEqual(reencoded, StructuredOutputSchema.schemaData)
        let toolCacheControl = try XCTUnwrap(emit["cache_control"] as? [String: Any])
        XCTAssertEqual(toolCacheControl["type"] as? String, "ephemeral")

    }

    func testSubmitRequestAddsServerWebToolsOnlyWhenEnabled() throws {
        let prompt = makePrompt(model: .claudeSonnet46, input: "Hello", webAccessEnabled: true)
        let payload = try encode(AnthropicSubmitRequest(prompt: prompt, stream: false))

        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 3)

        XCTAssertEqual(tools[0]["name"] as? String, StructuredOutputSchema.toolName)
        XCTAssertEqual(tools[1]["type"] as? String, "web_search_20260209")
        XCTAssertEqual(tools[1]["name"] as? String, "web_search")
        XCTAssertEqual(tools[1]["max_uses"] as? Int, 5)
        XCTAssertEqual(tools[2]["type"] as? String, "web_fetch_20260209")
        XCTAssertEqual(tools[2]["name"] as? String, "web_fetch")
        XCTAssertEqual(tools[2]["max_uses"] as? Int, 5)
        // The cache breakpoint always lands on the last tool entry.
        XCTAssertNil(tools[0]["cache_control"])
        XCTAssertNil(tools[1]["cache_control"])
        let lastToolCacheControl = try XCTUnwrap(tools[2]["cache_control"] as? [String: Any])
        XCTAssertEqual(lastToolCacheControl["type"] as? String, "ephemeral")

        let system = try XCTUnwrap(payload["system"] as? [[String: Any]])
        let systemText = try XCTUnwrap(system[0]["text"] as? String)
        XCTAssertTrue(systemText.contains("Do not include API keys"))
    }

    func testSubmitRequestForceEmitOutputWhenThinkingOff() throws {
        // Sonnet 4.6 has no reasoningEffort -> thinking is off -> tool_choice
        // pins emit_output by name.
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
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["name"] as? String, StructuredOutputSchema.toolName)

        let schemaObj = try XCTUnwrap(tools[0]["input_schema"])
        let reencoded = try JSONSerialization.data(withJSONObject: schemaObj, options: [.sortedKeys])
        XCTAssertEqual(reencoded, StructuredOutputSchema.schemaData)

        let toolChoice = try XCTUnwrap(payload["tool_choice"] as? [String: Any])
        XCTAssertEqual(toolChoice["type"] as? String, "tool")
        XCTAssertEqual(toolChoice["name"] as? String, StructuredOutputSchema.toolName)
        XCTAssertEqual(toolChoice["disable_parallel_tool_use"] as? Bool, true)
    }

    func testChatRequestAddsServerWebToolsOnlyWhenEnabled() throws {
        let chat = ChatSubmitPrompt(
            model: .claudeSonnet46,
            operation: WritingOp.rephrase,
            customInstructions: "",
            turns: [ChatTurn(role: .user, text: "latest?")],
            webAccessEnabled: true
        )
        let payload = try encode(AnthropicChatRequest(prompt: chat, stream: true))

        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools[0]["name"] as? String, StructuredOutputSchema.toolName)
        XCTAssertEqual(tools[1]["name"] as? String, "web_search")
        XCTAssertEqual(tools[2]["name"] as? String, "web_fetch")
        // Cache breakpoint sits on the last tool entry only.
        XCTAssertNil(tools[0]["cache_control"])
        XCTAssertNil(tools[1]["cache_control"])
        XCTAssertNotNil(tools[2]["cache_control"] as? [String: Any])

        let system = try XCTUnwrap(payload["system"] as? [[String: Any]])
        let systemText = try XCTUnwrap(system[0]["text"] as? String)
        XCTAssertTrue(systemText.contains("minimal public-safe query"))
    }

    func testChatRequestFoldsContextTextIntoSystemAndImagesIntoPreambleUser() throws {
        let chat = ChatSubmitPrompt(
            model: .claudeSonnet46,
            operation: ChatOp.ask,
            customInstructions: "",
            turns: [
                ChatTurn(role: .user, text: "first"),
                ChatTurn(role: .assistant, text: "ack"),
                ChatTurn(role: .user, text: "second"),
            ],
            context: "These are the project notes.",
            contextImages: [stubImage()]
        )
        let payload = try encode(AnthropicChatRequest(prompt: chat, stream: true))

        let system = try XCTUnwrap(payload["system"] as? [[String: Any]])
        let systemText = try XCTUnwrap(system[0]["text"] as? String)
        XCTAssertTrue(systemText.contains("These are the project notes."),
                      "context text must be in system, not folded into a user turn")

        // Preamble user message at index 0 carries context images, then real
        // turns follow unmodified.
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let preambleParts = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(preambleParts.count, 1)
        XCTAssertEqual(preambleParts[0]["type"] as? String, "image")

        // The first real user turn is unchanged — no context preface spliced
        // into its text.
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "first")
    }

    func testChatRequestMarksTrailingAssistantAsCacheBreakpoint() throws {
        // The most recent assistant message before a new user turn becomes
        // the transcript-prefix cache breakpoint — its trailing text block
        // gets `cache_control: ephemeral`.
        let chat = ChatSubmitPrompt(
            model: .claudeSonnet46,
            operation: ChatOp.ask,
            customInstructions: "",
            turns: [
                ChatTurn(role: .user, text: "first"),
                ChatTurn(role: .assistant, text: "ack"),
                ChatTurn(role: .user, text: "second"),
            ]
        )
        let payload = try encode(AnthropicChatRequest(prompt: chat, stream: true))
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        // After marking, the assistant content is in block form rather than
        // a plain string.
        let assistantBlocks = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistantBlocks.count, 1)
        XCTAssertEqual(assistantBlocks[0]["type"] as? String, "text")
        XCTAssertEqual(assistantBlocks[0]["text"] as? String, "ack")
        let assistantCacheControl = try XCTUnwrap(assistantBlocks[0]["cache_control"] as? [String: Any])
        XCTAssertEqual(assistantCacheControl["type"] as? String, "ephemeral")
    }

    func testChatRequestSkipsTranscriptBreakpointWhenNoAssistantYet() throws {
        let chat = ChatSubmitPrompt(
            model: .claudeSonnet46,
            operation: ChatOp.ask,
            customInstructions: "",
            turns: [ChatTurn(role: .user, text: "first")]
        )
        let payload = try encode(AnthropicChatRequest(prompt: chat, stream: true))
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        // Plain string content, no caching marker on the user turn.
        XCTAssertEqual(messages[0]["content"] as? String, "first")
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any])
    }

    private func makePrompt(
        model: AIModel,
        input: String,
        webAccessEnabled: Bool = false
    ) -> SubmitPrompt {
        SubmitPrompt(
            model: model,
            operation: WritingOp.rephrase,
            input: input,
            context: "",
            customInstructions: "",
            webAccessEnabled: webAccessEnabled
        )
    }

    private func stubImage() -> AttachedImage {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        return AttachedImage(
            fileName: "stub.png",
            mimeType: "image/png",
            base64: base64,
            width: 1,
            height: 1,
            byteSize: 70
        )
    }
}
