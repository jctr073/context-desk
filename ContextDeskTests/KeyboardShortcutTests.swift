import AppKit
import Carbon
import XCTest
@testable import ContextDesk

final class KeyboardShortcutTests: XCTestCase {
    func testDefaultIsControlA() {
        let s = KeyboardShortcut.defaultImportSelection
        XCTAssertEqual(s.keyCode, UInt32(kVK_ANSI_A))
        XCTAssertEqual(s.modifiers, UInt32(controlKey))
        XCTAssertTrue(s.hasModifier)
    }

    func testHasModifierRejectsBareKey() {
        let bare = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0)
        XCTAssertFalse(bare.hasModifier)

        let withCmd = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey))
        XCTAssertTrue(withCmd.hasModifier)
    }

    func testSymbolDescriptionRendersModifierStack() {
        let combo = KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(controlKey | shiftKey | cmdKey)
        )
        XCTAssertEqual(combo.symbolDescription, "⌃⇧⌘V")
    }

    func testCarbonModifiersFromNSEventFlags() {
        let mask = KeyboardShortcut.carbonModifiers(from: [.command, .shift])
        XCTAssertEqual(mask, UInt32(cmdKey | shiftKey))

        XCTAssertEqual(KeyboardShortcut.carbonModifiers(from: []), 0)
    }
}

final class AppPreferencesShortcutPersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var savedDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "KeyboardShortcutPersistTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        XCTAssertNotNil(defaults)
        savedDefaults = AppPreferencesStore.defaults
        AppPreferencesStore.defaults = defaults
    }

    override func tearDownWithError() throws {
        AppPreferencesStore.defaults = savedDefaults
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    func testFallsBackToDefaultWhenUnset() {
        let loaded = AppPreferencesStore.load()
        XCTAssertEqual(loaded.importSelectionShortcut, .defaultImportSelection)
    }

    func testRoundTripsCustomShortcut() {
        let custom = KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | optionKey)
        )
        AppPreferencesStore.saveImportSelectionShortcut(custom)

        let loaded = AppPreferencesStore.load()
        XCTAssertEqual(loaded.importSelectionShortcut, custom)
    }
}
