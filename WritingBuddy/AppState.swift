import SwiftUI

enum InputTab: String, CaseIterable, Identifiable, Hashable {
    case input
    case context

    var id: String { rawValue }

    var label: String {
        switch self {
        case .input:   return "Input"
        case .context: return "Context"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var input: String = ""
    @Published var context: String = ""
    @Published var customInstructions: String = ""
    @Published var inputTab: InputTab = .input
    @Published var editingInstructions: Bool = false
    @Published var ops: Set<WritingOp> = [.cleanup]
    @Published var fmts: Set<OutputFormat> = []
    @Published var output: [OutputBlock]? = nil
    @Published var running: Bool = false
    @Published var diffMode: Bool = false
    @Published var renderMode: RenderMode = .rendered
    @Published var activeRecentID: String? = nil
    @Published var history: [RecentItem] = []
    @Published var model: AIModel = .gpt55Medium
    @Published var theme: AppTheme = .light
    @Published var layout: PaneLayout = .stacked
    @Published var copiedFlash: Bool = false
    @Published var configuredProviders: Set<AIProvider> = []
    @Published var addingKeyFor: AIProvider? = nil
    @Published var historyVisible: Bool = true
    @Published var inputImages: [AttachedImage] = []
    @Published var contextImages: [AttachedImage] = []
    @Published var lightboxImage: AttachedImage? = nil
    /// ID of the most-recently-added image, used to drive the bounce/flash animation.
    @Published var lastAddedImageID: String? = nil
    @Published var pasteFlash: Bool = false

    private var runTask: Task<Void, Never>?
    private var pasteFlashTask: Task<Void, Never>?

    init() {
        self.configuredProviders = Self.configuredProviderSet()
        self.history = HistoryStore.load()
    }

    func hasKey(for provider: AIProvider) -> Bool {
        configuredProviders.contains(provider) || APIKeyStore.exists(for: provider)
    }

    func startAddingKey(_ provider: AIProvider) {
        addingKeyFor = provider
    }

    func cancelAddingKey() {
        addingKeyFor = nil
    }

    var canRun: Bool {
        let hasInputText = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasInputImages = !inputImages.isEmpty
        let canUseImageOnlyInput = AIWritingService.supports(model.provider)
        return (hasInputText || (hasInputImages && canUseImageOnlyInput))
            && !(ops.isEmpty && fmts.isEmpty)
            && !running
    }

    var currentTabImages: [AttachedImage] {
        inputTab == .input ? inputImages : contextImages
    }

    var currentTabImageCount: Int {
        currentTabImages.count
    }

    func attachImage(_ image: AttachedImage, to tab: InputTab) {
        switch tab {
        case .input:   inputImages.append(image)
        case .context: contextImages.append(image)
        }
        lastAddedImageID = image.id
        triggerPasteFlash()
    }

    func attachImages(_ images: [AttachedImage], to tab: InputTab) {
        guard !images.isEmpty else { return }
        switch tab {
        case .input:   inputImages.append(contentsOf: images)
        case .context: contextImages.append(contentsOf: images)
        }
        lastAddedImageID = images.last?.id
        triggerPasteFlash()
    }

    func removeImage(_ image: AttachedImage, from tab: InputTab) {
        switch tab {
        case .input:   inputImages.removeAll { $0.id == image.id }
        case .context: contextImages.removeAll { $0.id == image.id }
        }
        if lastAddedImageID == image.id {
            lastAddedImageID = nil
        }
    }

    func showLightbox(_ image: AttachedImage) {
        lightboxImage = image
    }

    func dismissLightbox() {
        lightboxImage = nil
    }

    private func triggerPasteFlash() {
        pasteFlash = true
        pasteFlashTask?.cancel()
        pasteFlashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            await MainActor.run { self?.pasteFlash = false }
        }
    }

    var wordCount: Int {
        let source = inputTab == .input ? input : context
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.split { $0.isWhitespace }.count
    }

    var outputWordCount: Int {
        guard let blocks = output else { return 0 }
        let trimmed = MockGenerator.plainText(from: blocks)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.split { $0.isWhitespace }.count
    }

    var hasCustomInstructions: Bool {
        !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleOp(_ op: WritingOp) {
        ops = [op]
    }

    func toggleHistoryVisible() {
        historyVisible.toggle()
    }

    var isAutomaticFormat: Bool { fmts.isEmpty }

    func setAutomaticFormat() {
        fmts.removeAll()
    }

    func toggleFormat(_ fmt: OutputFormat) {
        if fmts.contains(fmt) {
            fmts.remove(fmt)
        } else {
            fmts.insert(fmt)
        }
    }

    func run() {
        guard canRun else { return }
        runTask?.cancel()
        let snapshotInput = input
        let snapshotContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshotInstructions = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshotInputImages = inputImages
        let snapshotContextImages = contextImages
        let snapshotOps = ops
        let snapshotFmts = fmts
        let snapshotModel = model
        let snapshotOp = WritingOp.allCases.first { snapshotOps.contains($0) } ?? .cleanup

        if AIWritingService.supports(snapshotModel.provider) {
            let provider = snapshotModel.provider
            configuredProviders = Self.configuredProviderSet()

            guard let apiKey = APIKeyStore.read(for: provider) else {
                startAddingKey(provider)
                return
            }
            runAIImprove(
                input: snapshotInput,
                context: snapshotContext,
                customInstructions: snapshotInstructions,
                inputImages: snapshotInputImages,
                contextImages: snapshotContextImages,
                operation: snapshotOp,
                formats: snapshotFmts,
                model: snapshotModel,
                apiKey: apiKey
            )
            return
        }

        running = true
        output = nil
        runTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000) // 650ms — matches prototype
            guard !Task.isCancelled, let self else { return }
            let result = MockGenerator.generate(
                input: snapshotInput,
                ops: snapshotOps,
                fmts: snapshotFmts,
                model: snapshotModel
            )
            await MainActor.run {
                self.finishRun(
                    input: snapshotInput,
                    context: snapshotContext,
                    inputImages: snapshotInputImages,
                    contextImages: snapshotContextImages,
                    operation: snapshotOp,
                    formats: snapshotFmts,
                    model: snapshotModel,
                    output: result
                )
            }
        }
    }

