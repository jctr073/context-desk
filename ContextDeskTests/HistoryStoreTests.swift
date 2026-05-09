import XCTest
@testable import ContextDesk

final class HistoryStoreTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    private let legacyKey = "WritingBuddy.history.v1"

    private var savedFileURL: URL!
    private var savedLegacyFileURL: URL?
    private var savedDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("history.json")

        defaultsSuiteName = "HistoryStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        XCTAssertNotNil(defaults)

        savedFileURL = HistoryStore.fileURL
        savedLegacyFileURL = HistoryStore.legacyFileURL
        savedDefaults = HistoryStore.defaults
        HistoryStore.fileURL = fileURL
        HistoryStore.legacyFileURL = nil
        HistoryStore.defaults = defaults
    }

    override func tearDownWithError() throws {
        HistoryStore.fileURL = savedFileURL
        HistoryStore.legacyFileURL = savedLegacyFileURL
        HistoryStore.defaults = savedDefaults
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testRoundTripSaveAndLoad() async throws {
        let item = makeItem(id: "a", input: "hello", createdAt: Date(timeIntervalSince1970: 1_000))
        await HistoryStore.save([item]).value

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let loaded = HistoryStore.load()
        XCTAssertEqual(loaded.map(\.id), ["a"])
        XCTAssertEqual(loaded.first?.input, "hello")
    }

    func testMigratesLegacyUserDefaultsBlobAndRemovesKey() throws {
        let older = makeItem(id: "old", input: "older", createdAt: Date(timeIntervalSince1970: 1_000))
        let newer = makeItem(id: "new", input: "newer", createdAt: Date(timeIntervalSince1970: 2_000))
        let blob = try JSONEncoder().encode([older, newer])
        defaults.set(blob, forKey: legacyKey)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        let loaded = HistoryStore.load()

        XCTAssertEqual(loaded.map(\.id), ["new", "old"], "load() should return items sorted newest-first")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "migration should write history.json before clearing UserDefaults")
        XCTAssertNil(defaults.data(forKey: legacyKey), "legacy UserDefaults key should be removed after successful migration")

        let onDisk = try JSONDecoder().decode([RecentItem].self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(Set(onDisk.map(\.id)), ["old", "new"])
    }

    func testReturnsEmptyWhenNoFileAndNoLegacyKey() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(defaults.data(forKey: legacyKey))
        XCTAssertEqual(HistoryStore.load(), [])
    }

    private func makeItem(id: String, input: String, createdAt: Date) -> RecentItem {
        RecentItem(
            id: id,
            createdAt: createdAt,
            input: input,
            output: [.paragraph(text: "out: \(input)")],
            operationID: "rewrite",
            operationLabel: "Rewrite",
            modelID: "test-model"
        )
    }
}
