import XCTest
@testable import ContextDesk

final class OpenAIResponseDecodingTests: XCTestCase {
    func testDecodesStructuredBlocksFromOutputText() throws {
        let inner = #"{"blocks":[{"kind":"heading","text":"Title"},{"kind":"paragraph","text":"Body."}]}"#
        let envelope = """
        {
          "output": [
            {
              "content": [
                { "type": "output_text", "text": \(jsonEscaped(inner)) }
              ]
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

    func testEmptyOutputTextThrowsMissingOutput() throws {
        let envelope = #"{"output":[]}"#
        XCTAssertThrowsError(try OpenAIService.decodeBlocks(from: Data(envelope.utf8))) { error in
            guard case AIWritingServiceError.missingOutput = error else {
                XCTFail("expected .missingOutput, got \(error)")
                return
            }
        }
    }

    func testNonJSONOutputTextThrowsInvalidStructuredOutput() throws {
        let envelope = """
        {
          "output": [
            { "content": [ { "type": "output_text", "text": "not json" } ] }
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
