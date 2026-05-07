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
}
