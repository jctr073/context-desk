import Foundation

/// The container/wire format the output is rendered in (independent of shape).
/// Mirrors the FORMATS list in the v3 prototype's `wb-shell.jsx`.
enum OutputContainerFormat: String, CaseIterable, Identifiable, Hashable, Codable {
    case markdown
    case slack
    case plain
    case html

    var id: String { rawValue }

    var label: String {
        switch self {
        case .markdown: return "Markdown"
        case .slack:    return "Slack"
        case .plain:    return "Plain text"
        case .html:     return "HTML"
        }
    }

    var sfSymbol: String {
        switch self {
        case .markdown: return "text.alignleft"
        case .slack:    return "bubble.left"
        case .plain:    return "text.justify"
        case .html:     return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Formats not yet wired up — shown with a "Soon" tag and disabled.
    var isAvailable: Bool {
        switch self {
        case .markdown, .slack: return true
        case .plain, .html:     return false
        }
    }

    func apiGuidance(formats: Set<OutputFormat>) -> String {
        switch self {
        case .markdown:
            return """
            Container format: Markdown.
            Return Markdown only, with no code fence around the whole response, preamble, or explanation.
            Use '-' bullets for bullet lists and GitHub-style pipe tables when a table is requested.
            """

        case .slack:
            return """
            Container format: Slack mrkdwn, ready to paste into Slack.
            Return Slack mrkdwn only, with no code fence around the whole response, preamble, or explanation.
            Use Slack syntax rather than standard Markdown:
            - Bold with *text*, italic with _text_, strikethrough with ~text~, inline code with `text`, and code blocks with triple backticks without language hints.
            - Use '-' or numbered lists. Use > for quoted lines and >>> only when everything after it should be quoted.
            - Use Slack links like <https://example.com|label>; do not use [label](https://example.com).
            - Preserve existing @mentions, #channels, emoji names, and Slack ID tokens. Do not create broadcast pings like <!here>, <!channel>, or <!everyone> unless the user explicitly asks for them.
            - Do not use Markdown headings (#), double-star bold, pipe tables, HTML, or Block Kit JSON unless the user explicitly asks for JSON.
            \(slackTableGuidance(formats: formats))
            """

        case .plain:
            return """
            Container format: Plain text.
            Return plain text only, with no Markdown, code fence around the whole response, preamble, or explanation.
            """

        case .html:
            return """
            Container format: HTML.
            Return HTML only, with no Markdown, code fence around the whole response, preamble, or explanation.
            """
        }
    }

    private func slackTableGuidance(formats: Set<OutputFormat>) -> String {
        guard formats.isEmpty || formats.contains(.tables) else {
            return "If structured comparison is useful, use short labeled bullets rather than a table."
        }

        return """
        Slack does not render Markdown tables. If a table is requested, use aligned columns inside a plain triple-backtick code block, or use short labeled bullets if that is clearer.
        """
    }
}
