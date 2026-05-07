import Foundation

final class StreamingOutputParser {
    private var buffer: [UInt8] = []
    private var cursor: Int = 0

    private var depth: Int = 0
    private var inString: Bool = false
    private var escape: Bool = false

    private var enteredArray: Bool = false
    private var currentObjectStart: Int? = nil

    private var completed: [OutputBlock] = []

    private static let kindRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\"kind\"\\s*:\\s*\"([A-Za-z0-9_]+)\"", options: [])
    }()

    private static let textKeyRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\"text\"\\s*:\\s*\"", options: [])
    }()

    private static let itemsKeyRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\"items\"\\s*:\\s*\\[", options: [])
    }()

    func feed(_ chunk: String) {
        let bytes = Array(chunk.utf8)
        buffer.append(contentsOf: bytes)
        advance()
    }

    var snapshot: [OutputBlock] {
        if let preview = buildPreview() {
            return completed + [preview]
        }
        return completed
    }

    func finish() throws -> [OutputBlock] {
        let data = Data(buffer)
        return try JSONDecoder().decode(StructuredOutput.self, from: data).blocks
    }

    var bufferDebugString: String {
        String(decoding: buffer, as: UTF8.self)
    }

    private func advance() {
        while cursor < buffer.count {
            let byte = buffer[cursor]

            if inString {
                if escape {
                    escape = false
                } else if byte == 0x5C {
                    escape = true
                } else if byte == 0x22 {
                    inString = false
                }
                cursor += 1
                continue
            }

            switch byte {
            case 0x22:
                inString = true
            case 0x7B:
                if enteredArray && depth == 2 && currentObjectStart == nil {
                    currentObjectStart = cursor
                }
                depth += 1
            case 0x7D:
                depth -= 1
                if enteredArray && depth == 2, let start = currentObjectStart {
                    let slice = Array(buffer[start...cursor])
                    if let block = try? JSONDecoder().decode(OutputBlock.self, from: Data(slice)) {
                        completed.append(block)
                    }
                    currentObjectStart = nil
                }
            case 0x5B:
                if !enteredArray && depth == 1 {
                    enteredArray = true
                }
                depth += 1
            case 0x5D:
                depth -= 1
            default:
                break
            }
            cursor += 1
        }
    }

    private func buildPreview() -> OutputBlock? {
        guard enteredArray, let start = currentObjectStart, start < buffer.count else {
            return nil
        }
        let slice = Array(buffer[start..<buffer.count])
        guard let partial = String(bytes: slice, encoding: .utf8) else {
            return nil
        }
        let nsPartial = partial as NSString
        let fullRange = NSRange(location: 0, length: nsPartial.length)

        guard let kindMatch = Self.kindRegex.firstMatch(in: partial, options: [], range: fullRange),
              kindMatch.numberOfRanges >= 2 else {
            return nil
        }
        let kind = nsPartial.substring(with: kindMatch.range(at: 1))

        switch kind {
        case "paragraph", "heading":
            guard let text = extractPartialString(in: partial, ns: nsPartial, fullRange: fullRange) else {
                return nil
            }
            return kind == "paragraph" ? .paragraph(text: text) : .heading(text: text)
        case "bulletList":
            guard let items = extractPartialItems(in: partial, ns: nsPartial, fullRange: fullRange) else {
                return nil
            }
            return .bulletList(items: items)
        default:
            return nil
        }
    }

    private func extractPartialString(in partial: String, ns: NSString, fullRange: NSRange) -> String? {
        guard let textMatch = Self.textKeyRegex.firstMatch(in: partial, options: [], range: fullRange) else {
            return nil
        }
        let after = textMatch.range.location + textMatch.range.length
        let remaining = ns.substring(from: after)
        return readPartialJSONString(remaining)
    }

    private func extractPartialItems(in partial: String, ns: NSString, fullRange: NSRange) -> [String]? {
        guard let itemsMatch = Self.itemsKeyRegex.firstMatch(in: partial, options: [], range: fullRange) else {
            return nil
        }
        let after = itemsMatch.range.location + itemsMatch.range.length
        let remaining = ns.substring(from: after)
        return readPartialStringArray(remaining)
    }

    private func readPartialStringArray(_ s: String) -> [String] {
        var items: [String] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            let ch = s[idx]
            if ch == "]" {
                return items
            }
            if ch == "\"" {
                let after = s.index(after: idx)
                let rest = String(s[after...])
                let (decoded, consumed, closed) = readOneString(rest)
                if closed {
                    items.append(decoded)
                    idx = s.index(after, offsetBy: consumed + 1)
                    continue
                } else {
                    items.append(decoded)
                    return items
                }
            }
            idx = s.index(after: idx)
        }
        return items
    }

    private func readPartialJSONString(_ s: String) -> String {
        let (decoded, _, _) = readOneString(s)
        return decoded
    }

    private func readOneString(_ s: String) -> (decoded: String, consumed: Int, closed: Bool) {
        var out = String()
        var i = s.startIndex
        var consumed = 0
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\\" {
                let next = s.index(after: i)
                if next >= s.endIndex {
                    return (out, consumed, false)
                }
                let escChar = s[next]
                switch escChar {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/": out.append("/")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "u":
                    let hexStart = s.index(after: next)
                    let hexEnd = s.index(hexStart, offsetBy: 4, limitedBy: s.endIndex) ?? s.endIndex
                    let hexStr = String(s[hexStart..<hexEnd])
                    if hexStr.count < 4 {
                        return (out, consumed, false)
                    }
                    if let code = UInt32(hexStr, radix: 16), let scalar = Unicode.Scalar(code) {
                        out.append(Character(scalar))
                    }
                    i = hexEnd
                    consumed = s.distance(from: s.startIndex, to: i)
                    continue
                default:
                    out.append(escChar)
                }
                i = s.index(after: next)
                consumed = s.distance(from: s.startIndex, to: i)
                continue
            }
            if ch == "\"" {
                return (out, consumed, true)
            }
            out.append(ch)
            i = s.index(after: i)
            consumed = s.distance(from: s.startIndex, to: i)
        }
        return (out, consumed, false)
    }
}
