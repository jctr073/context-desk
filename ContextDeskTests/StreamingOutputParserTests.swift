import XCTest
@testable import ContextDesk

final class StreamingOutputParserTests: XCTestCase {
    private let decoder = JSONDecoder()

    private let mixedJSON: String =
        #"{"blocks":[{"kind":"heading","text":"Title"},{"kind":"paragraph","text":"Hello, world."},{"kind":"bulletList","items":["alpha","beta","gamma"]},{"kind":"table","head":["A","B"],"rows":[["1","2"],["3","4"]]},{"kind":"codeBlock","code":"let x = 1","language":"swift"}]}"#

    func testWholeStringFeedMatchesCanonicalDecode() throws {
        let json = mixedJSON
        let parser = StreamingOutputParser()
        parser.feed(json)
        let streamed = try parser.finish()
        let canonical = try decoder.decode(StructuredOutput.self, from: Data(json.utf8)).blocks
        XCTAssertEqual(streamed, canonical)
        XCTAssertEqual(parser.snapshot, canonical)
    }

    func testPrefixByPrefixCompletedPrefixMatchesCanonical() throws {
        let json = mixedJSON
        let bytes = Array(json.utf8)
        let canonical = try decoder.decode(StructuredOutput.self, from: Data(json.utf8)).blocks

        var maxCompleted = 0
        for end in 1...bytes.count {
            let parser = StreamingOutputParser()
            if let s = String(bytes: Array(bytes[0..<end]), encoding: .utf8) {
                parser.feed(s)
                let snap = parser.snapshot
                // The number of canonical blocks that match snapshot exactly
                // from the front is the parser's completed-block count.
                var matched = 0
                let bound = min(snap.count, canonical.count)
                while matched < bound && snap[matched] == canonical[matched] {
                    matched += 1
                }
                // matched-count must be non-decreasing as we add bytes.
                XCTAssertGreaterThanOrEqual(matched, maxCompleted)
                maxCompleted = max(maxCompleted, matched)
                // Snapshot length is at most matched + 1 (optional preview).
                XCTAssertLessThanOrEqual(snap.count, matched + 1)
            }
        }
        XCTAssertEqual(maxCompleted, canonical.count)
    }

    func testParagraphWithCitationsParsesEnd() throws {
        // The streaming parser only renders text in its preview path. The
        // structured `citations` field arrives at the *end* of a block, so
        // it materializes only once `finish()` (or a closing brace) is
        // observed. This test pins that contract.
        let json = #"{"blocks":[{"kind":"paragraph","text":"X is true.","citations":[{"tool_call_id":"ws_1","hit_index":2}]}]}"#
        let parser = StreamingOutputParser()
        parser.feed(json)
        let result = try parser.finish()
        XCTAssertEqual(result, [
            .paragraph(text: "X is true.", citations: [Citation(toolCallID: "ws_1", hitIndex: 2)]),
        ])
    }

    func testSplitInMiddleOfText() throws {
        let json = #"{"blocks":[{"kind":"paragraph","text":"hello"}]}"#
        let parts = [
            #"{"blocks":[{"kind":"paragraph","text":"hel"#,
            #"lo"}]}"#,
        ]
        XCTAssertEqual(parts.joined(), json)
        let parser = StreamingOutputParser()
        parser.feed(parts[0])
        let mid = parser.snapshot
        XCTAssertEqual(mid, [.paragraph(text: "hel")])
        parser.feed(parts[1])
        let final = try parser.finish()
        XCTAssertEqual(final, [.paragraph(text: "hello")])
    }

    func testSplitInMiddleOfEscapedQuote() throws {
        let json = #"{"blocks":[{"kind":"paragraph","text":"a\"b"}]}"#
        let canonical = try decoder.decode(StructuredOutput.self, from: Data(json.utf8)).blocks
        XCTAssertEqual(canonical, [.paragraph(text: "a\"b")])

        let splitIndex = json.range(of: "\\\"")!.lowerBound
        let i = json.distance(from: json.startIndex, to: splitIndex) + 1
        let first = String(json.prefix(i))
        let rest = String(json.suffix(json.count - i))
        XCTAssertEqual(first + rest, json)

        let parser = StreamingOutputParser()
        parser.feed(first)
        // Mid-split: trailing lone backslash must be dropped from preview.
        if case let .paragraph(text, _)? = parser.snapshot.last {
            XCTAssertFalse(text.contains("\\"))
        }
        parser.feed(rest)
        let result = try parser.finish()
        XCTAssertEqual(result, canonical)
    }

    func testSplitInMiddleOfUnicodeEscape() throws {
        // JSON with explicit é escape so we can split in the middle.
        let json = "{\"blocks\":[{\"kind\":\"paragraph\",\"text\":\"caf\\u00e9\"}]}"
        let canonical = try decoder.decode(StructuredOutput.self, from: Data(json.utf8)).blocks
        XCTAssertEqual(canonical, [.paragraph(text: "café")])

        let marker = "\\u00"
        let r = json.range(of: marker)!
        let cutPos = json.index(r.lowerBound, offsetBy: marker.count)
        let first = String(json[..<cutPos])
        let rest = String(json[cutPos...])
        XCTAssertEqual(first + rest, json)

        let parser = StreamingOutputParser()
        parser.feed(first)
        // The partial \u00 (with fewer than 4 hex digits) must be dropped.
        if case let .paragraph(text, _)? = parser.snapshot.last {
            XCTAssertEqual(text, "caf")
        } else {
            XCTFail("expected paragraph preview")
        }
        parser.feed(rest)
        let result = try parser.finish()
        XCTAssertEqual(result, canonical)
    }

