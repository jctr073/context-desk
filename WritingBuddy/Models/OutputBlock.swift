import Foundation

enum OutputBlock: Identifiable, Hashable {
    case paragraph(text: String)
    case heading(text: String)
    case bulletList(items: [String])
    case table(head: [String], rows: [[String]])

    var id: String {
        switch self {
        case .paragraph(let t):    return "p:\(t.hashValue)"
        case .heading(let t):      return "h:\(t.hashValue)"
        case .bulletList(let it):  return "ul:\(it.hashValue)"
        case .table(let h, let r): return "tbl:\(h.hashValue):\(r.hashValue)"
        }
    }
}
