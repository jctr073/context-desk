import XCTest
@testable import ContextDesk

private struct StubListing: ModelListing {
    var byProvider: [AIProvider: [DiscoveredModel]] = [:]
    var error: Error?

    func fetch(provider: AIProvider, apiKey: String) async throws -> [DiscoveredModel] {
        if let error { throw error }
        return byProvider[provider] ?? []
    }
}

private struct StubError: LocalizedError {
    var errorDescription: String? { "stub failure" }
}

@MainActor
final class ModelCatalogTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var savedDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "ModelCatalogTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        savedDefaults = ModelCatalogStore.defaults
        ModelCatalogStore.defaults = defaults
    }

    override func tearDownWithError() throws {
        ModelCatalogStore.defaults = savedDefaults
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeCatalog(_ listing: ModelListing) -> ModelCatalog {
        ModelCatalog(listing: listing, keyProvider: { _ in "test-key" }, now: Date.init)
    }

    func testOfflineFallbackUsesBaseline() {
        let catalog = makeCatalog(StubListing())
        let opus = catalog.familyRows(for: .anthropic).first { $0.id == "claude-opus" }!
        let model = catalog.aiModel(family: opus, effort: .high)
        XCTAssertEqual(model.apiModelID, "claude-opus-4-7")
        XCTAssertEqual(catalog.displayName(for: opus), "Claude Opus 4.7")
    }

    func testFetchUpdatesResolvedAndModelLookup() async {
        let listing = StubListing(byProvider: [
            .anthropic: [
                DiscoveredModel(apiModelID: "claude-opus-4-8", displayName: nil, provider: .anthropic),
                DiscoveredModel(apiModelID: "claude-sonnet-4-6", displayName: nil, provider: .anthropic),
            ],
        ])
        let catalog = makeCatalog(listing)

        let updated = expectation(description: "catalog updated")
        catalog.onCatalogUpdated = { updated.fulfill() }
        catalog.refresh(.anthropic, force: true)
        await fulfillment(of: [updated], timeout: 2)

        XCTAssertEqual(catalog.resolved["claude-opus"]?.apiModelID, "claude-opus-4-8")
        let opus = catalog.familyRows(for: .anthropic).first { $0.id == "claude-opus" }!
        XCTAssertEqual(catalog.displayName(for: opus), "Claude Opus 4.8")
        // A persisted selection now resolves to the freshly-discovered id.
        XCTAssertEqual(catalog.model(withID: "claude-opus#high")?.apiModelID, "claude-opus-4-8")
    }

    func testFetchFailureLeavesCatalogUsable() async {
        let catalog = makeCatalog(StubListing(error: StubError()))

        let updated = expectation(description: "catalog updated")
        catalog.onCatalogUpdated = { updated.fulfill() }
        catalog.refresh(.anthropic, force: true)
        await fulfillment(of: [updated], timeout: 2)

        if case .failed = catalog.fetchState[.anthropic] {} else {
            XCTFail("expected failed fetch state")
        }
        // Still falls back to baseline.
        let opus = catalog.familyRows(for: .anthropic).first { $0.id == "claude-opus" }!
        XCTAssertEqual(catalog.aiModel(family: opus, effort: .high).apiModelID, "claude-opus-4-7")
    }

    func testCacheRoundTrip() {
        let snapshot = ModelCatalogStore.Snapshot(
            resolved: [ResolvedFamily(familyID: "claude-opus", apiModelID: "claude-opus-4-8", displayName: "Claude Opus 4.8")],
            derived: [DiscoveredModel(apiModelID: "claude-neptune-1", displayName: nil, provider: .anthropic)],
            fetchedAt: ["anthropic": Date(timeIntervalSince1970: 1_000_000)],
            schemaVersion: ModelCatalogStore.schemaVersion
        )
        ModelCatalogStore.save(snapshot)

        let loaded = ModelCatalogStore.load()
        XCTAssertEqual(loaded?.resolved.first?.apiModelID, "claude-opus-4-8")
        XCTAssertEqual(loaded?.derived.first?.apiModelID, "claude-neptune-1")
    }

    func testCacheSchemaMismatchDiscarded() {
        let snapshot = ModelCatalogStore.Snapshot(
            resolved: [], derived: [], fetchedAt: [:],
            schemaVersion: ModelCatalogStore.schemaVersion + 1
        )
        ModelCatalogStore.save(snapshot)
        XCTAssertNil(ModelCatalogStore.load())
    }
}
