import SwiftUI

@MainActor
final class AppState: ObservableObject {
    // MARK: Conversations
    @Published var conversations: [Conversation] = []
    @Published var activeConversationID: String? = nil

    // MARK: Composer / draft
    @Published var draft: String = ""
    @Published var draftImages: [AttachedImage] = []
    @Published var lastAddedImageID: String? = nil
    @Published var pasteFlash: Bool = false
    @Published var lightboxImage: AttachedImage? = nil

    // MARK: Output canvas
    /// Index of the assistant message currently shown in the right output canvas.
    @Published var pinnedReplyIdx: Int? = nil
    /// When true, the canvas auto-advances to the freshest assistant reply on send.
    @Published var autoFollowLatest: Bool = true
    @Published var renderMode: RenderMode = .rendered
    @Published var copiedFlash: Bool = false

    // MARK: Mode + operation (per-conversation, mirrored here for the toolbar)
    @Published var mode: WritingMode = .chat {
        didSet { syncActiveConversationMeta() }
    }
    @Published var ops: Set<WritingOp> = [.cleanup] {
        didSet { syncActiveConversationMeta() }
    }
    @Published var chatOp: ChatOp = .ask {
        didSet { syncActiveConversationMeta() }
    }
    @Published var fmts: Set<OutputFormat> = [] {
        didSet { syncActiveConversationMeta() }
    }
    @Published var containerFormat: OutputContainerFormat = .markdown {
        didSet { syncActiveConversationMeta() }
    }
    @Published var customInstructions: String = "" {
        didSet { syncActiveConversationMeta() }
    }
    @Published var editingInstructions: Bool = false

    // MARK: Conversation-wide context (reference material attached to every send)
    @Published var contextText: String = "" {
        didSet { syncActiveConversationMeta() }
    }
    @Published var contextImages: [AttachedImage] = [] {
        didSet { syncActiveConversationMeta() }
    }
    @Published var webAccessEnabled: Bool = false {
        didSet { syncActiveConversationMeta() }
    }
    @Published var lastAddedContextImageID: String? = nil
    @Published var editingContext: Bool = false

    // MARK: Output canvas diff toggle (writing mode only)
    @Published var diffMode: Bool = false

    // MARK: Run state
    @Published var running: Bool = false
    /// While streaming, the assistant message at this index is being filled in.
    @Published var streamingMessageIndex: Int? = nil

    // MARK: Global app chrome
    @Published var model: AIModel = .gpt55Medium
    @Published var theme: AppTheme = .dark
    @Published var historyVisible: Bool = true
    @Published var canvasVisible: Bool = true
    @Published var canvasSplit: Double = 0.66
    @Published var configuredProviders: Set<AIProvider> = []
    @Published var addingKeyFor: AIProvider? = nil

    private var runTask: Task<Void, Never>?
    private var pasteFlashTask: Task<Void, Never>?
    private var suppressMetaSync = false

    init() {
        self.configuredProviders = Self.configuredProviderSet()
        self.conversations = ConversationStore.load()
        if let first = self.conversations.first {
            adoptConversation(first.id)
        }
    }

    // MARK: - Active conversation accessors

    var activeConversation: Conversation? {
        guard let id = activeConversationID else { return nil }
        return conversations.first(where: { $0.id == id })
    }

    var activeMessages: [ChatMessage] {
        activeConversation?.messages ?? []
    }

    var assistantIndices: [Int] {
        activeConversation?.assistantIndices ?? []
    }

    var pinnedMessage: ChatMessage? {
        guard let idx = pinnedReplyIdx,
              let msgs = activeConversation?.messages,
              msgs.indices.contains(idx) else { return nil }
        return msgs[idx]
    }

    /// User message immediately preceding the pinned assistant reply — the
    /// "original" text for the writing-mode diff view.
    var pinnedReplyOriginalUserText: String {
        guard let idx = pinnedReplyIdx,
              let msgs = activeConversation?.messages,
              msgs.indices.contains(idx) else { return "" }
        let prefix = msgs.prefix(idx)
        return prefix.last(where: { $0.role == .user })?.text ?? ""
    }

    var composerPromptHistory: [String] {
        guard let messages = activeConversation?.messages else { return [] }
        return messages.reversed().compactMap { message in
            guard message.role == .user else { return nil }
            guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return message.text
        }
    }

    // MARK: - API key helpers

    func hasKey(for provider: AIProvider) -> Bool {
        configuredProviders.contains(provider) || APIKeyStore.exists(for: provider)
    }

    func startAddingKey(_ provider: AIProvider) {
        addingKeyFor = provider
    }

    func cancelAddingKey() {
        addingKeyFor = nil
    }

