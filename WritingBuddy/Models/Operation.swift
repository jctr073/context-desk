import Foundation

enum WritingOp: String, CaseIterable, Identifiable, Hashable, Codable {
    case rephrase
    case expand
    case shorten
    case cleanup

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rephrase: return "Rephrase"
        case .expand:   return "Expand"
        case .shorten:  return "Shorten"
        case .cleanup:  return "Clean up"
        }
    }

    var sfSymbol: String {
        switch self {
        case .rephrase: return "arrow.triangle.2.circlepath"
        case .expand:   return "arrow.left.and.right"
        case .shorten:  return "chevron.right.2"
        case .cleanup:  return "wand.and.stars"
        }
    }

    var keyEquivalent: String {
        switch self {
        case .rephrase: return "1"
        case .expand:   return "2"
        case .shorten:  return "3"
        case .cleanup:  return "4"
        }
    }

    var kbdHint: String { "\u{2318}\(keyEquivalent)" }

    var openAIInstructions: String {
        switch self {
        case .rephrase:
            return """
            Rephrase the user's writing. Preserve the original meaning and important details, improve wording and flow, and keep roughly the same length.
            """
        case .expand:
            return """
            Expand the user's writing. Preserve the original meaning, add useful context and connective detail without inventing facts, and improve clarity and flow.
            """
        case .shorten:
            return """
            Shorten the user's writing. Preserve the core meaning and important details, remove redundancy, and keep it concise and clear.
            """
        case .cleanup:
            return """
            Clean up the user's writing. Preserve the original meaning, keep it concise, fix grammar and punctuation, and improve clarity and flow.
            """
        }
    }
}