    private static func configuredProviderSet() -> Set<AIProvider> {
        Set(AIProvider.allCases.filter { APIKeyStore.exists(for: $0) })
    }

    private func runAIImprove(
        input: String,
        context: String,
        customInstructions: String,
        inputImages: [AttachedImage],
        contextImages: [AttachedImage],
        operation: WritingOp,
        formats: Set<OutputFormat>,
        model: AIModel,
        apiKey: String
    ) {
        running = true
        output = nil
        runTask = Task { [weak self] in
            do {
                let blocks = try await AIWritingService.improve(
                    input: input,
                    context: context,
                    customInstructions: customInstructions,
                    inputImages: inputImages,
                    contextImages: contextImages,
                    operation: operation,
                    formats: formats,
                    model: model,
                    apiKey: apiKey
                )
                guard !Task.isCancelled, let self else { return }
                await MainActor.run {
                    self.finishRun(
                        input: input,
                        context: context,
                        inputImages: inputImages,
                        contextImages: contextImages,
                        operation: operation,
                        formats: formats,
                        model: model,
                        output: blocks
                    )
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                await MainActor.run {
                    self.output = [.paragraph(text: "\(model.provider.keyLabel) request failed. Please check your API key and try again.")]
                    self.running = false
                }
            }
        }
    }

    private func finishRun(
        input: String,
        context: String,
        inputImages: [AttachedImage],
        contextImages: [AttachedImage],
        operation: WritingOp,
        formats: Set<OutputFormat>,
        model: AIModel,
        output blocks: [OutputBlock]
    ) {
        output = blocks
        running = false
        addHistoryItem(
            input: input,
            context: context,
            inputImages: inputImages,
            contextImages: contextImages,
            output: blocks,
            operation: operation,
            formats: formats,
            model: model
        )
    }

    private func addHistoryItem(
        input: String,
        context: String,
        inputImages: [AttachedImage],
        contextImages: [AttachedImage],
        output: [OutputBlock],
        operation: WritingOp,
        formats: Set<OutputFormat>,
        model: AIModel
    ) {
        let item = RecentItem(
            input: input,
            context: context,
            inputImages: inputImages,
            contextImages: contextImages,
            output: output,
            operation: operation,
            formats: formats,
            modelID: model.id
        )
        history.removeAll { $0.id == item.id }
        history.insert(item, at: 0)
        history = Array(history.prefix(HistoryStore.maxItems))
        HistoryStore.save(history)
        activeRecentID = item.id
    }

    func selectHistoryItem(_ item: RecentItem) {
        runTask?.cancel()
        running = false
        input = item.input
        context = item.context
        inputImages = item.inputImages
        contextImages = item.contextImages
        inputTab = .input
        output = item.output
        ops = [item.operation]
        fmts = item.formats
        if let restoredModel = AIModel.model(withID: item.modelID) {
            model = restoredModel
        }
        activeRecentID = item.id
    }

    func newSession() {
        runTask?.cancel()
        running = false
        input = ""
        context = ""
        customInstructions = ""
        inputImages = []
        contextImages = []
        lastAddedImageID = nil
        inputTab = .input
        output = nil
        activeRecentID = nil
    }

    func startEditingInstructions() {
        editingInstructions = true
    }

    func cancelEditingInstructions() {
        editingInstructions = false
    }

    func saveCustomInstructions(_ text: String) {
        customInstructions = text
        editingInstructions = false
    }

    func importSelectedTextFromActiveApp(to targetTab: InputTab = .input) {
        Task { [weak self] in
            let result = await SelectedTextCapture.capture()

            await MainActor.run {
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: true)

                switch result {
                case .success(let text):
                    self.runTask?.cancel()
                    self.running = false
                    self.applyImportedSelectedText(text, to: targetTab)
                    self.output = nil
                    self.activeRecentID = nil

                case .accessibilityPermissionNeeded:
                    self.running = false
                    self.output = [
                        .paragraph(text: "WritingBuddy needs Accessibility permission to copy selected text from other apps. Enable it in System Settings, then try Control-A or Control-Q again.")
                    ]

                case .noText:
                    self.running = false
                    self.output = [
                        .paragraph(text: "No selected text was available to import.")
                    ]
                }
            }
        }
    }

    private func applyImportedSelectedText(_ text: String, to targetTab: InputTab) {
        switch targetTab {
        case .input:
            input = text
            inputImages = []
            contextImages = []
        case .context:
            context = text
            contextImages = []
        }
        lastAddedImageID = nil
        inputTab = targetTab
    }

    func copyOutput() {
        guard let blocks = output else { return }
        let text = renderMode == .raw
            ? blocks.markdown
            : MockGenerator.plainText(from: blocks)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copiedFlash = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run { self?.copiedFlash = false }
        }
    }
}
