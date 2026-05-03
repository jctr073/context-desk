import Foundation

struct RecentItem: Identifiable, Hashable, Codable {
    let id: String
    let createdAt: Date
    let input: String
    let output: [OutputBlock]
    let operation: WritingOp
    let formats: Set<OutputFormat>
    let modelID: String

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        input: String,
        output: [OutputBlock],
        operation: WritingOp,
        formats: Set<OutputFormat>,
        modelID: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.input = input
        self.output = output
        self.operation = operation
        self.formats = formats.isEmpty ? [.paragraphs] : formats
        self.modelID = modelID
    }

    var title: String {
        let text = compacted(input)
        guard !text.isEmpty else { return "Untitled note" }

        if let sentenceEnd = text.firstIndex(where: { ".?!".contains($0) }) {
            let sentence = String(text[...sentenceEnd])
            return clipped(sentence, maxLength: 42)
        }

        return clipped(text, maxLength: 42)
    }

    var preview: String {
        let text = compacted(input)
        return text.isEmpty ? "No input text" : clipped(text, maxLength: 56)
    }

    var when: String {
        let seconds = max(0, Int(Date().timeIntervalSince(createdAt)))

        if seconds < 60 {
            return "Just now"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }

        let calendar = Calendar.current
        if calendar.isDateInYesterday(createdAt) {
            return "Yesterday"
        }

        return Self.dateFormatter.string(from: createdAt)
    }

    var actions: [String] {
        let selectedFormats = OutputFormat.allCases
            .filter { formats.contains($0) }
            .map(\.label)
        return [operation.label] + selectedFormats
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

enum HistoryStore {
    private static let key = "WritingBuddy.history.v1"
    static let maxItems = 50

    static func load() -> [RecentItem] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }

        do {
            return try JSONDecoder()
                .decode([RecentItem].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }

    static func save(_ items: [RecentItem]) {
        let limitedItems = Array(items.prefix(maxItems))

        do {
            let data = try JSONEncoder().encode(limitedItems)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            return
        }
    }
}

private func compacted(_ text: String) -> String {
    text
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func clipped(_ text: String, maxLength: Int) -> String {
    guard text.count > maxLength else { return text }
    let endIndex = text.index(text.startIndex, offsetBy: maxLength)
    return String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
}
