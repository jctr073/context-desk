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
}
