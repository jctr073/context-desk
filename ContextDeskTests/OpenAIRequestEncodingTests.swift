import XCTest
@testable import ContextDesk

/// Pins the wire format of OpenAI request bodies. Track 3 of the tool-use
/// prep deliberately changes this; updating these assertions is how we make
/// that change visible in code review instead of silent.
final class OpenAIRequestEncodingTests: XCTestCase {

    // MARK: - Single-turn (OpenAISubmitRequest)

    func testSubmitRequestPinsStructuredOutputSchema() throws {
        let prompt = makePrompt(model: .gpt55Medium, input: "Hello")
        let payload = try encode(OpenAISubmitRequest(prompt: prompt, stream: false))

        XCTAssertEqual(payload["model"] as? String, "gpt-5.5")
        XCTAssertNil(payload["stream"], "stream omitted when false")
        XCTAssertEqual(payload["input"] as? String, "Hello")
        XCTAssertNotNil(payload["instructions"] as? String)

        let reasoning = try XCTUnwrap(payload["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["effort"] as? String, "medium")

        // No `text.format` / json_schema response_format anymore: the schema
        // ships as the parameters of a forced function-call tool.
        XCTAssertNil(payload["text"], "response_format replaced by forced function-call")

        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 2)

        // First tool: emit_output (custom function).
        let emit = tools[0]
        XCTAssertEqual(emit["type"] as? String, "function")
        XCTAssertEqual(emit["name"] as? String, StructuredOutputSchema.toolName)
        XCTAssertEqual(emit["description"] as? String, StructuredOutputSchema.description)
        XCTAssertEqual(emit["strict"] as? Bool, true)
        let parameters = try XCTUnwrap(emit["parameters"])
        let reencoded = try JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys])
        XCTAssertEqual(reencoded, StructuredOutputSchema.schemaData)

        // Second tool: hosted web_search.
        let web = tools[1]
        XCTAssertEqual(web["type"] as? String, "web_search")
        XCTAssertNil(web["name"], "hosted tools have no function name")
        XCTAssertNil(web["parameters"], "hosted tools have no schema")
        XCTAssertNil(web["allowed_domains"], "no domain filter set in this branch")
        XCTAssertNil(web["blocked_domains"])

        let toolChoice = try XCTUnwrap(payload["tool_choice"] as? [String: Any])
        XCTAssertEqual(toolChoice["type"] as? String, "function")
        XCTAssertEqual(toolChoice["name"] as? String, StructuredOutputSchema.toolName)
    }

    func testSubmitRequestStreamFlag() throws {
        let prompt = makePrompt(model: .gpt55Low, input: "Hi")
        let payload = try encode(OpenAISubmitRequest(prompt: prompt, stream: true))
        XCTAssertEqual(payload["stream"] as? Bool, true)
    }

    func testSubmitRequestMultimodalInput() throws {
        let prompt = makePrompt(
            model: .gpt55Medium,
            input: "describe",
            inputImages: [stubImage()]
        )
        let payload = try encode(OpenAISubmitRequest(prompt: prompt, stream: false))
        let input = try XCTUnwrap(payload["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 1)
        let item = input[0]
        XCTAssertEqual(item["role"] as? String, "user")
        let parts = try XCTUnwrap(item["content"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["type"] as? String, "input_image")
        XCTAssertEqual(parts.last?["type"] as? String, "input_text")
    }

    // MARK: - Multi-turn (OpenAIChatRequest)

    func testChatRequestPinsStructuredOutputSchema() throws {
        let chat = ChatSubmitPrompt(
            model: .gpt55Medium,
            operation: WritingOp.rephrase,
            customInstructions: "",
            turns: [
                ChatTurn(role: .user, text: "first"),
                ChatTurn(role: .assistant, text: "ack"),
                ChatTurn(role: .user, text: "second"),
            ]
        )
        let payload = try encode(OpenAIChatRequest(prompt: chat, stream: true))

        XCTAssertEqual(payload["model"] as? String, "gpt-5.5")
        XCTAssertEqual(payload["stream"] as? Bool, true)

        let input = try XCTUnwrap(payload["input"] as? [[String: Any]])
        XCTAssertEqual(input.count, 3)
        XCTAssertEqual(input[0]["role"] as? String, "user")
        XCTAssertEqual(input[1]["role"] as? String, "assistant")
        XCTAssertEqual(input[2]["role"] as? String, "user")

        // Assistant turns use the `output_text` content type.
        let assistantParts = try XCTUnwrap(input[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistantParts.first?["type"] as? String, "output_text")
        // User turns use `input_text`.
        let userParts = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(userParts.first?["type"] as? String, "input_text")

        XCTAssertNil(payload["text"])
        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools[0]["name"] as? String, StructuredOutputSchema.toolName)
        let parameters = try XCTUnwrap(tools[0]["parameters"])
        let reencoded = try JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys])
        XCTAssertEqual(reencoded, StructuredOutputSchema.schemaData)
        XCTAssertEqual(tools[1]["type"] as? String, "web_search")

        let toolChoice = try XCTUnwrap(payload["tool_choice"] as? [String: Any])
        XCTAssertEqual(toolChoice["type"] as? String, "function")
        XCTAssertEqual(toolChoice["name"] as? String, StructuredOutputSchema.toolName)
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
        inputImages: [AttachedImage] = []
    ) -> SubmitPrompt {
        SubmitPrompt(
            model: model,
            operation: WritingOp.rephrase,
            input: input,
            context: "",
            customInstructions: "",
            inputImages: inputImages
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
