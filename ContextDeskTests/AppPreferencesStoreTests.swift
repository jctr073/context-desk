import XCTest
@testable import ContextDesk

final class AppPreferencesStoreTests: XCTestCase {
    private var tempDir: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    private var savedPreferencesDefaults: UserDefaults!
    private var savedConversationFileURL: URL!
    private var savedConversationLegacyFileURL: URL?
    private var savedHistoryFileURL: URL!
    private var savedHistoryLegacyFileURL: URL?
    private var savedHistoryDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AppPreferencesStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defaultsSuiteName = "AppPreferencesStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        XCTAssertNotNil(defaults)

        savedPreferencesDefaults = AppPreferencesStore.defaults
        savedConversationFileURL = ConversationStore.fileURL
        savedConversationLegacyFileURL = ConversationStore.legacyFileURL
        savedHistoryFileURL = HistoryStore.fileURL
        savedHistoryLegacyFileURL = HistoryStore.legacyFileURL
        savedHistoryDefaults = HistoryStore.defaults

        AppPreferencesStore.defaults = defaults
        ConversationStore.fileURL = tempDir.appendingPathComponent("conversations.json")
        ConversationStore.legacyFileURL = nil
        HistoryStore.fileURL = tempDir.appendingPathComponent("history.json")
        HistoryStore.legacyFileURL = nil
        HistoryStore.defaults = defaults
    }

    override func tearDownWithError() throws {
        AppPreferencesStore.defaults = savedPreferencesDefaults
        ConversationStore.fileURL = savedConversationFileURL
        ConversationStore.legacyFileURL = savedConversationLegacyFileURL
        HistoryStore.fileURL = savedHistoryFileURL
        HistoryStore.legacyFileURL = savedHistoryLegacyFileURL
        HistoryStore.defaults = savedHistoryDefaults

        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testLoadFallsBackToBuiltInDefaults() {
        let preferences = AppPreferencesStore.load()

        XCTAssertEqual(preferences.theme, .dark)
        XCTAssertEqual(preferences.defaultMode, .chat)
    }

    @MainActor
    func testAppStatePersistsAndRestoresTweaksAcrossLaunches() {
        let state = AppState()

        state.theme = .light
        state.defaultMode = .writing

        let restored = AppState()
        XCTAssertEqual(restored.theme, .light)
        XCTAssertEqual(restored.defaultMode, .writing)
        XCTAssertEqual(restored.mode, .writing)
    }
}
