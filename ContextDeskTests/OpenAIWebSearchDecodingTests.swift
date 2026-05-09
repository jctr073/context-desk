import XCTest
@testable import ContextDesk

/// Pins how the OpenAI Responses API hosted `web_search` tool surfaces
/// in our decoded `[OutputBlock]` stream. Activity arrives as
/// `web_search_call` output items (non-streaming) or
/// `response.output_item.added` + `response.web_search_call.completed`
/// events (streaming) — we translate both into paired `.toolCall` /
/// `.toolResult` blocks rendered before the `emit_output` blocks.
final class OpenAIWebSearchDecodingTests: XCTestCase {

    // MARK: - Non-streaming

    func testDecodesWebSearchCallAlongsideEmitOutput() throws {
        let inner = #"{"blocks":[{"kind":"paragraph","text":"answer"}]}"#
        let envelope = """
        {
          "output": [
            {
              "type": "web_search_call",
              "id": "ws_1",
              "status": "completed",
              "action": { "type": "search", "query": "swift concurrency" }
            },
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
        XCTAssertEqual(blocks.count, 3, "expected toolCall + toolResult + emit_output paragraph")
        guard case .toolCall(let id, let name, let argsJSON) = blocks[0] else {
            return XCTFail("blocks[0] should be .toolCall, got \(blocks[0])")
        }
        XCTAssertEqual(id, "ws_1")
        XCTAssertEqual(name, "web_search")
        XCTAssertTrue(argsJSON.contains("\"swift concurrency\""), "args should contain the query: \(argsJSON)")

        guard case .toolResult(let callID, let content, let isError) = blocks[1] else {
            return XCTFail("blocks[1] should be .toolResult, got \(blocks[1])")
        }
        XCTAssertEqual(callID, "ws_1")
        XCTAssertEqual(content, "completed")
        XCTAssertFalse(isError)

        XCTAssertEqual(blocks[2], .paragraph(text: "answer"))
    }

    func testFailedWebSearchCallMarkedAsError() throws {
        let inner = #"{"blocks":[{"kind":"paragraph","text":"sorry"}]}"#
        let envelope = """
        {
          "output": [
            {
              "type": "web_search_call",
              "id": "ws_2",
              "status": "failed",
              "action": { "type": "search", "query": "x" }
            },
            {
              "type": "function_call",
              "name": "\(StructuredOutputSchema.toolName)",
              "call_id": "call_x",
              "arguments": \(jsonEscaped(inner))
            }
          ]
        }
        """
        let blocks = try OpenAIService.decodeBlocks(from: Data(envelope.utf8))
        guard case .toolResult(_, _, let isError) = blocks[1] else {
            return XCTFail("expected .toolResult, got \(blocks[1])")
        }
        XCTAssertTrue(isError, "non-completed status should mark the result as error")
    }

    // MARK: - Streaming

    func testStreamingInterleavedWebSearchAndEmitOutput() async throws {
        let json = #"{"blocks":[{"kind":"paragraph","text":"hi"}]}"#
        let events: [SSEEvent] = [
            webSearchCallAdded(id: "ws_1", query: "swift"),
            SSEEvent(event: nil, data: #"{"type":"response.web_search_call.in_progress","item_id":"ws_1"}"#),
            SSEEvent(event: nil, data: #"{"type":"response.web_search_call.searching","item_id":"ws_1"}"#),
            SSEEvent(event: nil, data: #"{"type":"response.web_search_call.completed","item_id":"ws_1"}"#),
            emitOutputCallAdded(itemID: "fc_emit"),
            argumentsDelta(json, itemID: "fc_emit"),
            completedEvent(),
        ]

        let snapshots = try await collect(events)
        XCTAssertFalse(snapshots.isEmpty)

        // The first snapshot should land as soon as the toolCall lands.
        if case .toolCall(let id, let name, _) = snapshots.first?.first {
            XCTAssertEqual(id, "ws_1")
            XCTAssertEqual(name, "web_search")
        } else {
            XCTFail("first snapshot should lead with the .toolCall, got \(String(describing: snapshots.first))")
        }

        let final = snapshots.last ?? []
        XCTAssertEqual(final.count, 3)
        if case .toolCall = final[0], case .toolResult(_, let status, let isError) = final[1] {
            XCTAssertEqual(status, "completed")
            XCTAssertFalse(isError)
        } else {
            XCTFail("expected toolCall + toolResult prefix, got \(final)")
        }
        XCTAssertEqual(final.last, .paragraph(text: "hi"))
    }

    func testStreamingFailedWebSearchMarksError() async throws {
        let json = #"{"blocks":[{"kind":"paragraph","text":"hi"}]}"#
        let events: [SSEEvent] = [
            webSearchCallAdded(id: "ws_x", query: "y"),
            SSEEvent(event: nil, data: #"{"type":"response.web_search_call.failed","item_id":"ws_x"}"#),
            emitOutputCallAdded(itemID: "fc_emit"),
            argumentsDelta(json, itemID: "fc_emit"),
            completedEvent(),
        ]
        let final = (try await collect(events)).last ?? []
        guard case .toolResult(_, let status, let isError) = final[1] else {
            return XCTFail("expected toolResult at index 1, got \(final[1])")
        }
        XCTAssertEqual(status, "failed")
        XCTAssertTrue(isError)
    }

    func testStreamingWebSearchOnlyCompletesEmitOutput() async throws {
        // Sanity check: web_search activity should not interfere with
        // function_call_arguments parsing — the item_id filter at the
        // delta stage must still admit emit_output's deltas.
        let json = #"{"blocks":[{"kind":"heading","text":"H"}]}"#
        let events: [SSEEvent] = [
            webSearchCallAdded(id: "ws_1", query: "q"),
            SSEEvent(event: nil, data: #"{"type":"response.web_search_call.completed","item_id":"ws_1"}"#),
            emitOutputCallAdded(itemID: "fc_emit"),
            argumentsDelta(#"{"q":"poison"}"#, itemID: "ws_1"),
            argumentsDelta(json, itemID: "fc_emit"),
            completedEvent(),
        ]
        let final = (try await collect(events)).last ?? []
        XCTAssertEqual(final.last, .heading(text: "H"))
    }

    // MARK: - Helpers

    private func collect(_ events: [SSEEvent]) async throws -> [[OutputBlock]] {
        let seq = WebSearchEventSequence(events: events)
        var out: [[OutputBlock]] = []
        for try await snapshot in OpenAIService.decodeStream(events: seq) {
            out.append(snapshot)
        }
        return out
    }

    private func webSearchCallAdded(id: String, query: String) -> SSEEvent {
        let data = #"{"type":"response.output_item.added","item":{"type":"web_search_call","id":"\#(id)","status":"in_progress","action":{"type":"search","query":"\#(query)"}}}"#
        return SSEEvent(event: nil, data: data)
    }

    private func emitOutputCallAdded(itemID: String) -> SSEEvent {
        let data = #"{"type":"response.output_item.added","item":{"type":"function_call","name":"\#(StructuredOutputSchema.toolName)","id":"\#(itemID)","call_id":"call_abc"}}"#
        return SSEEvent(event: nil, data: data)
    }

    private func argumentsDelta(_ delta: String, itemID: String) -> SSEEvent {
        let escaped = jsonEscaped(delta)
        let data = #"{"type":"response.function_call_arguments.delta","item_id":"\#(itemID)","delta":\#(escaped)}"#
        return SSEEvent(event: nil, data: data)
    }

    private func completedEvent() -> SSEEvent {
        SSEEvent(event: nil, data: #"{"type":"response.completed"}"#)
    }

    private func jsonEscaped(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}

private struct WebSearchEventSequence: AsyncSequence {
    typealias Element = SSEEvent
    let events: [SSEEvent]
    struct AsyncIterator: AsyncIteratorProtocol {
        var iter: IndexingIterator<[SSEEvent]>
        mutating func next() async throws -> SSEEvent? { iter.next() }
    }
    func makeAsyncIterator() -> AsyncIterator { .init(iter: events.makeIterator()) }
}
