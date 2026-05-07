import Foundation

enum RenderMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case rendered
    case raw

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rendered: return "Rendered"
        case .raw:      return "Raw"
        }
    }
}
