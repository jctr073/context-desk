import Foundation

extension OutputBlock {
    func text(for containerFormat: OutputContainerFormat) -> String {
        switch containerFormat {
        case .markdown, .plain, .html:
            return markdown
        case .slack:
            return slack
        }
    }

    var markdown: String {
        switch self {
        case .paragraph(let text, _):
            return text
        case .heading(let text):
            return "## \(text)"
        case .bulletList(let items):
            return items.map { "- \($0)" }.joined(separator: "\n")
        case .table(let head, let rows):
            let widths = columnWidths(head: head, rows: rows)
            let headerLine = renderRow(head, widths: widths)
            let separatorLine = "| " + widths.map { String(repeating: "-", count: max(3, $0)) }.joined(separator: " | ") + " |"
            let bodyLines = rows.map { renderRow($0, widths: widths) }
            return ([headerLine, separatorLine] + bodyLines).joined(separator: "\n")
        case .codeBlock(let language, let code):
            let fence = "```" + (language ?? "")
            return "\(fence)\n\(code)\n```"
        case .toolCall(_, let name, let argumentsJSON):
            return "> **Tool call:** `\(name)`\n> ```\n> \(argumentsJSON)\n> ```"
        case .toolResult(_, let content, let isError):
            let label = isError ? "Tool error" : "Tool result"
            return "> **\(label):** \(content)"
        case .unknown(let kind, _):
            return "<!-- unsupported block: \(kind) -->"
        }
    }

    private var slack: String {
        switch self {
        case .paragraph(let text, _):
            return text
        case .heading(let text):
            return "*\(text)*"
        case .bulletList(let items):
            return items.map { "- \($0)" }.joined(separator: "\n")
        case .table(let head, let rows):
            let widths = columnWidths(head: head, rows: rows)
            let headerLine = renderPlainRow(head, widths: widths)
            let separatorLine = widths
                .map { String(repeating: "-", count: max(3, $0)) }
                .joined(separator: "  ")
            let bodyLines = rows.map { renderPlainRow($0, widths: widths) }
            let tableText = ([headerLine, separatorLine] + bodyLines).joined(separator: "\n")
            return "```\n\(tableText)\n```"
        case .codeBlock(_, let code):
            return "```\n\(code)\n```"
        case .toolCall(_, let name, _):
            return "_(tool call: \(name))_"
        case .toolResult(_, let content, let isError):
            return isError ? "_(tool error: \(content))_" : "_(tool result: \(content))_"
        case .unknown(let kind, _):
            return "[unsupported: \(kind)]"
        }
    }

    private func columnWidths(head: [String], rows: [[String]]) -> [Int] {
        var widths = head.map { $0.count }
        for row in rows {
            for (i, cell) in row.enumerated() where i < widths.count {
                widths[i] = max(widths[i], cell.count)
            }
        }
        return widths
    }

    private func renderRow(_ cells: [String], widths: [Int]) -> String {
        let padded = cells.enumerated().map { idx, cell -> String in
            let width = idx < widths.count ? widths[idx] : cell.count
            return cell.padding(toLength: width, withPad: " ", startingAt: 0)
        }
        return "| " + padded.joined(separator: " | ") + " |"
    }

    private func renderPlainRow(_ cells: [String], widths: [Int]) -> String {
        let padded = cells.enumerated().map { idx, cell -> String in
            let width = idx < widths.count ? widths[idx] : cell.count
            return cell.padding(toLength: width, withPad: " ", startingAt: 0)
        }
        return padded.joined(separator: "  ")
    }
}

extension Array where Element == OutputBlock {
    var markdown: String {
        map(\.markdown).joined(separator: "\n\n")
    }

    func text(for containerFormat: OutputContainerFormat) -> String {
        map { $0.text(for: containerFormat) }.joined(separator: "\n\n")
    }
}
