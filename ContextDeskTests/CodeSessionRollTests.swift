import XCTest
@testable import ContextDesk

final class CodeSessionRollTests: XCTestCase {

    private func codeUnit(
        id: String = "c",
        code: String,
        isError: Bool = false,
        running: Bool = false
    ) -> ToolUnit {
        let args = #"{"code":"\#(code.replacingOccurrences(of: "\"", with: "\\\""))"}"#
        return ToolUnit(
            call: (id, "code_execution", args),
            result: running ? nil : (content: "ok", isError: isError)
        )
    }

    private func searchUnit(id: String = "s") -> ToolUnit {
        ToolUnit(
            call: (id, "web_search", #"{"query":"x"}"#),
            result: (content: #"[{"url":"https://example.com/","title":"x"}]"#, isError: false)
        )
    }

    // MARK: subCluster

    func testSubClusterAllCode() {
        let units = [codeUnit(id: "1", code: "a()"), codeUnit(id: "2", code: "b()")]
        let subs = ToolUnitWalker.subCluster(units)
        XCTAssertEqual(subs.count, 1)
        if case .codeRun(let run) = subs[0] {
            XCTAssertEqual(run.count, 2)
        } else {
            XCTFail("expected codeRun")
        }
    }

    func testSubClusterMixedSplitsCodeRunsFromSingles() {
        let units = [
            searchUnit(id: "s1"),
            codeUnit(id: "c1", code: "a()"),
            codeUnit(id: "c2", code: "b()"),
            searchUnit(id: "s2"),
            codeUnit(id: "c3", code: "c()"),
        ]
        let subs = ToolUnitWalker.subCluster(units)
        XCTAssertEqual(subs.count, 4)
        guard case .single = subs[0],
              case .codeRun(let run) = subs[1],
              case .single = subs[2],
              case .codeRun(let tail) = subs[3]
        else { return XCTFail("unexpected sub-cluster pattern") }
        XCTAssertEqual(run.count, 2)
        XCTAssertEqual(tail.count, 1)
    }

    func testSubClusterEmpty() {
        XCTAssertTrue(ToolUnitWalker.subCluster([]).isEmpty)
    }

    func testSubClusterAllSearches() {
        let units = [searchUnit(id: "1"), searchUnit(id: "2")]
        let subs = ToolUnitWalker.subCluster(units)
        XCTAssertEqual(subs.count, 2)
        for s in subs {
            if case .single = s { continue } else { XCTFail("expected single") }
        }
    }

    // MARK: ToolKind code coverage

    func testToolKindCodeMatchesAllCodeNames() {
        XCTAssertEqual(ToolKind.from(name: "code_execution"), .code)
        XCTAssertEqual(ToolKind.from(name: "bash_code_execution"), .code)
        XCTAssertEqual(ToolKind.from(name: "bash"), .code)
        XCTAssertEqual(ToolKind.from(name: "computer"), .code)
    }

    func testExtractedArgumentReturnsFirstNonEmptyLineForCode() {
        let args = #"{"code":"\n\nimport json\nx = 1\n"}"#
        let line = ToolResultParser.extractedArgument(name: "code_execution", argumentsJSON: args)
        XCTAssertEqual(line, "import json")
    }

    func testExtractedArgumentReturnsBashCommand() {
        let args = #"{"command":"ls -la"}"#
        let line = ToolResultParser.extractedArgument(name: "bash", argumentsJSON: args)
        XCTAssertEqual(line, "ls -la")
    }
}