    func testSplitJustAfterClosingBrace() throws {
        let json = #"{"blocks":[{"kind":"heading","text":"Hi"},{"kind":"paragraph","text":"there"}]}"#
        let canonical = try decoder.decode(StructuredOutput.self, from: Data(json.utf8)).blocks
        let firstClose = json.range(of: "\"Hi\"}")!.upperBound
        let i = json.distance(from: json.startIndex, to: firstClose)
        let first = String(json.prefix(i))
        let rest = String(json.suffix(json.count - i))
        XCTAssertEqual(first + rest, json)

        let parser = StreamingOutputParser()
        parser.feed(first)
        XCTAssertEqual(parser.snapshot, [.heading(text: "Hi")])
        parser.feed(rest)
        let result = try parser.finish()
        XCTAssertEqual(result, canonical)
    }

    func testSplitBetweenTopLevelObjects() throws {
        let json = #"{"blocks":[{"kind":"heading","text":"A"},{"kind":"heading","text":"B"}]}"#
        let canonical = try decoder.decode(StructuredOutput.self, from: Data(json.utf8)).blocks
        let r = json.range(of: "},")!
        let i = json.distance(from: json.startIndex, to: r.upperBound)
        let first = String(json.prefix(i))
        let rest = String(json.suffix(json.count - i))
        XCTAssertEqual(first + rest, json)

        let parser = StreamingOutputParser()
        parser.feed(first)
        XCTAssertEqual(parser.snapshot, [.heading(text: "A")])
        parser.feed(rest)
        let result = try parser.finish()
        XCTAssertEqual(result, canonical)
    }

    func testMidParagraphPreview() {
        let parser = StreamingOutputParser()
        parser.feed(#"{"blocks":[{"kind":"paragraph","text":"partial..."#)
        XCTAssertEqual(parser.snapshot, [.paragraph(text: "partial...")])
    }

    func testMidHeadingPreview() {
        let parser = StreamingOutputParser()
        parser.feed(#"{"blocks":[{"kind":"heading","text":"Sec"#)
        XCTAssertEqual(parser.snapshot, [.heading(text: "Sec")])
    }

    func testBulletListPreviewClosedAndPartial() {
        let parser = StreamingOutputParser()
        // "one" is closed; "tw" is mid-string with no closing quote yet.
        parser.feed("{\"blocks\":[{\"kind\":\"bulletList\",\"items\":[\"one\",\"tw")
        XCTAssertEqual(parser.snapshot, [.bulletList(items: ["one", "tw"])])
    }

    func testBulletListPreviewBetweenItems() {
        let parser = StreamingOutputParser()
        // Comma-only between items: no trailing string yet, only the closed
        // items show.
        parser.feed(#"{"blocks":[{"kind":"bulletList","items":["one","two","#)
        if case let .bulletList(items)? = parser.snapshot.last {
            XCTAssertEqual(items.prefix(2).map { $0 }, ["one", "two"])
        } else {
            XCTFail("expected bulletList preview")
        }
    }

    func testTableNoPreview() {
        let parser = StreamingOutputParser()
        parser.feed(#"{"blocks":[{"kind":"table","head":["A","B"],"rows":[["1","#)
        // Table preview is intentionally skipped.
        XCTAssertEqual(parser.snapshot, [])
    }

    func testCodeBlockNoPreview() {
        let parser = StreamingOutputParser()
        parser.feed(#"{"blocks":[{"kind":"codeBlock","code":"let x"#)
        XCTAssertEqual(parser.snapshot, [])
    }

    func testCanonicalParseAfterFullStream() throws {
        let json = mixedJSON
        let bytes = Array(json.utf8)
        let parser = StreamingOutputParser()
        var i = 0
        let chunkSize = 7
        while i < bytes.count {
            let end = min(i + chunkSize, bytes.count)
            let slice = Array(bytes[i..<end])
            if let s = String(bytes: slice, encoding: .utf8) {
                parser.feed(s)
            }
            i = end
        }
        let canonical = try decoder.decode(StructuredOutput.self, from: Data(json.utf8)).blocks
        let finished = try parser.finish()
        XCTAssertEqual(finished, canonical)
    }

    func testEAcuteEscapeAcrossSplit() throws {
        let json = "{\"blocks\":[{\"kind\":\"paragraph\",\"text\":\"caf\\u00e9\"}]}"
        let canonical = try decoder.decode(StructuredOutput.self, from: Data(json.utf8)).blocks
        XCTAssertEqual(canonical, [.paragraph(text: "café")])

        let marker = "\\u00"
        let r = json.range(of: marker)!
        let cutPos = json.index(r.lowerBound, offsetBy: 3)
        let first = String(json[..<cutPos])
        let rest = String(json[cutPos...])
        XCTAssertEqual(first + rest, json)

        let parser = StreamingOutputParser()
        parser.feed(first)
        parser.feed(rest)
        let finished = try parser.finish()
        XCTAssertEqual(finished, canonical)
    }

    func testSnapshotPreviewReplacedByCanonicalOnClose() throws {
        let parser = StreamingOutputParser()
        parser.feed(#"{"blocks":[{"kind":"paragraph","text":"hel"#)
        XCTAssertEqual(parser.snapshot, [.paragraph(text: "hel")])
        parser.feed(#"lo"}"#)
        XCTAssertEqual(parser.snapshot, [.paragraph(text: "hello")])
        parser.feed("]}")
        XCTAssertEqual(parser.snapshot, [.paragraph(text: "hello")])
        let finished = try parser.finish()
        XCTAssertEqual(finished, [.paragraph(text: "hello")])
    }
}
