import Foundation

enum WritingOp: String, CaseIterable, Identifiable, Hashable {
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
}
