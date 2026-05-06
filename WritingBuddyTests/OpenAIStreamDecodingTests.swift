import XCTest
@testable import WritingBuddy

final class OpenAIStreamDecodingTests: XCTestCase {
    func testHappyPathReconstructsBlocks() async throws {
        let json = #"{"blocks":[{"kind":"heading","text":"Title"},{"kind":"paragraph","text":"Body."}]}"#
        let events = [
            deltaEvent(json),
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

        var events: [SSEEvent] = chunks.map { deltaEvent($0) }
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
        let events = [deltaEvent(json)]

        let snapshots = try await collect(events)
        XCTAssertEqual(snapshots.last, [.paragraph(text: "Hi.")])
    }

    func testErrorEventThrowsApiError() async throws {
        let errorPayload = #"{"type":"response.error","error":{"message":"rate limit hit"}}"#
        let events = [
            deltaEvent(#"{"blocks":[{"kind":"paragraph","text":"part"#),
            SSEEvent(event: nil, data: errorPayload),
        ]

        do {
            _ = try await collect(events)
            XCTFail("expected stream to throw")
        } catch let AIWritingServiceError.apiError(message) {
            XCTAssertEqual(message, "rate limit hit")
        } catch {
            XCTFail("expected .apiError, got \(error)")
        }
    }

    func testUnknownEventTypesAreIgnored() async throws {
        let json = #"{"blocks":[{"kind":"heading","text":"Hello"}]}"#
        let events: [SSEEvent] = [
            SSEEvent(event: nil, data: #"{"type":"response.created"}"#),
            SSEEvent(event: nil, data: #"{"type":"response.in_progress"}"#),
            SSEEvent(event: nil, data: #"{"type":"response.reasoning_summary_text.delta","delta":"thinking..."}"#),
            SSEEvent(event: nil, data: #"{"type":"response.output_item.added"}"#),
            deltaEvent(json),
            SSEEvent(event: nil, data: #"{"type":"response.output_text.done"}"#),
            completedEvent(),
        ]

        let snapshots = try await collect(events)
        XCTAssertEqual(snapshots.last, [.heading(text: "Hello")])
    }

    private func collect(_ events: [SSEEvent]) async throws -> [[OutputBlock]] {
        let seq = EventSequence(events: events)
        var out: [[OutputBlock]] = []
        for try await snapshot in OpenAIService.decodeStream(events: seq) {
            out.append(snapshot)
        }
        return out
    }

    private func deltaEvent(_ delta: String) -> SSEEvent {
        let escaped = jsonEscape(delta)
        return SSEEvent(event: nil, data: #"{"type":"response.output_text.delta","delta":"# + escaped + "}")
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
