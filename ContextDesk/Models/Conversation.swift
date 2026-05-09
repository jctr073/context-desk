import Foundation
import os

enum MessageRole: String, Codable, Hashable {
    case user
    case assistant
}

/// A single turn in a conversation. Assistant messages carry rendered
/// `OutputBlock`s; user messages carry raw text plus optional attachments.
struct ChatMessage: Identifiable, Hashable, Codable {
    let id: String
    let role: MessageRole
    let createdAt: Date
    /// Raw text. For user messages this is what they typed. For assistant
    /// messages it's the plain-text fallback (used for word-count, copy, and
    /// when blocks failed to parse).
    var text: String
    /// Structured assistant output. Empty for user messages.
    var blocks: [OutputBlock]
    var attachments: [AttachedImage]
    /// Currently-selected format chip on assistant messages (display only).
    var format: String?
    /// Provider-specific response id, used by OpenAI Responses' previous_response_id.
    var providerResponseID: String?

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        createdAt: Date = Date(),
        text: String,
        blocks: [OutputBlock] = [],
        attachments: [AttachedImage] = [],
        format: String? = nil,
        providerResponseID: String? = nil
    ) {
        self.id = id
        self.role = role
        self.createdAt = createdAt
        self.text = text
        self.blocks = blocks
        self.attachments = attachments
        self.format = format
        self.providerResponseID = providerResponseID
    }
}

/// A multi-turn conversation. Each `Conversation` corresponds to one row in
/// the history rail and one chat thread.
struct Conversation: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var mode: WritingMode
    var customInstructions: String
    var contextText: String
    var contextImages: [AttachedImage]
    var webAccessEnabled: Bool
    var modelID: String
    var operationID: String
    var formats: Set<OutputFormat>
    var containerFormat: OutputContainerFormat
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String = "New conversation",
        mode: WritingMode = .chat,
        customInstructions: String = "",
        contextText: String = "",
        contextImages: [AttachedImage] = [],
        webAccessEnabled: Bool = false,
        modelID: String,
        operationID: String,
        formats: Set<OutputFormat> = [],
        containerFormat: OutputContainerFormat = .markdown,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.customInstructions = customInstructions
        self.contextText = contextText
        self.contextImages = contextImages
        self.webAccessEnabled = webAccessEnabled
        self.modelID = modelID
        self.operationID = operationID
        self.formats = formats
        self.containerFormat = containerFormat
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.mode = try c.decode(WritingMode.self, forKey: .mode)
        self.customInstructions = try c.decode(String.self, forKey: .customInstructions)
        self.contextText = (try? c.decode(String.self, forKey: .contextText)) ?? ""
        self.contextImages = (try? c.decode([AttachedImage].self, forKey: .contextImages)) ?? []
        self.webAccessEnabled = (try? c.decode(Bool.self, forKey: .webAccessEnabled)) ?? false
        self.modelID = try c.decode(String.self, forKey: .modelID)
        self.operationID = try c.decode(String.self, forKey: .operationID)
        self.formats = try c.decode(Set<OutputFormat>.self, forKey: .formats)
        self.containerFormat = try c.decode(OutputContainerFormat.self, forKey: .containerFormat)
        self.messages = try c.decode([ChatMessage].self, forKey: .messages)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, mode, customInstructions, contextText, contextImages, webAccessEnabled
        case modelID, operationID, formats, containerFormat, messages
        case createdAt, updatedAt
    }

    /// Indices of assistant messages in the order they appear — used to power
    /// the Reply 1/2/… tabs in the output canvas.
    var assistantIndices: [Int] {
        messages.enumerated().compactMap { $0.element.role == .assistant ? $0.offset : nil }
    }

    /// Latest assistant message, if any.
    var latestAssistantIndex: Int? {
        assistantIndices.last
    }

    var preview: String {
        let firstUser = messages.first(where: { $0.role == .user })
        let text = (firstUser?.text ?? "").compacted()
        if !text.isEmpty { return text.clipped(maxLength: 56) }
        if let firstUser, !firstUser.attachments.isEmpty {
            return firstUser.attachments.count == 1
                ? "1 image"
                : "\(firstUser.attachments.count) images"
        }
        return "No messages"
    }

    var when: String {
        let seconds = max(0, Int(Date().timeIntervalSince(updatedAt)))
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let calendar = Calendar.current
        if calendar.isDateInYesterday(updatedAt) { return "Yesterday" }
        return Self.dateFormatter.string(from: updatedAt)
    }

    /// Resolve the persisted operation back into an `Operation`, falling back
    /// to the mode's default if the id no longer exists.
    var operation: Operation {
        OperationCatalog.operation(for: mode, id: operationID)
            ?? OperationCatalog.defaultOp(for: mode)
    }

    /// Auto-derive a title from the first user message.
    static func deriveTitle(from text: String) -> String {
        let cleaned = text.compacted()
        guard !cleaned.isEmpty else { return "New conversation" }
        if let sentenceEnd = cleaned.firstIndex(where: { ".?!".contains($0) }) {
            let sentence = String(cleaned[...sentenceEnd])
            return sentence.clipped(maxLength: 42)
        }
        return cleaned.clipped(maxLength: 42)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()
}

