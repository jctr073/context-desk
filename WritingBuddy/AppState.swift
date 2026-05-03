import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var input: String = MockGenerator.sampleInput
    @Published var ops: Set<WritingOp> = [.cleanup]
    @Published var fmts: Set<OutputFormat> = [.paragraphs]
    @Published var output: [OutputBlock]? = nil
    @Published var running: Bool = false
    @Published var diffMode: Bool = false
    @Published var activeRecentID: String? = "r1"
    @Published var model: AIModel = .gpt55
    @Published var theme: AppTheme = .light
    @Published var layout: PaneLayout = .stacked
    @Published var copiedFlash: Bool = false
    @Published var configuredProviders: Set<AIProvider> = []
    @Published var addingKeyFor: AIProvider? = nil

    private var runTask: Task<Void, Never>?

    init() {
        self.configuredProviders = Set(AIProvider.allCases.filter { KeychainStore.exists(for: $0) })

        // Initial output so the design looks alive on first paint
        // (mirrors the React `useEffect` in the prototype).
        self.output = MockGenerator.generate(
            input: MockGenerator.sampleInput,
            ops: [.cleanup],
            fmts: [.paragraphs],
            model: model
        )
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
        if fmts.contains(fmt) { fmts.remove(fmt) } else { fmts.insert(fmt) }
    }

    func run() {
        guard canRun else { return }
        runTask?.cancel()
        let snapshotInput = input
        let snapshotOps = ops
        let snapshotFmts = fmts
        let snapshotModel = model

        if snapshotModel == .gpt55 {
            guard let apiKey = KeychainStore.read(for: .openai) else {
                startAddingKey(.openai)
                return
            }
            let snapshotOp = WritingOp.allCases.first { snapshotOps.contains($0) } ?? .cleanup
            runOpenAIImprove(input: snapshotInput, operation: snapshotOp, model: snapshotModel, apiKey: apiKey)
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
                self.output = result
                self.running = false
            }
        }
    }

    private func runOpenAIImprove(input: String, operation: WritingOp, model: AIModel, apiKey: String) {
        running = true
        output = nil
        runTask = Task { [weak self] in
            do {
                let text = try await OpenAIService.improve(input: input, operation: operation, model: model, apiKey: apiKey)
                guard !Task.isCancelled, let self else { return }
                await MainActor.run {
                    self.output = [.paragraph(text: text)]
                    self.running = false
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

    func newSession() {
        input = ""
        output = nil
        activeRecentID = nil
    }

    func copyOutput() {
        guard let blocks = output else { return }
        let text = MockGenerator.plainText(from: blocks)
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
