import Foundation

enum PaneLayout: String, CaseIterable, Identifiable {
    case stacked
    case side

    var id: String { rawValue }
    var label: String {
        switch self {
        case .stacked: return "Stacked"
        case .side:    return "Side-by-side"
        }
    }
}
