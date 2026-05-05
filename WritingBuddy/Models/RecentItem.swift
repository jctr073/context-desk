import Foundation

struct RecentItem: Identifiable, Hashable, Codable {
    let id: String
    let createdAt: Date
    let input: String
    let context: String
    let inputImages: [AttachedImage]
    let contextImages: [AttachedImage]
    let output: [OutputBlock]
    let operationID: String
    let operationLabel: String
    let mode: WritingMode
    let formats: Set<OutputFormat>
    let containerFormat: OutputContainerFormat
    let modelID: String

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        input: String,
        context: String = "",
        inputImages: [AttachedImage] = [],
        contextImages: [AttachedImage] = [],
        output: [OutputBlock],
        operationID: String,
        operationLabel: String,
        mode: WritingMode = .writing,
        formats: Set<OutputFormat>,
        containerFormat: OutputContainerFormat = .markdown,
        modelID: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.input = input
        self.context = context
        self.inputImages = inputImages
        self.contextImages = contextImages
        self.output = output
        self.operationID = operationID
        self.operationLabel = operationLabel
        self.mode = mode
        self.formats = formats
        self.containerFormat = containerFormat
        self.modelID = modelID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.input = try c.decode(String.self, forKey: .input)
        self.context = (try? c.decode(String.self, forKey: .context)) ?? ""
        self.inputImages = (try? c.decode([AttachedImage].self, forKey: .inputImages)) ?? []
        self.contextImages = (try? c.decode([AttachedImage].self, forKey: .contextImages)) ?? []
        self.output = try c.decode([OutputBlock].self, forKey: .output)
        // New schema: operationID + operationLabel + mode.
        // Legacy schema: operation: WritingOp.
        if let opID = try? c.decode(String.self, forKey: .operationID) {
            self.operationID = opID
            self.operationLabel = (try? c.decode(String.self, forKey: .operationLabel))
                ?? (WritingOp(rawValue: opID)?.label
                    ?? ChatOp(rawValue: opID)?.label
                    ?? opID.capitalized)
            self.mode = (try? c.decode(WritingMode.self, forKey: .mode)) ?? .writing
        } else {
            let legacyOp = try c.decode(WritingOp.self, forKey: .operation)
            self.operationID = legacyOp.id
            self.operationLabel = legacyOp.label
            self.mode = .writing
        }
        self.formats = try c.decode(Set<OutputFormat>.self, forKey: .formats)
        self.containerFormat = (try? c.decode(OutputContainerFormat.self, forKey: .containerFormat)) ?? .markdown
        self.modelID = try c.decode(String.self, forKey: .modelID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(input, forKey: .input)
        try c.encode(context, forKey: .context)
        try c.encode(inputImages, forKey: .inputImages)
        try c.encode(contextImages, forKey: .contextImages)
        try c.encode(output, forKey: .output)
        try c.encode(operationID, forKey: .operationID)
        try c.encode(operationLabel, forKey: .operationLabel)
        try c.encode(mode, forKey: .mode)
        try c.encode(formats, forKey: .formats)
        try c.encode(containerFormat, forKey: .containerFormat)
        try c.encode(modelID, forKey: .modelID)
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, input, context, inputImages, contextImages
        case output, operation, operationID, operationLabel, mode, formats, containerFormat, modelID
    }

    var title: String {
        let text = compacted(input)
        guard !text.isEmpty else {
            guard !inputImages.isEmpty else { return "Untitled note" }
            return inputImages.count == 1 ? "Image input" : "\(inputImages.count) image inputs"
        }

        if let sentenceEnd = text.firstIndex(where: { ".?!".contains($0) }) {
            let sentence = String(text[...sentenceEnd])
            return clipped(sentence, maxLength: 42)
        }

        return clipped(text, maxLength: 42)
    }

    var preview: String {
        let text = compacted(input)
        if !text.isEmpty {
            return clipped(text, maxLength: 56)
        }

        var parts: [String] = []
        if !inputImages.isEmpty {
            parts.append(inputImages.count == 1 ? "1 input image" : "\(inputImages.count) input images")
        }
        if !contextImages.isEmpty {
            parts.append(contextImages.count == 1 ? "1 context image" : "\(contextImages.count) context images")
        }
        let contextText = compacted(context)
        if !contextText.isEmpty {
            parts.append("Context: \(clipped(contextText, maxLength: 36))")
        }
        return parts.isEmpty ? "No input text" : parts.joined(separator: " + ")
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
        let formatLabel = containerFormat == .markdown ? [] : [containerFormat.label]
        return [operationLabel] + formatLabel + selectedFormats
    }

    /// Resolve the stored operation back into an `Operation` if possible.
    var operation: Operation? {
        OperationCatalog.operation(for: mode, id: operationID)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

enum HistoryStore {
    private static let key = "WritingBuddy.history.v1"
    static let maxItems = 15

    static func load() -> [RecentItem] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return []
        }

        do {
            let items = try JSONDecoder()
                .decode([RecentItem].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
            return Array(items.prefix(maxItems))
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
