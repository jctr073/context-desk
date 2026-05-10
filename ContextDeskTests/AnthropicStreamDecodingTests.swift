import XCTest
@testable import ContextDesk

final class AnthropicStreamDecodingTests: XCTestCase {
    func testHappyPathReconstructsBlocks() async throws {
        let json = #"{"blocks":[{"kind":"heading","text":"Title"},{"kind":"paragraph","text":"Body."}]}"#
        let chunks = splitIntoChunks(json, count: 6)

        var events: [SSEEvent] = [
            toolUseStart(index: 1),
        ]
        for chunk in chunks {
            events.append(deltaEvent(index: 1, partial: chunk))
        }
        events.append(blockStop(index: 1))
        events.append(messageStop())

        let snapshots = try await collect(events)
        XCTAssertFalse(snapshots.isEmpty)
        XCTAssertEqual(snapshots.last, [
            .heading(text: "Title"),
            .paragraph(text: "Body."),
        ])
    }

    func testSkipsLeadingThinkingContentBlock() async throws {
        let json = #"{"blocks":[{"kind":"paragraph","text":"Hi."}]}"#

        let events: [SSEEvent] = [
            // Index 0: thinking block; should be ignored end to end.
            SSEEvent(event: nil, data: #"{"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}"#),
            SSEEvent(event: nil, data: #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"reasoning..."}}"#),
            SSEEvent(event: nil, data: #"{"type":"content_block_stop","index":0}"#),

            // Index 1: our tool use.
            toolUseStart(index: 1),
            deltaEvent(index: 1, partial: json),
            blockStop(index: 1),
            messageStop(),
        ]

        let snapshots = try await collect(events)
        XCTAssertEqual(snapshots.last, [.paragraph(text: "Hi.")])
    }

    func testSkipsDeltasAtNonMatchingIndices() async throws {
        let json = #"{"blocks":[{"kind":"paragraph","text":"OK"}]}"#

        let events: [SSEEvent] = [
            toolUseStart(index: 1),
            // A spurious delta at a different index; must NOT feed the parser.
            deltaEvent(index: 0, partial: #"{"blocks":[{"kind":"paragraph","text":"WRONG"}]}"#),
            deltaEvent(index: 1, partial: json),
            blockStop(index: 1),
            messageStop(),
        ]

        let snapshots = try await collect(events)
        XCTAssertEqual(snapshots.last, [.paragraph(text: "OK")])
    }

    func testErrorEventThrowsApiError() async throws {
        let events: [SSEEvent] = [
            toolUseStart(index: 0),
            deltaEvent(index: 0, partial: #"{"blocks":[{"kind":"paragraph","text":"par"#),
            SSEEvent(event: nil, data: #"{"type":"error","error":{"message":"overloaded"}}"#),
        ]

        do {
            _ = try await collect(events)
            XCTFail("expected stream to throw")
        } catch let AIWritingServiceError.apiError(message, _) {
            XCTAssertEqual(message, "overloaded")
        } catch {
            XCTFail("expected .apiError, got \(error)")
        }
    }

    private func collect(_ events: [SSEEvent]) async throws -> [[OutputBlock]] {
        let seq = EventSequence(events: events)
        var out: [[OutputBlock]] = []
        for try await snapshot in AnthropicService.decodeStream(events: seq) {
            out.append(snapshot)
        }
        return out
    }

    private func toolUseStart(index: Int) -> SSEEvent {
        SSEEvent(
            event: nil,
            data: #"{"type":"content_block_start","index":\#(index),"content_block":{"type":"tool_use","name":"\#(StructuredOutputSchema.toolName)","input":{}}}"#
        )
    }

    private func deltaEvent(index: Int, partial: String) -> SSEEvent {
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

    private func splitIntoChunks(_ s: String, count: Int) -> [String] {
        guard count > 0 else { return [s] }
        let chars = Array(s)
        let size = max(1, chars.count / count)
        var chunks: [String] = []
        var i = 0
        while i < chars.count {
            let end = min(i + size, chars.count)
            chunks.append(String(chars[i..<end]))
            i = end
        }
        return chunks
    }
}

private struct EventSequence: AsyncSequence {
    typealias Element = SSEEvent
    let events: [SSEEvent]

    struct AsyncIterator: AsyncIteratorProtocol {
        var iter: IndexingIterator<[SSEEvent]>
        mutating func next() async throws -> SSEEvent? { iter.next() }
    }

    func makeAsyncIterator() -> AsyncIterator { .init(iter: events.makeIterator()) }
}
