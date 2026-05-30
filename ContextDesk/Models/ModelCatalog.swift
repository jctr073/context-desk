import Foundation

enum FetchState: Equatable {
    case idle
    case loading
    case ok(Date)
    case failed(String)
}

/// Owns the merged family → latest-model state that drives the model picker.
/// Loads a cached snapshot for an instant offline-safe UI, then refreshes from
/// each provider's live `/models` endpoint (when a key exists) and falls back
/// to the bundled baseline whenever discovery is missing or fails.
@MainActor
final class ModelCatalog: ObservableObject {
    @Published private(set) var resolved: [String: ResolvedFamily] = [:]
    @Published private(set) var derivedRows: [DiscoveredModel] = []
    @Published private(set) var fetchState: [AIProvider: FetchState] = [:]

    let families = ModelFamily.bundled
    static let fetchableProviders: [AIProvider] = [.anthropic, .openai]

    /// Invoked after discovery updates `resolved`, so the owner can re-resolve
    /// the currently-selected model to its latest concrete id/name.
    var onCatalogUpdated: (() -> Void)?

    private let listing: ModelListing
    private let keyProvider: (AIProvider) -> String?
    private let now: () -> Date

    private var lastFetchStart: [AIProvider: Date] = [:]
    private var lastSuccess: [AIProvider: Date] = [:]
    private var inFlight: Set<AIProvider> = []

    private let debounceInterval: TimeInterval = 30
    private let staleTTL: TimeInterval = 6 * 60 * 60

    init(
        listing: ModelListing = ModelListingService(),
        keyProvider: @escaping (AIProvider) -> String? = { APIKeyStore.read(for: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.listing = listing
        self.keyProvider = keyProvider
        self.now = now
    }

    // MARK: - UI surface

    func familyRows(for provider: AIProvider) -> [ModelFamily] {
        families.filter { $0.provider == provider }
    }

    func derivedModels(for provider: AIProvider) -> [AIModel] {
        derivedRows.filter { $0.provider == provider }.map(derivedAIModel)
    }

    func displayName(for family: ModelFamily) -> String {
        resolved[family.id]?.displayName ?? family.bundledDisplayName
    }

    func aiModel(family: ModelFamily, effort: ReasoningEffort?) -> AIModel {
        family.aiModel(effort: effort, resolved: resolved[family.id])
    }

    func family(for model: AIModel) -> ModelFamily? {
        ModelFamily.resolve(id: model.id)?.family
    }

    /// Catalog-aware resolution of a persisted id: composite/family/legacy →
    /// live or baseline `AIModel`; then derived rows; then the static baseline.
    func model(withID id: String) -> AIModel? {
        if let (family, effort) = ModelFamily.resolve(id: id) {
            return family.aiModel(effort: effort, resolved: resolved[family.id])
        }
        if let derived = derivedRows.first(where: { $0.apiModelID == id }) {
            return derivedAIModel(derived)
        }
        return AIModel.all.first { $0.id == id }
    }

    private func derivedAIModel(_ model: DiscoveredModel) -> AIModel {
        AIModel(
            id: model.apiModelID,
            name: model.displayName ?? ModelFamily.prettify(model.apiModelID),
            provider: model.provider,
            apiModelID: model.apiModelID,
            reasoningEffort: nil
        )
    }

    // MARK: - Lifecycle

    /// Load the cached snapshot (instant) then refresh any keyed provider whose
    /// cache is stale. Safe to call when offline / unkeyed.
    func bootstrap() {
        if let snapshot = ModelCatalogStore.load() {
            apply(snapshot)
        }
        for provider in Self.fetchableProviders where keyProvider(provider) != nil {
            if isStale(provider) { refresh(provider) }
        }
    }

    /// Debounced refresh of keyed providers when the picker is opened.
    func onPickerOpened() {
        refresh()
    }

    /// Refresh one provider (or all fetchable). `force` bypasses the debounce.
    func refresh(_ provider: AIProvider? = nil, force: Bool = false) {
        let targets = provider.map { [$0] } ?? Self.fetchableProviders
        for provider in targets {
            guard let key = keyProvider(provider) else { continue }
            guard !inFlight.contains(provider) else { continue }
            if !force, let started = lastFetchStart[provider],
               now().timeIntervalSince(started) < debounceInterval { continue }

            inFlight.insert(provider)
            lastFetchStart[provider] = now()
            fetchState[provider] = .loading
            Task { await self.runFetch(provider: provider, key: key) }
        }
    }

    private func runFetch(provider: AIProvider, key: String) async {
        do {
            let discovered = try await listing.fetch(provider: provider, apiKey: key)
            let providerFamilies = families.filter { $0.provider == provider }
            let (newResolved, newDerived) = FamilyResolver.resolve(discovered, families: providerFamilies)
            // Replace only this provider's slice; leave other providers intact.
            for family in providerFamilies { resolved[family.id] = newResolved[family.id] }
            derivedRows = derivedRows.filter { $0.provider != provider } + newDerived
            lastSuccess[provider] = now()
            fetchState[provider] = .ok(now())
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            fetchState[provider] = .failed(detail)
        }
        inFlight.remove(provider)
        persist()
        onCatalogUpdated?()
    }

    // MARK: - Cache

    private func apply(_ snapshot: ModelCatalogStore.Snapshot) {
        resolved = Dictionary(uniqueKeysWithValues: snapshot.resolved.map { ($0.familyID, $0) })
        derivedRows = snapshot.derived
        for (raw, date) in snapshot.fetchedAt {
            guard let provider = AIProvider(rawValue: raw) else { continue }
            lastSuccess[provider] = date
            fetchState[provider] = .ok(date)
        }
    }

    private func persist() {
        let snapshot = ModelCatalogStore.Snapshot(
            resolved: Array(resolved.values),
            derived: derivedRows,
            fetchedAt: lastSuccess.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
            schemaVersion: ModelCatalogStore.schemaVersion
        )
        ModelCatalogStore.save(snapshot)
    }

    private func isStale(_ provider: AIProvider) -> Bool {
        guard let last = lastSuccess[provider] else { return true }
        return now().timeIntervalSince(last) > staleTTL
    }
}
