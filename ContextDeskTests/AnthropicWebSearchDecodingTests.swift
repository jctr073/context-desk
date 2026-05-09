import XCTest
@testable import ContextDesk

/// Pins how Anthropic's hosted `web_search_20260209` and
/// `web_fetch_20260209` server tools surface in our decoded
/// `[OutputBlock]` stream. Activity arrives as `server_tool_use` +
/// `web_search_tool_result` (or `web_fetch_tool_result`) content
/// blocks. We translate them into `.toolCall` / `.toolResult` blocks
/// rendered before the `emit_output` blocks.
final class AnthropicWebSearchDecodingTests: XCTestCase {

    // MARK: - Non-streaming

    func testDecodesServerToolUseAndResult() throws {
        let envelope = """
        {
          "content": [
            {
              "type": "server_tool_use",
              "id": "srvtoolu_1",
              "name": "web_search",
              "input": { "query": "swift concurrency" }
            },
            {
              "type": "web_search_tool_result",
              "tool_use_id": "srvtoolu_1",
              "content": [
                { "type": "web_search_result", "url": "https://example.com", "title": "Example" }
              ]
            },
            {
              "type": "tool_use",
              "name": "\(StructuredOutputSchema.toolName)",
              "input": { "blocks": [ { "kind": "paragraph", "text": "answer" } ] }
            }
          ]
        }
        """
        let blocks = try AnthropicService.decodeBlocks(from: Data(envelope.utf8))
        XCTAssertEqual(blocks.count, 3)
        guard case .toolCall(let id, let name, let argsJSON) = blocks[0] else {
            return XCTFail("blocks[0] should be .toolCall, got \(blocks[0])")
        }
        XCTAssertEqual(id, "srvtoolu_1")
        XCTAssertEqual(name, "web_search")
        XCTAssertTrue(argsJSON.contains("\"swift concurrency\""))

        guard case .toolResult(let callID, let content, let isError) = blocks[1] else {
            return XCTFail("blocks[1] should be .toolResult, got \(blocks[1])")
        }
        XCTAssertEqual(callID, "srvtoolu_1")
        XCTAssertTrue(content.contains("https://example.com"), "content was: \(content)")
        XCTAssertFalse(isError)

        XCTAssertEqual(blocks[2], .paragraph(text: "answer"))
    }

    func testWebFetchToolResultDecodes() throws {
        let envelope = """
        {
          "content": [
            {
              "type": "server_tool_use",
              "id": "srvtoolu_f",
              "name": "web_fetch",
              "input": { "url": "https://example.com" }
            },
            {
              "type": "web_fetch_tool_result",
              "tool_use_id": "srvtoolu_f",
              "content": { "type": "web_fetch_result", "url": "https://example.com" }
            },
            {
              "type": "tool_use",
              "name": "\(StructuredOutputSchema.toolName)",
              "input": { "blocks": [ { "kind": "paragraph", "text": "ok" } ] }
            }
          ]
        }
        """
        let blocks = try AnthropicService.decodeBlocks(from: Data(envelope.utf8))
        XCTAssertEqual(blocks.count, 3)
        guard case .toolCall(_, let name, _) = blocks[0] else {
            return XCTFail("expected .toolCall, got \(blocks[0])")
        }
        XCTAssertEqual(name, "web_fetch")
    }

    func testToolResultErrorMarksIsErrorTrue() throws {
        let envelope = """
        {
          "content": [
            {
              "type": "server_tool_use",
              "id": "srvtoolu_e",
              "name": "web_search",
              "input": { "query": "x" }
            },
            {
              "type": "web_search_tool_result",
              "tool_use_id": "srvtoolu_e",
              "content": { "type": "web_search_tool_result_error", "error_code": "max_uses_exceeded" }
            },
            {
              "type": "tool_use",
              "name": "\(StructuredOutputSchema.toolName)",
              "input": { "blocks": [ { "kind": "paragraph", "text": "p" } ] }
            }
          ]
        }
        """
        let blocks = try AnthropicService.decodeBlocks(from: Data(envelope.utf8))
        guard case .toolResult(_, _, let isError) = blocks[1] else {
            return XCTFail("expected toolResult at [1], got \(blocks[1])")
        }
        XCTAssertTrue(isError)
    }

    // MARK: - Streaming

