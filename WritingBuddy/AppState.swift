import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var input: String = ""
    @Published var ops: Set<WritingOp> = [.cleanup]
    @Published var fmts: Set<OutputFormat> = [.paragraphs]
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

    private var runTask: Task<Void, Never>?

    init() {
        self.configuredProviders = Set(AIProvider.allCases.filter { KeychainStore.exists(for: $0) })
        self.history = HistoryStore.load()
    }

    func hasKey(for provider: AIProvider) -> Bool {
        configuredProviders.contains(provider)
    }

    func startAddingKey(_ provider: AIProvider) {
        addingKeyFor = provider
    }

    func cancelAddingKey() {
        addingKeyFor = nil
    }

    func saveAPIKey(_ key: String) {
        guard let provider = addingKeyFor else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainStore.save(trimmed, for: provider)
            configuredProviders.insert(provider)
            addingKeyFor = nil
        } catch {
            print("Keychain save failed for \(provider.rawValue):", error)
        }
    }

    var canRun: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(ops.isEmpty && fmts.isEmpty)
            && !running
    }

    var wordCount: Int {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.split { $0.isWhitespace }.count
    }

    func toggleOp(_ op: WritingOp) {
        ops = [op]
    }

    func toggleFormat(_ fmt: OutputFormat) {
        if fmts.contains(fmt) {
            guard fmts.count > 1 else { return }
            fmts.remove(fmt)
        } else {
            fmts.insert(fmt)
        }
    }

    func run() {
        guard canRun else { return }
        runTask?.cancel()
        let snapshotInput = input
        let snapshotOps = ops
        let snapshotFmts = fmts
        let snapshotModel = model
        let snapshotOp = WritingOp.allCases.first { snapshotOps.contains($0) } ?? .cleanup

        if snapshotModel.provider == .openai {
            guard let apiKey = KeychainStore.read(for: .openai) else {
                startAddingKey(.openai)
                return
            }
            runOpenAIImprove(
                input: snapshotInput,
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
                    operation: snapshotOp,
                    formats: snapshotFmts,
                    model: snapshotModel,
                    output: result
                )
            }
        }
    }

    private func runOpenAIImprove(
        input: String,
        operation: WritingOp,
        formats: Set<OutputFormat>,
        model: AIModel,
        apiKey: String
    ) {
        running = true
        output = nil
        runTask = Task { [weak self] in
            do {
                let blocks = try await OpenAIService.improve(
                    input: input,
                    operation: operation,
                    formats: formats,
                    model: model,
                    apiKey: apiKey
                )
                guard !Task.isCancelled, let self else { return }
                await MainActor.run {
                    self.finishRun(
                        input: input,
                        operation: operation,
                        formats: formats,
                        model: model,
                        output: blocks
                    )
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                await MainActor.run {
                    self.output = [.paragraph(text: "OpenAI request failed. Please check your API key and try again.")]
                    self.running = false
                }
            }
        }
    }

    private func finishRun(
        input: String,
        operation: WritingOp,
        formats: Set<OutputFormat>,
        model: AIModel,
        output blocks: [OutputBlock]
    ) {
        output = blocks
        running = false
        addHistoryItem(
            input: input,
            output: blocks,
            operation: operation,
            formats: formats,
            model: model
        )
    }

    private func addHistoryItem(
        input: String,
        output: [OutputBlock],
        operation: WritingOp,
        formats: Set<OutputFormat>,
        model: AIModel
    ) {
        let item = RecentItem(
            input: input,
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
        output = item.output
        ops = [item.operation]
        fmts = item.formats.isEmpty ? [.paragraphs] : item.formats
        if let restoredModel = AIModel.model(withID: item.modelID) {
            model = restoredModel
        }
        activeRecentID = item.id
    }

    func newSession() {
        runTask?.cancel()
        running = false
        input = ""
        output = nil
        activeRecentID = nil
    }

    func importSelectedTextFromActiveApp() {
        Task { [weak self] in
            let result = await SelectedTextCapture.capture()

            await MainActor.run {
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: true)

                switch result {
                case .success(let text):
                    self.runTask?.cancel()
                    self.running = false
                    self.input = text
                    self.output = nil
                    self.activeRecentID = nil

                case .accessibilityPermissionNeeded:
                    self.running = false
                    self.output = [
                        .paragraph(text: "WritingBuddy needs Accessibility permission to copy selected text from other apps. Enable it in System Settings, then try Control-A again.")
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
