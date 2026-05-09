import XCTest
@testable import ContextDesk

final class OutputBlockCodingTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    func testParagraphRoundTrip() throws {
        try assertRoundTrip(.paragraph(text: "Hello, world."))
    }

    func testHeadingRoundTrip() throws {
        try assertRoundTrip(.heading(text: "Section"))
    }

    func testBulletListRoundTrip() throws {
        try assertRoundTrip(.bulletList(items: ["one", "two", "three"]))
    }

    func testTableRoundTrip() throws {
        try assertRoundTrip(.table(head: ["A", "B"], rows: [["1", "2"], ["3", "4"]]))
    }

    func testCodeBlockWithLanguageRoundTrip() throws {
        try assertRoundTrip(.codeBlock(language: "swift", code: "let x = 1"))
    }

    func testCodeBlockWithoutLanguageRoundTrip() throws {
        try assertRoundTrip(.codeBlock(language: nil, code: "raw"))
    }

    func testDecodesCanonicalParagraphJSON() throws {
        let json = #"{"kind":"paragraph","text":"hi"}"#
        let block = try decoder.decode(OutputBlock.self, from: Data(json.utf8))
        XCTAssertEqual(block, .paragraph(text: "hi"))
    }

    func testDecodesCanonicalTableJSON() throws {
        let json = #"{"kind":"table","head":["a"],"rows":[["1"],["2"]]}"#
        let block = try decoder.decode(OutputBlock.self, from: Data(json.utf8))
        XCTAssertEqual(block, .table(head: ["a"], rows: [["1"], ["2"]]))
    }

    func testDecodesCodeBlockWithNullLanguage() throws {
        // OpenAI strict mode requires every property to be present, so
        // language arrives as `null` rather than being omitted. The decoder
        // must accept both shapes.
        let json = #"{"kind":"codeBlock","code":"x","language":null}"#
        let block = try decoder.decode(OutputBlock.self, from: Data(json.utf8))
        XCTAssertEqual(block, .codeBlock(language: nil, code: "x"))
    }

    func testToolCallRoundTrip() throws {
        try assertRoundTrip(.toolCall(
            id: "call_abc",
            name: "web_search",
            argumentsJSON: #"{"q":"swift"}"#
        ))
    }

    func testToolResultRoundTrip() throws {
        try assertRoundTrip(.toolResult(
            callID: "call_abc",
            content: "1 result found",
            isError: false
        ))
    }

    func testToolResultErrorRoundTrip() throws {
        try assertRoundTrip(.toolResult(
            callID: "call_xyz",
            content: "rate limited",
            isError: true
        ))
    }

    func testDecodesCanonicalToolCallJSON() throws {
        let json = #"{"arguments":"{\"q\":\"x\"}","id":"c1","kind":"toolCall","name":"search"}"#
        let block = try decoder.decode(OutputBlock.self, from: Data(json.utf8))
        XCTAssertEqual(block, .toolCall(id: "c1", name: "search", argumentsJSON: #"{"q":"x"}"#))
    }

    func testUnknownKindDecodesAsForwardCompatBlock() throws {
        let json = #"{"kind":"futureWidget","label":"Beta","count":3}"#
        let block = try decoder.decode(OutputBlock.self, from: Data(json.utf8))
        guard case .unknown(let kind, _) = block else {
            return XCTFail("expected .unknown, got \(block)")
        }
        XCTAssertEqual(kind, "futureWidget")
    }

    func testUnknownKindRoundTripsAllFields() throws {
        // A future build must be able to re-save a conversation containing a
        // block kind this build doesn't understand without losing fields.
        let json = #"{"count":3,"kind":"futureWidget","label":"Beta","nested":{"flag":true,"items":[1,2.5,"x",null]}}"#
        let block = try decoder.decode(OutputBlock.self, from: Data(json.utf8))
        let re = try encoder.encode(block)
        let reEncoded = try XCTUnwrap(String(data: re, encoding: .utf8))
        // sortedKeys + the original sorted-key fixture should match byte-for-byte.
        XCTAssertEqual(reEncoded, json)
    }

    func testUnknownKindSurvivesAlongsideKnownBlocks() throws {
        let json = #"{"blocks":[{"kind":"paragraph","text":"hi"},{"kind":"futureWidget","data":42}]}"#
        let decoded = try decoder.decode(StructuredOutput.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.blocks.count, 2)
        XCTAssertEqual(decoded.blocks[0], .paragraph(text: "hi"))
        guard case .unknown(let kind, _) = decoded.blocks[1] else {
            return XCTFail("expected .unknown for second block")
        }
        XCTAssertEqual(kind, "futureWidget")
    }

    func testStructuredOutputWrapperRoundTrip() throws {
        let blocks: [OutputBlock] = [
            .heading(text: "Title"),
            .paragraph(text: "Body."),
            .bulletList(items: ["a", "b"]),
        ]
        let wrapped = ["blocks": blocks]
        let data = try encoder.encode(wrapped)
        let decoded = try decoder.decode(StructuredOutput.self, from: data)
        XCTAssertEqual(decoded.blocks, blocks)
    }

    private func assertRoundTrip(_ block: OutputBlock, file: StaticString = #file, line: UInt = #line) throws {
        let data = try encoder.encode(block)
        let decoded = try decoder.decode(OutputBlock.self, from: data)
        XCTAssertEqual(decoded, block, file: file, line: line)
    }
}
