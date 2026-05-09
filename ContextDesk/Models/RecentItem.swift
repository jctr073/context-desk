import Foundation
import os

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
        try c.encode(containerFormat, forKey: .containerFormat)
        try c.encode(modelID, forKey: .modelID)
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, input, context, inputImages, contextImages
        case output, operation, operationID, operationLabel, mode, containerFormat, modelID
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
        let formatLabel = containerFormat == .markdown ? [] : [containerFormat.label]
        return [operationLabel] + formatLabel
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

private let historyLogger = Logger(subsystem: "com.contextdesk.app", category: "history")

enum HistoryStore {
    private static let userDefaultsKeys = ["ContextDesk.history.v1", "WritingBuddy.history.v1"]
    private static let appSupportDirectoryName = "com.contextdesk.app"
    private static let legacyAppSupportDirectoryName = "com.writingbuddy.app"
    static let maxItems = 15

    /// Overridable for tests. Defaults to `~/Library/Application Support/com.contextdesk.app/history.json`.
    static var fileURL: URL = defaultFileURL()
    /// Overridable for tests. Defaults to the pre-rename app-support file.
    static var legacyFileURL: URL? = defaultLegacyFileURL()
    /// Overridable for tests. Defaults to `.standard`.
    static var defaults: UserDefaults = .standard

    private static func defaultFileURL() -> URL {
        defaultFileURL(appSupportDirectoryName: appSupportDirectoryName)
    }

    private static func defaultLegacyFileURL() -> URL {
        defaultFileURL(appSupportDirectoryName: legacyAppSupportDirectoryName)
    }

    private static func defaultFileURL(appSupportDirectoryName: String) -> URL {
        let base: URL
        do {
            base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            historyLogger.error("Could not resolve Application Support; falling back to tmp: \(error.localizedDescription, privacy: .public)")
            base = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        return base
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("history.json")
    }

    static func load() -> [RecentItem] {
        let url = fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            // Defensive: if a stale legacy blob is still around, drop it.
            removeUserDefaultsBlobs()
            return decodeFile(at: url)
        }
        if let migrated = migrateFromLegacyFile() {
            return migrated
        }
        return migrateFromUserDefaults()
    }

    @discardableResult
    static func save(_ items: [RecentItem]) -> Task<Void, Never> {
        let trimmed = Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(maxItems))
        let url = fileURL
        return Task { await HistoryWriter.shared.write(trimmed, to: url) }
    }

    private static func decodeFile(at url: URL) -> [RecentItem] {
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([RecentItem].self, from: data)
            return Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(maxItems))
        } catch {
            historyLogger.error("Failed to read history file at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func migrateFromLegacyFile() -> [RecentItem]? {
        guard let legacyURL = legacyFileURL,
              legacyURL.path != fileURL.path,
              FileManager.default.fileExists(atPath: legacyURL.path) else {
            return nil
        }
        let items = decodeFile(at: legacyURL)
        do {
            try writeAtomically(items, to: fileURL)
            historyLogger.info("Migrated \(items.count, privacy: .public) legacy history items from \(legacyURL.path, privacy: .public)")
        } catch {
            historyLogger.error("Migration write to \(fileURL.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        return items
    }

    private static func migrateFromUserDefaults() -> [RecentItem] {
        guard let (key, data) = firstUserDefaultsBlob() else { return [] }
        let items: [RecentItem]
        do {
            items = try JSONDecoder().decode([RecentItem].self, from: data)
        } catch {
            historyLogger.error("Failed to decode legacy UserDefaults history; leaving key intact for postmortem: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let trimmed = Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(maxItems))
        do {
            try writeAtomically(trimmed, to: fileURL)
        } catch {
            historyLogger.error("Migration write to \(fileURL.path, privacy: .public) failed; leaving UserDefaults key intact: \(error.localizedDescription, privacy: .public)")
            return trimmed
        }
        defaults.removeObject(forKey: key)
        historyLogger.info("Migrated \(trimmed.count, privacy: .public) history items from UserDefaults to \(fileURL.path, privacy: .public)")
        return trimmed
    }

    private static func firstUserDefaultsBlob() -> (key: String, data: Data)? {
        for key in userDefaultsKeys {
            if let data = defaults.data(forKey: key) {
                return (key, data)
            }
        }
        return nil
    }

    private static func removeUserDefaultsBlobs() {
        for key in userDefaultsKeys where defaults.data(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
    }

    static func writeAtomically(_ items: [RecentItem], to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(items)
        try data.write(to: url, options: [.atomic])
    }
}

private actor HistoryWriter {
    static let shared = HistoryWriter()

    func write(_ items: [RecentItem], to url: URL) {
        do {
            try HistoryStore.writeAtomically(items, to: url)
        } catch {
            historyLogger.error("Failed to write history file at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
