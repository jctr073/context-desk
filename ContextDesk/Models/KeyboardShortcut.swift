import AppKit
import Carbon

/// A keyboard combination (Carbon virtual key + Carbon modifier mask) suitable
/// for `RegisterEventHotKey`. Stored verbatim in `UserDefaults` so a user's
/// override survives across launches.
struct KeyboardShortcut: Equatable, Hashable {
    /// Carbon virtual key code, e.g. `kVK_ANSI_A`.
    let keyCode: UInt32
    /// Carbon modifier mask: bitwise-or of `cmdKey | optionKey | controlKey | shiftKey`.
    let modifiers: UInt32

    static let defaultImportSelection = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: UInt32(controlKey)
    )

    /// At least one of ⌃/⌥/⇧/⌘ must be present — a bare letter would hijack
    /// the key system-wide and prevent the user from typing it anywhere.
    var hasModifier: Bool {
        modifiers & UInt32(cmdKey | optionKey | controlKey | shiftKey) != 0
    }

    /// Compact symbol form, e.g. `⌃A`, `⌃⇧V`. Used in the panel chip.
    var symbolDescription: String {
        var out = ""
        if modifiers & UInt32(controlKey) != 0 { out += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { out += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0 { out += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0 { out += "⌘" }
        out += KeyCodeNames.label(for: keyCode)
        return out
    }
}

// MARK: - NSEvent → KeyboardShortcut

extension KeyboardShortcut {
    /// Build a shortcut from an `NSEvent.keyDown`. Returns `nil` for events
    /// that wouldn't make a usable global hotkey (modifiers-only, etc).
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = modifiers
    }

    /// Convert AppKit's `NSEvent.ModifierFlags` to the Carbon mask used by
    /// `RegisterEventHotKey`.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command)  { mask |= UInt32(cmdKey) }
        if flags.contains(.option)   { mask |= UInt32(optionKey) }
        if flags.contains(.control)  { mask |= UInt32(controlKey) }
        if flags.contains(.shift)    { mask |= UInt32(shiftKey) }
        return mask
    }
}

// MARK: - Pretty printing

private enum KeyCodeNames {
    static func label(for keyCode: UInt32) -> String {
        if let named = named[Int(keyCode)] { return named }

        // Letter / number keys: ask AppKit's keyboard layout for a glyph.
        if let glyph = glyph(for: keyCode) {
            return glyph.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static let named: [Int: String] = [
        kVK_Return:           "↩",
        kVK_Tab:              "⇥",
        kVK_Space:            "Space",
        kVK_Delete:           "⌫",
        kVK_ForwardDelete:    "⌦",
        kVK_Escape:           "⎋",
        kVK_LeftArrow:        "←",
        kVK_RightArrow:       "→",
        kVK_DownArrow:        "↓",
        kVK_UpArrow:          "↑",
        kVK_Home:             "↖",
        kVK_End:              "↘",
        kVK_PageUp:           "⇞",
        kVK_PageDown:         "⇟",
        kVK_F1:  "F1",  kVK_F2:  "F2",  kVK_F3:  "F3",  kVK_F4:  "F4",
        kVK_F5:  "F5",  kVK_F6:  "F6",  kVK_F7:  "F7",  kVK_F8:  "F8",
        kVK_F9:  "F9",  kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Translate the virtual key code through the active keyboard layout so
    /// "Q" on AZERTY shows "A", etc.
    private static func glyph(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
              let bytes = CFDataGetBytePtr(unsafeBitCast(layoutData, to: CFData.self))
        else { return nil }

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var realLength = 0

        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layoutPtr in
            UCKeyTranslate(
                layoutPtr,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &realLength,
                &chars
            )
        }

        guard status == noErr, realLength > 0 else { return nil }
        let glyph = String(utf16CodeUnits: chars, count: realLength)
        return glyph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : glyph
    }
}
