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
