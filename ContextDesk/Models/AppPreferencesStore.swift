import Foundation

struct AppPreferences {
    let theme: AppTheme
    let defaultMode: WritingMode
    let importSelectionShortcut: KeyboardShortcut

    static let fallback = AppPreferences(
        theme: .dark,
        defaultMode: .chat,
        importSelectionShortcut: .defaultImportSelection
    )
}

enum AppPreferencesStore {
    private enum Key {
        static let theme = "ContextDesk.preferences.theme.v1"
        static let defaultMode = "ContextDesk.preferences.defaultMode.v1"
        static let importShortcutKeyCode = "ContextDesk.preferences.importShortcut.keyCode.v1"
        static let importShortcutModifiers = "ContextDesk.preferences.importShortcut.modifiers.v1"
    }

    /// Overridable for tests. Defaults to `.standard`.
    static var defaults: UserDefaults = .standard

    static func load() -> AppPreferences {
        AppPreferences(
            theme: storedTheme() ?? AppPreferences.fallback.theme,
            defaultMode: storedDefaultMode() ?? AppPreferences.fallback.defaultMode,
            importSelectionShortcut: storedImportShortcut()
                ?? AppPreferences.fallback.importSelectionShortcut
        )
    }

    static func saveTheme(_ theme: AppTheme) {
        defaults.set(theme.rawValue, forKey: Key.theme)
    }

    static func saveDefaultMode(_ mode: WritingMode) {
        defaults.set(mode.rawValue, forKey: Key.defaultMode)
    }

    static func saveImportSelectionShortcut(_ shortcut: KeyboardShortcut) {
        defaults.set(Int(shortcut.keyCode), forKey: Key.importShortcutKeyCode)
        defaults.set(Int(shortcut.modifiers), forKey: Key.importShortcutModifiers)
    }

    private static func storedTheme() -> AppTheme? {
        defaults.string(forKey: Key.theme).flatMap(AppTheme.init(rawValue:))
    }

    private static func storedDefaultMode() -> WritingMode? {
        defaults.string(forKey: Key.defaultMode).flatMap(WritingMode.init(rawValue:))
    }

    private static func storedImportShortcut() -> KeyboardShortcut? {
        guard defaults.object(forKey: Key.importShortcutKeyCode) != nil,
              defaults.object(forKey: Key.importShortcutModifiers) != nil
        else { return nil }
        let keyCode = UInt32(defaults.integer(forKey: Key.importShortcutKeyCode))
        let modifiers = UInt32(defaults.integer(forKey: Key.importShortcutModifiers))
        return KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
    }
}