    func testStreamingServerToolUseProducesToolCallAndResult() async throws {
        let json = #"{"blocks":[{"kind":"paragraph","text":"hi"}]}"#
        let events: [SSEEvent] = [
            // Index 1: server_tool_use
            serverToolUseStart(index: 1, id: "srvtoolu_1", name: "web_search"),
            inputJsonDelta(index: 1, partial: #"{"query":"swift"}"#),
            blockStop(index: 1),
            // Index 2: web_search_tool_result (whole)
            searchResultStart(index: 2, toolUseID: "srvtoolu_1", url: "https://example.com"),
            blockStop(index: 2),
            // Index 3: emit_output tool_use
            toolUseStart(index: 3),
            inputJsonDelta(index: 3, partial: json),
            blockStop(index: 3),
            messageStop(),
        ]

        let snapshots = try await collect(events)
        let final = snapshots.last ?? []
        XCTAssertEqual(final.count, 3)
        guard case .toolCall(let id, let name, let args) = final[0] else {
            return XCTFail("blocks[0] should be .toolCall, got \(final[0])")
        }
        XCTAssertEqual(id, "srvtoolu_1")
        XCTAssertEqual(name, "web_search")
        XCTAssertTrue(args.contains("\"swift\""))

        guard case .toolResult(let cid, let content, let isError) = final[1] else {
            return XCTFail("blocks[1] should be .toolResult, got \(final[1])")
        }
        XCTAssertEqual(cid, "srvtoolu_1")
        XCTAssertTrue(content.contains("example.com"))
        XCTAssertFalse(isError)

        XCTAssertEqual(final.last, .paragraph(text: "hi"))
    }

    func testStreamingErrorResultBlockMarksIsError() async throws {
        let json = #"{"blocks":[{"kind":"paragraph","text":"x"}]}"#
        let events: [SSEEvent] = [
            serverToolUseStart(index: 1, id: "srvtoolu_e", name: "web_search"),
            inputJsonDelta(index: 1, partial: #"{"query":"q"}"#),
            blockStop(index: 1),
            errorResultStart(index: 2, toolUseID: "srvtoolu_e", code: "max_uses_exceeded"),
            blockStop(index: 2),
            toolUseStart(index: 3),
            inputJsonDelta(index: 3, partial: json),
            blockStop(index: 3),
            messageStop(),
        ]
        let final = (try await collect(events)).last ?? []
        guard case .toolResult(_, _, let isError) = final[1] else {
            return XCTFail("expected .toolResult at [1], got \(final[1])")
        }
        XCTAssertTrue(isError)
    }

    func testStreamingServerToolDoesNotPolluteEmitOutputParser() async throws {
        // Server-tool input deltas at a non-emit index must not feed the
        // structured-output parser.
        let json = #"{"blocks":[{"kind":"heading","text":"H"}]}"#
        let events: [SSEEvent] = [
            serverToolUseStart(index: 1, id: "srvtoolu_1", name: "web_search"),
            inputJsonDelta(index: 1, partial: #"{"blocks":[{"kind":"paragraph","text":"WRONG"}]}"#),
            blockStop(index: 1),
            toolUseStart(index: 2),
            inputJsonDelta(index: 2, partial: json),
            blockStop(index: 2),
            messageStop(),
        ]
        let final = (try await collect(events)).last ?? []
        XCTAssertEqual(final.last, .heading(text: "H"))
    }

    // MARK: - Helpers

    private func collect(_ events: [SSEEvent]) async throws -> [[OutputBlock]] {
        let seq = WebToolEventSequence(events: events)
        var out: [[OutputBlock]] = []
        for try await snapshot in AnthropicService.decodeStream(events: seq) {
            out.append(snapshot)
        }
        return out
    }

    private func serverToolUseStart(index: Int, id: String, name: String) -> SSEEvent {
        SSEEvent(
            event: nil,
            data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"server_tool_use","id":"\#(id)","name":"\#(name)","input":{}}}"#
        )
    }

    private func searchResultStart(index: Int, toolUseID: String, url: String) -> SSEEvent {
        SSEEvent(
            event: nil,
            data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"web_search_tool_result","tool_use_id":"\#(toolUseID)","content":[{"type":"web_search_result","url":"\#(url)","title":"Example"}]}}"#
        )
    }

    private func errorResultStart(index: Int, toolUseID: String, code: String) -> SSEEvent {
        SSEEvent(
            event: nil,
            data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"web_search_tool_result","tool_use_id":"\#(toolUseID)","content":{"type":"web_search_tool_result_error","error_code":"\#(code)"}}}"#
        )
    }

    private func toolUseStart(index: Int) -> SSEEvent {
        SSEEvent(
            event: nil,
            data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"tool_use","name":"\#(StructuredOutputSchema.toolName)","input":{}}}"#
        )
    }

    private func inputJsonDelta(index: Int, partial: String) -> SSEEvent {
        let escaped = jsonEscape(partial)
        return SSEEvent(
            event: nil,
            data: #"{"type":"content_block_delta","index":\#(index),"delta":{"type":"input_json_delta","partial_json":\#(escaped)}}"#
        )
    }

    private func blockStop(index: Int) -> SSEEvent {
        SSEEvent(event: nil, data: #"{"type":"content_block_stop","index":\#(index)}"#)
    }

    private func messageStop() -> SSEEvent {
        SSEEvent(event: nil, data: #"{"type":"message_stop"}"#)
    }

    private func jsonEscape(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}

private struct WebToolEventSequence: AsyncSequence {
    typealias Element = SSEEvent
    let events: [SSEEvent]
    struct AsyncIterator: AsyncIteratorProtocol {
        var iter: IndexingIterator<[SSEEvent]>
        mutating func next() async throws -> SSEEvent? { iter.next() }
    }
    func makeAsyncIterator() -> AsyncIterator { .init(iter: events.makeIterator()) }
}
