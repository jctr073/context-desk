import Foundation

enum OutputBlock: Identifiable, Hashable, Codable {
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

private enum OutputBlockKind: String, Codable {
    case paragraph
    case heading
    case bulletList
    case table
}

private enum OutputBlockCodingKeys: String, CodingKey {
    case kind
    case text
    case items
    case head
    case rows
}

extension OutputBlock {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: OutputBlockCodingKeys.self)
        let kind = try container.decode(OutputBlockKind.self, forKey: .kind)

        switch kind {
        case .paragraph:
            self = .paragraph(text: try container.decode(String.self, forKey: .text))
        case .heading:
            self = .heading(text: try container.decode(String.self, forKey: .text))
        case .bulletList:
            self = .bulletList(items: try container.decode([String].self, forKey: .items))
        case .table:
            self = .table(
                head: try container.decode([String].self, forKey: .head),
                rows: try container.decode([[String]].self, forKey: .rows)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: OutputBlockCodingKeys.self)

        switch self {
        case .paragraph(let text):
            try container.encode(OutputBlockKind.paragraph, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .heading(let text):
            try container.encode(OutputBlockKind.heading, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .bulletList(let items):
            try container.encode(OutputBlockKind.bulletList, forKey: .kind)
            try container.encode(items, forKey: .items)
        case .table(let head, let rows):
            try container.encode(OutputBlockKind.table, forKey: .kind)
            try container.encode(head, forKey: .head)
            try container.encode(rows, forKey: .rows)
        }
    }
}