private let conversationLogger = Logger(subsystem: "com.contextdesk.app", category: "conversation")

/// Disk-backed store for `Conversation`s. Mirrors `HistoryStore`.
/// Migrates legacy `RecentItem` history into single-turn conversations on
/// first load.
enum ConversationStore {
    private static let appSupportDirectoryName = "com.contextdesk.app"
    private static let legacyAppSupportDirectoryName = "com.writingbuddy.app"
    static let maxItems = 50

    /// Overridable for tests. Defaults to
    /// `~/Library/Application Support/com.contextdesk.app/conversations.json`.
    static var fileURL: URL = defaultFileURL()
    /// Overridable for tests. Defaults to the pre-rename app-support file.
    static var legacyFileURL: URL? = defaultLegacyFileURL()

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
            conversationLogger.error("Could not resolve Application Support; falling back to tmp: \(error.localizedDescription, privacy: .public)")
            base = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        return base
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("conversations.json")
    }

    static func load() -> [Conversation] {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return decode(at: fileURL)
        }
        if let migrated = migrateFromLegacyFile() {
            return migrated
        }
        return migrateFromHistory()
    }

    @discardableResult
    static func save(_ items: [Conversation]) -> Task<Void, Never> {
        let trimmed = Array(items.sorted { $0.updatedAt > $1.updatedAt }.prefix(maxItems))
        let url = fileURL
        return Task { await ConversationWriter.shared.write(trimmed, to: url) }
    }

    private static func decode(at url: URL) -> [Conversation] {
        do {
            let data = try Data(contentsOf: url)
            let items = try JSONDecoder().decode([Conversation].self, from: data)
            return Array(items.sorted { $0.updatedAt > $1.updatedAt }.prefix(maxItems))
        } catch {
            conversationLogger.error("Failed to read conversations file at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func migrateFromLegacyFile() -> [Conversation]? {
        guard let legacyURL = legacyFileURL,
              legacyURL.path != fileURL.path,
              FileManager.default.fileExists(atPath: legacyURL.path) else {
            return nil
        }
        let conversations = decode(at: legacyURL)
        do {
            try writeAtomically(conversations, to: fileURL)
            conversationLogger.info("Migrated \(conversations.count, privacy: .public) legacy conversations from \(legacyURL.path, privacy: .public)")
        } catch {
            conversationLogger.error("Migration write to \(fileURL.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        return conversations
    }

    /// One-time migration: turn each legacy `RecentItem` into a single-turn
    /// `Conversation` and persist. Leaves the legacy history.json in place
    /// (the chat UI reads only conversations.json from now on, but old data
    /// remains recoverable until the user clears it).
    private static func migrateFromHistory() -> [Conversation] {
        let legacy = HistoryStore.load()
        guard !legacy.isEmpty else { return [] }
        let conversations: [Conversation] = legacy.map { item in
            let userMsg = ChatMessage(
                id: item.id + ":user",
                role: .user,
                createdAt: item.createdAt,
                text: item.input,
                attachments: item.inputImages
            )
            let assistantMsg = ChatMessage(
                id: item.id + ":assistant",
                role: .assistant,
                createdAt: item.createdAt,
                text: MockGenerator.plainText(from: item.output),
                blocks: item.output
            )
            return Conversation(
                id: item.id,
                title: Conversation.deriveTitle(from: item.input),
                mode: item.mode,
                customInstructions: "",
                modelID: item.modelID,
                operationID: item.operationID,
                formats: item.formats,
                containerFormat: item.containerFormat,
                messages: [userMsg, assistantMsg],
                createdAt: item.createdAt,
                updatedAt: item.createdAt
            )
        }
        do {
            try writeAtomically(conversations, to: fileURL)
            conversationLogger.info("Migrated \(conversations.count, privacy: .public) legacy history items into conversations")
        } catch {
            conversationLogger.error("Migration write to \(fileURL.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        return conversations
    }

    static func writeAtomically(_ items: [Conversation], to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(items)
        try data.write(to: url, options: [.atomic])
    }
}

private actor ConversationWriter {
    static let shared = ConversationWriter()

    func write(_ items: [Conversation], to url: URL) {
        do {
            try ConversationStore.writeAtomically(items, to: url)
        } catch {
            conversationLogger.error("Failed to write conversations at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension String {
    func compacted() -> String {
        split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clipped(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let endIndex = index(startIndex, offsetBy: maxLength)
        return String(self[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
