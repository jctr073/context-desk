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