    private static func configuredProviderSet() -> Set<AIProvider> {
        Set(AIProvider.allCases.filter { APIKeyStore.exists(for: $0) })
    }

    // MARK: - Composer state

    var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !draftImages.isEmpty && AIWritingService.supports(model.provider)
        return (hasText || hasImages) && !running
    }

    func attachImages(_ images: [AttachedImage]) {
        guard !images.isEmpty else { return }
        draftImages.append(contentsOf: images)
        lastAddedImageID = images.last?.id
        triggerPasteFlash()
    }

    func attachImage(_ image: AttachedImage) {
        attachImages([image])
    }

    func removeImage(_ image: AttachedImage) {
        draftImages.removeAll { $0.id == image.id }
        if lastAddedImageID == image.id { lastAddedImageID = nil }
    }

    func showLightbox(_ image: AttachedImage) { lightboxImage = image }
    func dismissLightbox() { lightboxImage = nil }

    // MARK: - Context helpers

    var hasContext: Bool {
        !contextText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !contextImages.isEmpty
    }

    func attachContextImages(_ images: [AttachedImage]) {
        guard !images.isEmpty else { return }
        contextImages.append(contentsOf: images)
        lastAddedContextImageID = images.last?.id
    }

    func removeContextImage(_ image: AttachedImage) {
        contextImages.removeAll { $0.id == image.id }
        if lastAddedContextImageID == image.id { lastAddedContextImageID = nil }
    }

    func startEditingContext() { editingContext = true }
    func cancelEditingContext() { editingContext = false }
    func saveContext(text: String, images: [AttachedImage]) {
        contextText = text
        contextImages = images
        editingContext = false
    }

    private func triggerPasteFlash() {
        pasteFlash = true
        pasteFlashTask?.cancel()
        pasteFlashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            await MainActor.run { self?.pasteFlash = false }
        }
    }

    // MARK: - Operation routing

    func toggleOp(_ op: WritingOp) { ops = [op] }
    func setChatOp(_ op: ChatOp) { chatOp = op }

    func setMode(_ newMode: WritingMode) {
        guard mode != newMode else { return }
        mode = newMode
    }

    var activeOperation: Operation {
        switch mode {
        case .writing:
            return WritingOp.allCases.first { ops.contains($0) } ?? .cleanup
        case .chat:
            return chatOp
        }
    }

    var isAutomaticFormat: Bool { fmts.isEmpty }
    func setAutomaticFormat() { fmts.removeAll() }
    func toggleFormat(_ fmt: OutputFormat) {
        if fmts.contains(fmt) { fmts.remove(fmt) } else { fmts.insert(fmt) }
    }

    // MARK: - Conversation lifecycle

    func toggleHistoryVisible() { historyVisible.toggle() }
    func toggleCanvasVisible() { canvasVisible.toggle() }

    func newConversation() {
        runTask?.cancel()
        running = false
        let convo = Conversation(
            modelID: model.id,
            operationID: activeOperation.id,
            formats: fmts,
            containerFormat: containerFormat
        )
        conversations.insert(convo, at: 0)
        ConversationStore.save(conversations)
        adoptConversation(convo.id)
    }

    func selectConversation(_ id: String) {
        guard id != activeConversationID else { return }
        runTask?.cancel()
        running = false
        adoptConversation(id)
    }

    /// Reset all UI state to the conversation with the given id, syncing
    /// mode/op/format/instructions back to the published toolbar fields.
    private func adoptConversation(_ id: String) {
        guard let convo = conversations.first(where: { $0.id == id }) else { return }
        suppressMetaSync = true
        activeConversationID = id
        mode = convo.mode
        switch convo.mode {
        case .writing:
            ops = [WritingOp(rawValue: convo.operationID) ?? .cleanup]
        case .chat:
            chatOp = ChatOp(rawValue: convo.operationID) ?? .ask
        }
        fmts = convo.formats
        containerFormat = convo.containerFormat
        customInstructions = convo.customInstructions
        contextText = convo.contextText
        contextImages = convo.contextImages
        webAccessEnabled = convo.webAccessEnabled
        lastAddedContextImageID = nil
        if let m = AIModel.model(withID: convo.modelID) { model = m }
        draft = ""
        draftImages = []
        lastAddedImageID = nil
        pinnedReplyIdx = convo.latestAssistantIndex
        autoFollowLatest = true
        diffMode = false
        suppressMetaSync = false
    }

    func deleteConversation(_ id: String) {
        conversations.removeAll { $0.id == id }
        ConversationStore.save(conversations)
        if activeConversationID == id {
            if let next = conversations.first {
                adoptConversation(next.id)
            } else {
                activeConversationID = nil
                pinnedReplyIdx = nil
                draft = ""
                draftImages = []
                contextText = ""
                contextImages = []
                webAccessEnabled = false
            }
        }
    }

    func clearAllConversations() {
        conversations = []
        activeConversationID = nil
        pinnedReplyIdx = nil
        draft = ""
        draftImages = []
        contextText = ""
        contextImages = []
        webAccessEnabled = false
        ConversationStore.save([])
    }

    func startEditingInstructions() { editingInstructions = true }
    func cancelEditingInstructions() { editingInstructions = false }
    func saveCustomInstructions(_ text: String) {
        customInstructions = text
        editingInstructions = false
    }

    var hasCustomInstructions: Bool {
        !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Mirror toolbar/composer state back into the active conversation, so
    /// edits are picked up by the next save.
    private func syncActiveConversationMeta() {
        guard !suppressMetaSync, let id = activeConversationID,
              let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        var convo = conversations[idx]
        convo.mode = mode
        convo.operationID = activeOperation.id
        convo.formats = fmts
        convo.containerFormat = containerFormat
        convo.customInstructions = customInstructions
        convo.contextText = contextText
        convo.contextImages = contextImages
        convo.webAccessEnabled = webAccessEnabled
        convo.modelID = model.id
        conversations[idx] = convo
    }

    func selectPinnedReply(_ idx: Int) {
        guard let assistantIdxs = activeConversation?.assistantIndices,
              !assistantIdxs.isEmpty else { return }
        pinnedReplyIdx = idx
        autoFollowLatest = (idx == assistantIdxs.last)
    }

    // MARK: - Sending

    func send() {
        guard canSend else { return }
        let trimmedDraft = draft
        let images = draftImages

        if conversations.isEmpty || activeConversationID == nil {
            newConversation()
        }
        guard let convoIdx = conversations.firstIndex(where: { $0.id == activeConversationID }) else { return }

        let userMessage = ChatMessage(
            role: .user,
            text: trimmedDraft,
            attachments: images
        )
        var convo = conversations[convoIdx]
        convo.messages.append(userMessage)
        if convo.title == "New conversation" || convo.messages.count == 1 {
            convo.title = Conversation.deriveTitle(from: trimmedDraft.isEmpty ? "Image input" : trimmedDraft)
        }
        convo.updatedAt = Date()
        conversations[convoIdx] = convo
        moveActiveToTop()

        draft = ""
        draftImages = []

        // Append placeholder assistant message that streaming will populate.
        let assistantMessage = ChatMessage(role: .assistant, text: "", blocks: [])
        guard let convoIdx2 = conversations.firstIndex(where: { $0.id == activeConversationID }) else { return }
        conversations[convoIdx2].messages.append(assistantMessage)
        let assistantIdx = conversations[convoIdx2].messages.count - 1
        streamingMessageIndex = assistantIdx
        if autoFollowLatest { pinnedReplyIdx = assistantIdx }

        if AIWritingService.supports(model.provider) {
            guard let apiKey = APIKeyStore.read(for: model.provider) else {
                streamingMessageIndex = nil
                conversations[convoIdx2].messages.removeLast()
                startAddingKey(model.provider)
                return
            }
            startLiveStream(apiKey: apiKey, assistantIdx: assistantIdx)
        } else {
            startMockStream(userText: trimmedDraft, assistantIdx: assistantIdx)
        }
    }

    private func startLiveStream(apiKey: String, assistantIdx: Int) {
        guard let convoIdx = conversations.firstIndex(where: { $0.id == activeConversationID }) else { return }
        let snapshotConvo = conversations[convoIdx]
        var turns: [ChatTurn] = snapshotConvo.messages.prefix(assistantIdx).map { msg in
            ChatTurn(role: msg.role, text: msg.text, images: msg.attachments)
        }
        let trimmedContext = contextText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContext.isEmpty || !contextImages.isEmpty,
           let firstUser = turns.firstIndex(where: { $0.role == .user }) {
            let original = turns[firstUser]
            let preface = trimmedContext.isEmpty
                ? ""
                : "Reference material to keep in mind for this conversation:\n\n\(trimmedContext)\n\n---\n\n"
            turns[firstUser] = ChatTurn(
                role: .user,
                text: preface + original.text,
                images: contextImages + original.images
            )
        }
        let snapshotOperation = activeOperation
        let snapshotInstructions = customInstructions
        let snapshotModel = model
        let snapshotWebAccessEnabled = webAccessEnabled

        running = true
        runTask?.cancel()
        runTask = Task { [weak self] in
            do {
                let stream = AIWritingService.submitChatStream(
                    turns: turns,
                    operation: snapshotOperation,
                    customInstructions: snapshotInstructions,
                    model: snapshotModel,
                    webAccessEnabled: snapshotWebAccessEnabled,
                    apiKey: apiKey
                )
                for try await blocks in stream {
                    if Task.isCancelled { return }
                    await MainActor.run { self?.applyAssistantBlocks(blocks, at: assistantIdx) }
                }
                guard !Task.isCancelled, let self else { return }
                await MainActor.run { self.finishStreaming(at: assistantIdx) }
            } catch {
                guard !Task.isCancelled, let self else { return }
                await MainActor.run {
                    let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.applyAssistantBlocks(
                        [
                            .heading(text: "\(snapshotModel.provider.keyLabel) request failed"),
                            .paragraph(text: detail),
                        ],
                        at: assistantIdx
                    )
                    self.finishStreaming(at: assistantIdx)
                }
            }
        }
    }

    private func startMockStream(userText: String, assistantIdx: Int) {
        let snapshotOp = activeOperation
        let snapshotMode = mode
        let snapshotFmts = fmts
        let snapshotContainer = containerFormat
        let snapshotModel = model
        running = true
        runTask?.cancel()
        runTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, let self else { return }
            let blocks = MockGenerator.generate(
                input: userText.isEmpty ? "image" : userText,
                operation: snapshotOp,
                mode: snapshotMode,
                fmts: snapshotFmts,
                containerFormat: snapshotContainer,
                model: snapshotModel
            )
            await MainActor.run {
                self.applyAssistantBlocks(blocks, at: assistantIdx)
                self.finishStreaming(at: assistantIdx)
            }
        }
    }

    private func applyAssistantBlocks(_ blocks: [OutputBlock], at idx: Int) {
        guard let convoIdx = conversations.firstIndex(where: { $0.id == activeConversationID }) else { return }
        guard conversations[convoIdx].messages.indices.contains(idx) else { return }
        conversations[convoIdx].messages[idx].blocks = blocks
        conversations[convoIdx].messages[idx].text = MockGenerator.plainText(from: blocks)
        conversations[convoIdx].updatedAt = Date()
    }

    private func finishStreaming(at idx: Int) {
        running = false
        streamingMessageIndex = nil
        if autoFollowLatest { pinnedReplyIdx = idx }
        ConversationStore.save(conversations)
    }

    private func moveActiveToTop() {
        guard let id = activeConversationID,
              let idx = conversations.firstIndex(where: { $0.id == id }),
              idx != 0 else { return }
        let convo = conversations.remove(at: idx)
        conversations.insert(convo, at: 0)
    }

    // MARK: - External-text import

    func importSelectedTextFromActiveApp() {
        Task { [weak self] in
            let result = await SelectedTextCapture.capture()
            await MainActor.run {
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: true)
                switch result {
                case .success(let text):
                    self.draft = text
                case .accessibilityPermissionNeeded:
                    self.draft = "(Enable Accessibility permission in System Settings to import selected text.)"
                case .noText:
                    self.draft = ""
                }
            }
        }
    }

    // MARK: - Output copy

    func copyPinnedReply() {
        guard let msg = pinnedMessage else { return }
        let text = renderMode == .raw
            ? msg.blocks.text(for: containerFormat)
            : MockGenerator.plainText(from: msg.blocks)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text.isEmpty ? msg.text : text, forType: .string)
        copiedFlash = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run { self?.copiedFlash = false }
        }
    }

    func regeneratePinnedReply() {
        guard let pinnedIdx = pinnedReplyIdx,
              let convoIdx = conversations.firstIndex(where: { $0.id == activeConversationID }),
              conversations[convoIdx].messages.indices.contains(pinnedIdx),
              conversations[convoIdx].messages[pinnedIdx].role == .assistant else { return }
        // Find the last user message before pinnedIdx — re-run the streaming
        // with the same prompt, replacing the pinned assistant turn.
        let messagesBefore = conversations[convoIdx].messages.prefix(pinnedIdx)
        guard messagesBefore.last(where: { $0.role == .user }) != nil else { return }
        conversations[convoIdx].messages[pinnedIdx].blocks = []
        conversations[convoIdx].messages[pinnedIdx].text = ""
        let assistantIdx = pinnedIdx
        streamingMessageIndex = assistantIdx
        if AIWritingService.supports(model.provider),
           let apiKey = APIKeyStore.read(for: model.provider) {
            startLiveStream(apiKey: apiKey, assistantIdx: assistantIdx)
        } else {
            let lastUser = messagesBefore.last(where: { $0.role == .user })
            startMockStream(userText: lastUser?.text ?? "", assistantIdx: assistantIdx)
        }
    }
}
