import Foundation

enum OutputFormat: String, CaseIterable, Identifiable, Hashable, Codable {
    case paragraphs
    case bullets
    case tables

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paragraphs: return "Paragraphs"
        case .bullets:    return "Bullets"
        case .tables:     return "Tables"
        }
    }

    var sfSymbol: String {
        switch self {
        case .paragraphs: return "text.alignleft"
        case .bullets:    return "list.bullet"
        case .tables:     return "tablecells"
        }
    }

    var guidance: String {
        switch self {
        case .paragraphs:
            return "Paragraphs: include one or more polished paragraphs for the revised text."
        case .bullets:
            return "Bullets: include a concise Markdown bullet list using '-' bullets."
        case .tables:
            return "Tables: include a compact Markdown table. If the content has no obvious rows and columns, use a short key/value table."
        }
    }

    static func guidance(for formats: Set<OutputFormat>) -> String {
        guard !formats.isEmpty else {
            return """
            Output format: choose whichever shape best fits the content \u{2014} paragraphs, a Markdown bullet list using '-' bullets, a compact Markdown table, or a mix. Pick what makes the result clearest for the reader.
            Return Markdown only, with no code fence, preamble, or explanation.
            """
        }

        let selected = allCases.filter { formats.contains($0) }
        let names = selected.map(\.label).joined(separator: ", ")
        let guidance = selected
            .map(\.guidance)
            .map { "- \($0)" }
            .joined(separator: "\n")

        return """
        Requested formats: \(names).
        Return Markdown only, with no code fence, preamble, or explanation.
        Use only the requested formats. If multiple formats are requested, return a mix that includes each requested format in this order: Paragraphs, Bullets, Tables.
        \(guidance)
        """
    }
}
