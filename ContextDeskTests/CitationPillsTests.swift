import XCTest
@testable import ContextDesk

final class CitationPillsTests: XCTestCase {

    // MARK: CitationParser

    func testParserPlainText() {
        let segments = CitationParser.parse("just plain prose")
        XCTAssertEqual(segments, [.text("just plain prose")])
    }

    func testParserSingleCite() {
        let input = #"Before <cite index="2-1">cited claim.</cite> after."#
        let segments = CitationParser.parse(input)
        XCTAssertEqual(segments, [
            .text("Before "),
            .cite(claim: "cited claim.", index: "2-1"),
            .text(" after."),
        ])
    }

    func testParserMultipleCites() {
        let input = #"<cite index="1-1">A</cite> mid <cite index="1-2">B</cite>."#
        let segments = CitationParser.parse(input)
        XCTAssertEqual(segments, [
            .cite(claim: "A", index: "1-1"),
            .text(" mid "),
            .cite(claim: "B", index: "1-2"),
            .text("."),
        ])
    }

    func testParserCiteWithoutIndexFallsBackToText() {
        let input = #"Hello <cite>untagged</cite> world"#
        let segments = CitationParser.parse(input)
        XCTAssertEqual(segments, [
            .text("Hello "),
            .text("untagged"),
            .text(" world"),
        ])
    }

    func testParserSingleQuotedIndex() {
        let input = #"<cite index='3-2'>thing</cite>"#
        let segments = CitationParser.parse(input)
        XCTAssertEqual(segments, [.cite(claim: "thing", index: "3-2")])
    }

    func testParserExtraAttributes() {
        let input = #"<cite type="x" index="4-7" foo="bar">thing</cite>"#
        let segments = CitationParser.parse(input)
        XCTAssertEqual(segments, [.cite(claim: "thing", index: "4-7")])
    }

    // MARK: CitationSource

    func testSourceFaviconLetters() {
        let s1 = CitationSource(url: "https://dot.ca.gov/path", title: "x")
        XCTAssertEqual(s1.faviconLetters, "CA")

        let s2 = CitationSource(url: "https://en.wikipedia.org/wiki/x", title: "x")
        XCTAssertEqual(s2.faviconLetters, "WI")

        let s3 = CitationSource(url: "https://www.github.com/x", title: "x")
        XCTAssertEqual(s3.faviconLetters, "GI")
    }

    func testSourceDisplayLabelTakesTitleTail() {
        let s = CitationSource(
            url: "https://dot.ca.gov/x",
            title: "Sonora Pass — Caltrans District 10"
        )
        XCTAssertEqual(s.displayLabel, "Caltrans District 10")
    }

    func testSourceDisplayLabelFallsBackToHostLabel() {
        let s = CitationSource(
            url: "https://example.com/x",
            title: "No separator title"
        )
        XCTAssertEqual(s.displayLabel, "Example")
    }

    // MARK: CitationRegistry

    func testRegistryBuildFromWebSearchHits() {
        let hits = #"[{"url":"https://dot.ca.gov/a","title":"A — Caltrans"},{"url":"https://example.com/b","title":"B — Example"}]"#
        let blocks: [OutputBlock] = [
            .toolCall(id: "t1", name: "web_search", argumentsJSON: #"{"query":"sonora pass"}"#),
            .toolResult(callID: "t1", content: hits, isError: false),
            .paragraph(text: "x"),
        ]
        let reg = CitationRegistry.build(from: blocks)
        XCTAssertEqual(reg.flat.count, 2)
        XCTAssertEqual(reg.lookup("1-1")?.title, "A — Caltrans")
        XCTAssertEqual(reg.lookup("1-2")?.title, "B — Example")
        XCTAssertNil(reg.lookup("9-9"))
    }

    func testRegistrySkipsErroredAndUntilledTools() {
        let blocks: [OutputBlock] = [
            .toolCall(id: "t1", name: "web_search", argumentsJSON: "{}"),
            .toolResult(callID: "t1", content: "boom", isError: true),
            .toolCall(id: "t2", name: "web_search", argumentsJSON: "{}"),
            .toolResult(
                callID: "t2",
                content: #"[{"url":"https://example.com/x","title":"X — Site"}]"#,
                isError: false
            ),
        ]
        let reg = CitationRegistry.build(from: blocks)
        // Errored tool still occupies its index slot (1), good tool is at 2.
        XCTAssertEqual(reg.flat.count, 1)
        XCTAssertEqual(reg.lookup("2-1")?.title, "X — Site")
    }

    // MARK: ProseTextBuilder.autoLinkURLs

    @MainActor
    func testAutoLinkURLsLeavesPlainURLAlone() {
        let s = "See https://example.com for more."
        XCTAssertEqual(ProseTextBuilder.autoLinkURLs(s), s)
    }

    @MainActor
    func testAutoLinkURLsWrapsPlaceholderURL() {
        let s = "Visit https://github.com/<owner>/<repo>/graphs/traffic now."
        let out = ProseTextBuilder.autoLinkURLs(s)
        XCTAssertEqual(
            out,
            #"Visit [https://github.com/\<owner\>/\<repo\>/graphs/traffic](https://github.com/<owner>/<repo>/graphs/traffic) now."#
        )
    }

    @MainActor
    func testAutoLinkURLsTrimsTrailingPunctuation() {
        let s = "URL: https://github.com/<x>/y."
        let out = ProseTextBuilder.autoLinkURLs(s)
        XCTAssertEqual(
            out,
            #"URL: [https://github.com/\<x\>/y](https://github.com/<x>/y)."#
        )
    }

    @MainActor
    func testAutoLinkURLsSkipsAlreadyLinked() {
        let s = "[label](https://github.com/<owner>/x)"
        XCTAssertEqual(ProseTextBuilder.autoLinkURLs(s), s)
    }

    @MainActor
    func testAutoLinkURLsSkipsAngleBracketAutolink() {
        let s = "<https://example.com>"
        XCTAssertEqual(ProseTextBuilder.autoLinkURLs(s), s)
    }

    func testRegistryFallbackToFlatIndex() {
        let hits = #"[{"url":"https://a.com/","title":"A"},{"url":"https://b.com/","title":"B"}]"#
        let blocks: [OutputBlock] = [
            .toolCall(id: "t1", name: "web_search", argumentsJSON: "{}"),
            .toolResult(callID: "t1", content: hits, isError: false),
        ]
        let reg = CitationRegistry.build(from: blocks)
        XCTAssertEqual(reg.lookup("1")?.title, "A")
        XCTAssertEqual(reg.lookup("2")?.title, "B")
    }

    // MARK: ExternalURLPolicy

    func testExternalURLPolicyAllowsHttpAndHttps() {
        XCTAssertEqual(
            ExternalURLPolicy.webURL(from: " https://example.com/path ")?.absoluteString,
            "https://example.com/path"
        )
        XCTAssertEqual(
            ExternalURLPolicy.webURL(from: "http://example.com")?.host,
            "example.com"
        )
    }

    func testExternalURLPolicyRejectsNonWebSchemes() {
        XCTAssertNil(ExternalURLPolicy.webURL(from: "file:///etc/passwd"))
        XCTAssertNil(ExternalURLPolicy.webURL(from: "x-apple.systempreferences:com.apple.preference.security"))
        XCTAssertNil(ExternalURLPolicy.webURL(from: "mailto:test@example.com"))
    }

    func testExternalURLPolicyRequiresHost() {
        XCTAssertNil(ExternalURLPolicy.webURL(from: "https:///missing-host"))
        XCTAssertNil(ExternalURLPolicy.webURL(from: "not a url"))
    }
}
