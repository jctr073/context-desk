import XCTest
@testable import WritingBuddy

final class SSEEventStreamTests: XCTestCase {
    func testSingleNamedEvent() async throws {
        let events = try await collect(from: "event: foo\ndata: hello\n\n")
        XCTAssertEqual(events, [SSEEvent(event: "foo", data: "hello")])
    }

    func testSingleDataEventWithoutEventField() async throws {
        let events = try await collect(from: "data: hello\n\n")
        XCTAssertEqual(events, [SSEEvent(event: nil, data: "hello")])
    }

    func testMultiLineDataJoinedWithNewline() async throws {
        let events = try await collect(from: "data: line1\ndata: line2\n\n")
        XCTAssertEqual(events, [SSEEvent(event: nil, data: "line1\nline2")])
    }

    func testCommentLinesAreIgnored() async throws {
        let events = try await collect(from: ": keep-alive\ndata: hi\n\n")
        XCTAssertEqual(events, [SSEEvent(event: nil, data: "hi")])
    }

    func testCRLFEndingsBehaveLikeLF() async throws {
        let events = try await collect(from: "event: foo\r\ndata: hello\r\n\r\n")
        XCTAssertEqual(events, [SSEEvent(event: "foo", data: "hello")])
    }

    /// `URLSession.AsyncBytes.lines` splits on `\n` only and leaves a trailing
    /// `\r` attached to each line — feeding such lines must still produce
    /// correctly-parsed events (otherwise no flush ever happens).
    func testTrailingCRPreservedOnEachLineIsStripped() async throws {
        let lines: [String] = [
            "event: foo\r",
            "data: hello\r",
            "\r",
        ]
        let seq = LineSequence(lines: lines)
        var out: [SSEEvent] = []
        for try await event in SSEEventStream.events(fromLines: seq) {
            out.append(event)
        }
        XCTAssertEqual(out, [SSEEvent(event: "foo", data: "hello")])
    }

    func testMultipleEventsBackToBack() async throws {
        let raw = "event: a\ndata: 1\n\nevent: b\ndata: 2\n\n"
        let events = try await collect(from: raw)
        XCTAssertEqual(events, [
            SSEEvent(event: "a", data: "1"),
            SSEEvent(event: "b", data: "2"),
        ])
    }

    func testTrailingEventFlushedOnStreamEnd() async throws {
        let events = try await collect(from: "event: foo\ndata: hello\n")
        XCTAssertEqual(events, [SSEEvent(event: "foo", data: "hello")])
    }

    func testTrailingEventNotFlushedWhenNoDataLines() async throws {
        let events = try await collect(from: "event: foo\n")
        XCTAssertEqual(events, [])
    }

    func testOneOptionalLeadingSpaceStripped() async throws {
        let noSpace = try await collect(from: "data:hi\n\n")
        XCTAssertEqual(noSpace, [SSEEvent(event: nil, data: "hi")])

        let oneSpace = try await collect(from: "data: hi\n\n")
        XCTAssertEqual(oneSpace, [SSEEvent(event: nil, data: "hi")])

        let twoSpaces = try await collect(from: "data:  hi\n\n")
        XCTAssertEqual(twoSpaces, [SSEEvent(event: nil, data: " hi")])
    }

    private func collect(from raw: String) async throws -> [SSEEvent] {
        let lines = splitSSELines(raw)
        let seq = LineSequence(lines: lines)
        var out: [SSEEvent] = []
        for try await event in SSEEventStream.events(fromLines: seq) {
            out.append(event)
        }
        return out
    }

    private func splitSSELines(_ raw: String) -> [String] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}

private struct LineSequence: AsyncSequence {
    typealias Element = String
    let lines: [String]

    struct AsyncIterator: AsyncIteratorProtocol {
        var iter: IndexingIterator<[String]>
        mutating func next() async throws -> String? { iter.next() }
    }

    func makeAsyncIterator() -> AsyncIterator { .init(iter: lines.makeIterator()) }
}
