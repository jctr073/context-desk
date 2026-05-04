import Foundation

extension OutputBlock {
    var markdown: String {
        switch self {
        case .paragraph(let text):
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
}

extension Array where Element == OutputBlock {
    var markdown: String {
        map(\.markdown).joined(separator: "\n\n")
    }
}
