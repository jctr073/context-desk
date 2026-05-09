import XCTest
@testable import ContextDesk

final class OpenAIResponseDecodingTests: XCTestCase {
    func testDecodesStructuredBlocksFromFunctionCall() throws {
        let inner = #"{"blocks":[{"kind":"heading","text":"Title"},{"kind":"paragraph","text":"Body."}]}"#
        let envelope = """
        {
          "output": [
            {
              "type": "function_call",
              "name": "\(StructuredOutputSchema.toolName)",
              "call_id": "call_abc",
              "arguments": \(jsonEscaped(inner))
            }
          ]
        }
        """
        let blocks = try OpenAIService.decodeBlocks(from: Data(envelope.utf8))
        XCTAssertEqual(blocks, [
            .heading(text: "Title"),
            .paragraph(text: "Body."),
        ])
    }

    func testIgnoresFunctionCallWithDifferentName() throws {
        // A future build registering additional tools may emit other
        // function_calls in the same response. Only the emit_output one
        // carries the structured-output payload.
        let inner = #"{"blocks":[{"kind":"paragraph","text":"hi"}]}"#
        let envelope = """
        {
          "output": [
            { "type": "function_call", "name": "web_search", "call_id": "c1", "arguments": "{\\"q\\":\\"x\\"}" },
            { "type": "function_call", "name": "\(StructuredOutputSchema.toolName)", "call_id": "c2", "arguments": \(jsonEscaped(inner)) }
          ]
        }
        """
        let blocks = try OpenAIService.decodeBlocks(from: Data(envelope.utf8))
        XCTAssertEqual(blocks, [.paragraph(text: "hi")])
    }

    func testMissingFunctionCallThrowsMissingOutput() throws {
        let envelope = #"{"output":[]}"#
        XCTAssertThrowsError(try OpenAIService.decodeBlocks(from: Data(envelope.utf8))) { error in
            guard case AIWritingServiceError.missingOutput = error else {
                XCTFail("expected .missingOutput, got \(error)")
                return
            }
        }
    }

    func testNonJSONArgumentsThrowsInvalidStructuredOutput() throws {
        let envelope = """
        {
          "output": [
            { "type": "function_call", "name": "\(StructuredOutputSchema.toolName)", "call_id": "c1", "arguments": "not json" }
          ]
        }
        """
        XCTAssertThrowsError(try OpenAIService.decodeBlocks(from: Data(envelope.utf8))) { error in
            guard case AIWritingServiceError.invalidStructuredOutput = error else {
                XCTFail("expected .invalidStructuredOutput, got \(error)")
                return
            }
        }
    }

    private func jsonEscaped(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
