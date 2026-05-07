import XCTest
@testable import ContextDesk

final class SubmitPromptTests: XCTestCase {
    func testInstructionsIncludeEmDashRule() {
        let prompt = makePrompt()
        XCTAssertTrue(prompt.instructions.contains("Never use em dashes"),
                      "Global em-dash rule must remain in the system prompt")
    }

    func testInstructionsOmitDeletedFormatGuidance() {
        // Regression guard: these phrases came from the now-deleted
        // OutputFormat.guidance / OutputContainerFormat.apiGuidance helpers.
        // Structured outputs replace prompt-driven format guidance with the
        // schema, so these strings must not reappear in the prompt.
        let prompt = makePrompt()
        XCTAssertFalse(prompt.instructions.contains("Container format:"))
        XCTAssertFalse(prompt.instructions.contains("Return Markdown only"))
        XCTAssertFalse(prompt.instructions.contains("Output shape"))
        XCTAssertFalse(prompt.instructions.contains("Requested output shapes"))
    }

    func testCustomInstructionsAreIncludedWhenPresent() {
        let prompt = SubmitPrompt(
            model: .gpt55Medium,
            operation: WritingOp.rephrase,
            input: "x",
            context: "",
            customInstructions: "Speak in pirate."
        )
        XCTAssertTrue(prompt.instructions.contains("Speak in pirate."))
    }

    private func makePrompt() -> SubmitPrompt {
        SubmitPrompt(
            model: .gpt55Medium,
            operation: WritingOp.rephrase,
            input: "Hello world",
            context: "",
            customInstructions: ""
        )
    }
}
