import Foundation

enum WritingMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case writing
    case chat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .writing: return "Writing"
        case .chat:    return "Chat & Tasks"
        }
    }

    var sfSymbol: String {
        switch self {
        case .writing: return "pencil"
        case .chat:    return "bubble.left"
        }
    }
}

protocol Operation {
    var id: String { get }
    var label: String { get }
    var sfSymbol: String { get }
    var keyEquivalent: String { get }
    var kbdHint: String { get }
    var instructions: String { get }
}

extension Operation {
    var kbdHint: String { "\u{2318}\(keyEquivalent)" }
}

enum WritingOp: String, CaseIterable, Identifiable, Hashable, Codable, Operation {
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

    var instructions: String {
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

enum ChatOp: String, CaseIterable, Identifiable, Hashable, Codable, Operation {
    case ask
    case plan
    case summarize
    case compare
    case translate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ask:       return "Ask"
        case .plan:      return "Plan"
        case .summarize: return "Summarize"
        case .compare:   return "Compare"
        case .translate: return "Translate"
        }
    }

    var sfSymbol: String {
        switch self {
        case .ask:       return "questionmark.circle"
        case .plan:      return "checklist"
        case .summarize: return "text.alignleft"
        case .compare:   return "arrow.left.arrow.right"
        case .translate: return "character.bubble"
        }
    }

    var keyEquivalent: String {
        switch self {
        case .ask:       return "1"
        case .plan:      return "2"
        case .summarize: return "3"
        case .compare:   return "4"
        case .translate: return "5"
        }
    }

    var instructions: String {
        switch self {
        case .ask:
            return """
            Answer the user's question directly and clearly. Use the input as the question and any context as supporting material. Be concise and factual; if uncertain, say so.
            """
        case .plan:
            return """
            Produce a step-by-step plan or outline for the task described in the input. Use a numbered list of concrete, actionable steps. Group related steps under short headings when helpful.
            """
        case .summarize:
            return """
            Summarize the input. Capture the key points and important details in a tight, readable form. Prefer short paragraphs or a small bullet list; do not invent content not present in the input.
            """
        case .compare:
            return """
            Compare the items, options, or alternatives described in the input. Surface the meaningful tradeoffs and, if asked or clearly implied, recommend a choice with brief reasoning. A short table is welcome when the comparison is structured.
            """
        case .translate:
            return """
            Translate the input. If the target language is specified in the input or context, use that; otherwise translate to clear, natural English. Preserve meaning, tone, and any technical terms.
            """
        }
    }
}

/// Resolve an operation by mode + id, used when rehydrating history items.
enum OperationCatalog {
    static func operation(for mode: WritingMode, id: String) -> Operation? {
        switch mode {
        case .writing: return WritingOp(rawValue: id)
        case .chat:    return ChatOp(rawValue: id)
        }
    }

    static func defaultOp(for mode: WritingMode) -> Operation {
        switch mode {
        case .writing: return WritingOp.cleanup
        case .chat:    return ChatOp.ask
        }
    }
}
