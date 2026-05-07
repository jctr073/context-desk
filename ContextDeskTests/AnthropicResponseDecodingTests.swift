import XCTest
@testable import ContextDesk

final class AnthropicResponseDecodingTests: XCTestCase {
    func testDecodesBlocksFromToolUseInput() throws {
        let envelope = """
        {
          "content": [
            {
              "type": "tool_use",
              "name": "emit_output",
              "input": {
                "blocks": [
                  { "kind": "paragraph", "text": "Hi." },
                  { "kind": "bulletList", "items": ["a", "b"] }
                ]
              }
            }
          ]
        }
        """
        let blocks = try AnthropicService.decodeBlocks(from: Data(envelope.utf8))
        XCTAssertEqual(blocks, [
            .paragraph(text: "Hi."),
            .bulletList(items: ["a", "b"]),
        ])
    }

    func testSkipsLeadingThinkingBlockToFindToolUse() throws {
        let envelope = """
        {
          "content": [
            { "type": "thinking", "text": "reasoning..." },
            {
              "type": "tool_use",
              "name": "emit_output",
              "input": { "blocks": [ { "kind": "heading", "text": "ok" } ] }
            }
          ]
        }
        """
        let blocks = try AnthropicService.decodeBlocks(from: Data(envelope.utf8))
        XCTAssertEqual(blocks, [.heading(text: "ok")])
    }

    func testTextOnlyResponseThrowsMissingOutput() throws {
        let envelope = """
        {
          "content": [
            { "type": "text", "text": "just words" }
          ]
        }
        """
        XCTAssertThrowsError(try AnthropicService.decodeBlocks(from: Data(envelope.utf8))) { error in
            guard case AIWritingServiceError.missingOutput = error else {
                XCTFail("expected .missingOutput, got \(error)")
                return
            }
        }
    }

    func testMalformedToolInputThrowsInvalidStructuredOutput() throws {
        // input present but missing the required `blocks` key — decoder fails
        // before populating `input`, which surfaces as invalidStructuredOutput
        // (Foundation's DecodingError wrapped).
        let envelope = """
        {
          "content": [
            {
              "type": "tool_use",
              "name": "emit_output",
              "input": { "wrong_field": [] }
            }
          ]
        }
        """
        XCTAssertThrowsError(try AnthropicService.decodeBlocks(from: Data(envelope.utf8))) { error in
            // Two valid outcomes depending on how Foundation reports the
            // missing-key path: either a DecodingError surfaces directly, or
            // it's wrapped in our invalidStructuredOutput case. Both indicate
            // structured-output validation failed.
            switch error {
            case AIWritingServiceError.invalidStructuredOutput:
                break
            case is DecodingError:
                break
            default:
                XCTFail("expected structured-output failure, got \(error)")
            }
        }
    }
}
