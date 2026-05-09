import Foundation

enum OutputBlock: Identifiable, Hashable, Codable {
    case paragraph(text: String)
    case heading(text: String)
    case bulletList(items: [String])
    case table(head: [String], rows: [[String]])
    case codeBlock(language: String?, code: String)
    /// A model-issued tool call. `argumentsJSON` is the raw JSON string of
    /// the tool's input — kept opaque since the schema is per-tool.
    case toolCall(id: String, name: String, argumentsJSON: String)
    /// The result of a previously-issued tool call. `content` is plain text;
    /// can become structured later if needed.
    case toolResult(callID: String, content: String, isError: Bool)
    /// A block whose `kind` is not recognized by this build. Round-trips
    /// through encode/decode so opening a conversation written by a newer
    /// app version doesn't drop or corrupt the unknown blocks on save.
    case unknown(kind: String, raw: JSONValue)

    var id: String {
        switch self {
        case .paragraph(let t):    return "p:\(t.hashValue)"
        case .heading(let t):      return "h:\(t.hashValue)"
        case .bulletList(let it):  return "ul:\(it.hashValue)"
        case .table(let h, let r): return "tbl:\(h.hashValue):\(r.hashValue)"
        case .codeBlock(let lang, let code): return "cb:\(lang?.hashValue ?? 0):\(code.hashValue)"
        case .toolCall(let id, let name, _): return "tc:\(id):\(name)"
        case .toolResult(let callID, _, _): return "tr:\(callID)"
        case .unknown(let kind, let raw): return "unk:\(kind):\(raw.hashValue)"
        }
    }
}

private enum OutputBlockKind: String {
    case paragraph
    case heading
    case bulletList
    case table
    case codeBlock
    case toolCall
    case toolResult
}

private enum OutputBlockCodingKeys: String, CodingKey {
    case kind
    case text
    case items
    case head
    case rows
    case language
    case code
    // toolCall
    case toolCallID = "id"
    case name
    case argumentsJSON = "arguments"
    // toolResult
    case callID = "call_id"
    case content
    case isError = "is_error"
}

extension OutputBlock {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: OutputBlockCodingKeys.self)
        let kindString = try container.decode(String.self, forKey: .kind)

        guard let kind = OutputBlockKind(rawValue: kindString) else {
            // Forward-compat: capture every field of the unknown block so
            // encoding round-trips it untouched.
            let raw = try JSONValue(from: decoder)
            self = .unknown(kind: kindString, raw: raw)
            return
        }

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
        case .codeBlock:
            self = .codeBlock(
                language: try container.decodeIfPresent(String.self, forKey: .language),
                code: try container.decode(String.self, forKey: .code)
            )
        case .toolCall:
            self = .toolCall(
                id: try container.decode(String.self, forKey: .toolCallID),
                name: try container.decode(String.self, forKey: .name),
                argumentsJSON: try container.decode(String.self, forKey: .argumentsJSON)
            )
        case .toolResult:
            self = .toolResult(
                callID: try container.decode(String.self, forKey: .callID),
                content: try container.decode(String.self, forKey: .content),
                isError: try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .paragraph(let text):
            var c = encoder.container(keyedBy: OutputBlockCodingKeys.self)
            try c.encode(OutputBlockKind.paragraph.rawValue, forKey: .kind)
            try c.encode(text, forKey: .text)
        case .heading(let text):
            var c = encoder.container(keyedBy: OutputBlockCodingKeys.self)
            try c.encode(OutputBlockKind.heading.rawValue, forKey: .kind)
            try c.encode(text, forKey: .text)
        case .bulletList(let items):
            var c = encoder.container(keyedBy: OutputBlockCodingKeys.self)
            try c.encode(OutputBlockKind.bulletList.rawValue, forKey: .kind)
            try c.encode(items, forKey: .items)
        case .table(let head, let rows):
            var c = encoder.container(keyedBy: OutputBlockCodingKeys.self)
            try c.encode(OutputBlockKind.table.rawValue, forKey: .kind)
            try c.encode(head, forKey: .head)
            try c.encode(rows, forKey: .rows)
        case .codeBlock(let language, let code):
            var c = encoder.container(keyedBy: OutputBlockCodingKeys.self)
            try c.encode(OutputBlockKind.codeBlock.rawValue, forKey: .kind)
            try c.encodeIfPresent(language, forKey: .language)
            try c.encode(code, forKey: .code)
        case .toolCall(let id, let name, let argumentsJSON):
            var c = encoder.container(keyedBy: OutputBlockCodingKeys.self)
            try c.encode(OutputBlockKind.toolCall.rawValue, forKey: .kind)
            try c.encode(id, forKey: .toolCallID)
            try c.encode(name, forKey: .name)
            try c.encode(argumentsJSON, forKey: .argumentsJSON)
        case .toolResult(let callID, let content, let isError):
            var c = encoder.container(keyedBy: OutputBlockCodingKeys.self)
            try c.encode(OutputBlockKind.toolResult.rawValue, forKey: .kind)
            try c.encode(callID, forKey: .callID)
            try c.encode(content, forKey: .content)
            try c.encode(isError, forKey: .isError)
        case .unknown(_, let raw):
            // Write the captured fields verbatim. The raw object already
            // contains the original `kind` plus every other field.
            try raw.encode(to: encoder)
        }
    }
}

/// Minimal recursive JSON value used by `OutputBlock.unknown` to round-trip
/// blocks whose schema this build doesn't understand. Preserves integers
/// distinctly from doubles so the encoded form matches what was decoded.
enum JSONValue: Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: AnyCodingKey.self) {
            var dict: [String: JSONValue] = [:]
            for key in keyed.allKeys {
                let nested = try keyed.superDecoder(forKey: key)
                dict[key.stringValue] = try JSONValue(from: nested)
            }
            self = .object(dict)
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var arr: [JSONValue] = []
            while !unkeyed.isAtEnd {
                let nested = try unkeyed.superDecoder()
                arr.append(try JSONValue(from: nested))
            }
            self = .array(arr)
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let b = try? single.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? single.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? single.decode(Double.self) {
            self = .double(d)
        } else if let s = try? single.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported JSON value"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var c = encoder.singleValueContainer()
            try c.encodeNil()
        case .bool(let b):
            var c = encoder.singleValueContainer()
            try c.encode(b)
        case .int(let i):
            var c = encoder.singleValueContainer()
            try c.encode(i)
        case .double(let d):
            var c = encoder.singleValueContainer()
            try c.encode(d)
        case .string(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .array(let arr):
            var c = encoder.unkeyedContainer()
            for item in arr {
                try c.encode(item)
            }
        case .object(let dict):
            var c = encoder.container(keyedBy: AnyCodingKey.self)
            for (k, v) in dict {
                guard let key = AnyCodingKey(stringValue: k) else { continue }
                try c.encode(v, forKey: key)
            }
        }
    }
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}
