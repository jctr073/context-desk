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
            return "Bullets: include a concise bullet list."
        case .tables:
            return "Tables: include a compact table-like structure. If the content has no obvious rows and columns, use a short key/value structure."
        }
    }

    static func guidance(for formats: Set<OutputFormat>, containerFormat: OutputContainerFormat) -> String {
        let shapeGuidance: String

        guard !formats.isEmpty else {
            shapeGuidance = """
            Output shape: choose whichever shape best fits the content: paragraphs, a bullet list, a compact table-like structure, or a mix. Pick what makes the result clearest for the reader.
            """

            return """
            \(shapeGuidance)

            \(containerFormat.apiGuidance(formats: formats))
            """
        }

        let selected = allCases.filter { formats.contains($0) }
        let names = selected.map(\.label).joined(separator: ", ")
        let guidance = selected
            .map(\.guidance)
            .map { "- \($0)" }
            .joined(separator: "\n")

        shapeGuidance = """
        Requested output shapes: \(names).
        Use only the requested formats. If multiple formats are requested, return a mix that includes each requested format in this order: Paragraphs, Bullets, Tables.
        \(guidance)
        """

        return """
        \(shapeGuidance)

        \(containerFormat.apiGuidance(formats: formats))
        """
    }
}
