import XCTest
@testable import ContextDesk

final class OpenAIStreamDecodingTests: XCTestCase {
    private let emitItemID = "fc_emit"

    func testHappyPathReconstructsBlocks() async throws {
        let json = #"{"blocks":[{"kind":"heading","text":"Title"},{"kind":"paragraph","text":"Body."}]}"#
        let events = [
            outputItemAddedEvent(itemID: emitItemID),
            argumentsDeltaEvent(json, itemID: emitItemID),
            completedEvent(),
        ]

        let snapshots = try await collect(events)
        XCTAssertFalse(snapshots.isEmpty, "stream must yield at least one snapshot")
        XCTAssertEqual(snapshots.last, [
            .heading(text: "Title"),
            .paragraph(text: "Body."),
        ])
    }

    func testMultipleDeltasYieldMonotoneSnapshots() async throws {
        let json = #"{"blocks":[{"kind":"heading","text":"Title"},{"kind":"paragraph","text":"Body."}]}"#
        let chunks = splitIntoChunks(json, count: 8)

        var events: [SSEEvent] = [outputItemAddedEvent(itemID: emitItemID)]
        events.append(contentsOf: chunks.map { argumentsDeltaEvent($0, itemID: emitItemID) })
        events.append(completedEvent())

        let snapshots = try await collect(events)
        XCTAssertFalse(snapshots.isEmpty)

        for i in 1..<snapshots.count {
            XCTAssertGreaterThanOrEqual(
                snapshots[i].count,
                snapshots[i - 1].count - 1,
                "snapshot block count should not collapse: \(snapshots[i - 1]) -> \(snapshots[i])"
            )
        }

        XCTAssertEqual(snapshots.last, [
            .heading(text: "Title"),
            .paragraph(text: "Body."),
        ])
    }

    func testStreamEndWithoutCompletedStillYieldsFinalSnapshot() async throws {
        let json = #"{"blocks":[{"kind":"paragraph","text":"Hi."}]}"#
        let events = [
            outputItemAddedEvent(itemID: emitItemID),
            argumentsDeltaEvent(json, itemID: emitItemID),
        ]

        let snapshots = try await collect(events)
        XCTAssertEqual(snapshots.last, [.paragraph(text: "Hi.")])
    }

    func testErrorEventThrowsApiError() async throws {
        let errorPayload = #"{"type":"response.error","error":{"message":"rate limit hit","type":"rate_limit_error"}}"#
        let events = [
            outputItemAddedEvent(itemID: emitItemID),
            argumentsDeltaEvent(#"{"blocks":[{"kind":"paragraph","text":"part"#, itemID: emitItemID),
            SSEEvent(event: nil, data: errorPayload),
        ]

        do {
            _ = try await collect(events)
            XCTFail("expected stream to throw")
        } catch let AIWritingServiceError.apiError(message, kind) {
            XCTAssertEqual(message, "rate limit hit")
            XCTAssertEqual(kind, .rateLimited)
        } catch {
            XCTFail("expected .apiError, got \(error)")
        }
    }

    func testCapturesResponseIDFromCreatedEvent() async throws {
        let json = #"{"blocks":[{"kind":"paragraph","text":"hi"}]}"#
        let events: [SSEEvent] = [
            SSEEvent(event: nil, data: #"{"type":"response.created","response":{"id":"resp_abc123"}}"#),
            outputItemAddedEvent(itemID: emitItemID),
            argumentsDeltaEvent(json, itemID: emitItemID),
            completedEvent(),
        ]
        var captured: [String] = []
        let seq = EventSequence(events: events)
        for try await _ in OpenAIService.decodeStream(events: seq, onResponseID: { id in captured.append(id) }) {}
        XCTAssertEqual(captured, ["resp_abc123"], "response.id must be captured exactly once")
    }

    func testCapturesResponseIDFromCompletedEventWhenCreatedAbsent() async throws {
        // If `response.created` was missed, `response.completed` payload
        // also carries the id; we still surface it.
        let json = #"{"blocks":[{"kind":"paragraph","text":"hi"}]}"#
        let events: [SSEEvent] = [
            outputItemAddedEvent(itemID: emitItemID),
            argumentsDeltaEvent(json, itemID: emitItemID),
            SSEEvent(event: nil, data: #"{"type":"response.completed","response":{"id":"resp_xyz"}}"#),
        ]
        var captured: [String] = []
        let seq = EventSequence(events: events)
        for try await _ in OpenAIService.decodeStream(events: seq, onResponseID: { id in captured.append(id) }) {}
        XCTAssertEqual(captured, ["resp_xyz"])
    }

    func testUnknownEventTypesAreIgnored() async throws {
        let json = #"{"blocks":[{"kind":"heading","text":"Hello"}]}"#
        let events: [SSEEvent] = [
            SSEEvent(event: nil, data: #"{"type":"response.created"}"#),
            SSEEvent(event: nil, data: #"{"type":"response.in_progress"}"#),
            SSEEvent(event: nil, data: #"{"type":"response.reasoning_summary_text.delta","delta":"thinking..."}"#),
            outputItemAddedEvent(itemID: emitItemID),
            argumentsDeltaEvent(json, itemID: emitItemID),
            SSEEvent(event: nil, data: #"{"type":"response.function_call_arguments.done","item_id":"\#(emitItemID)"}"#),
            completedEvent(),
        ]

        let snapshots = try await collect(events)
        XCTAssertEqual(snapshots.last, [.heading(text: "Hello")])
    }

    func testIgnoresArgumentDeltasFromOtherTools() async throws {
        // If a future build registers additional tools, their argument
        // deltas must not pollute the emit_output JSON parser.
        let json = #"{"blocks":[{"kind":"paragraph","text":"hi"}]}"#
        let events: [SSEEvent] = [
            outputItemAddedEvent(itemID: emitItemID),
            argumentsDeltaEvent(#"{"q":"unused"}"#, itemID: "fc_other"),
            argumentsDeltaEvent(json, itemID: emitItemID),
            completedEvent(),
        ]
        let snapshots = try await collect(events)
        XCTAssertEqual(snapshots.last, [.paragraph(text: "hi")])
    }

    private func collect(_ events: [SSEEvent]) async throws -> [[OutputBlock]] {
        let seq = EventSequence(events: events)
        var out: [[OutputBlock]] = []
        for try await snapshot in OpenAIService.decodeStream(events: seq) {
            out.append(snapshot)
        }
        return out
    }

    private func argumentsDeltaEvent(_ delta: String, itemID: String) -> SSEEvent {
        let escapedDelta = jsonEscape(delta)
        let data = #"{"type":"response.function_call_arguments.delta","item_id":"\#(itemID)","delta":\#(escapedDelta)}"#
        return SSEEvent(event: nil, data: data)
    }

    private func outputItemAddedEvent(itemID: String) -> SSEEvent {
        let data = #"{"type":"response.output_item.added","item":{"type":"function_call","name":"\#(StructuredOutputSchema.toolName)","id":"\#(itemID)","call_id":"call_abc"}}"#
        return SSEEvent(event: nil, data: data)
    }

    private func completedEvent() -> SSEEvent {
        SSEEvent(event: nil, data: #"{"type":"response.completed"}"#)
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
