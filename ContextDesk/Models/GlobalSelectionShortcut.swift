import AppKit
import ApplicationServices
import Carbon

@MainActor
final class GlobalSelectionShortcut {
    static let shared = GlobalSelectionShortcut()

    private static let signature = OSType(0x5742484B) // WBHK
    private static let hotKeyID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?
    private var currentShortcut: KeyboardShortcut?

    private init() {}

    /// Install the global handler and register `shortcut`. Subsequent calls
    /// just update the action — use `update(to:)` to change the binding.
    func start(shortcut: KeyboardShortcut, action: @escaping () -> Void) {
        self.action = action
        if eventHandlerRef == nil {
            installHandler()
        }
        register(shortcut: shortcut)
    }

    /// Swap the active hotkey at runtime — used when the user re-binds it
    /// from the Tweaks panel.
    func update(to shortcut: KeyboardShortcut) {
        guard shortcut != currentShortcut else { return }
        register(shortcut: shortcut)
    }

    func stop() {
        unregisterHotKey()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    // MARK: - Internals

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard parameterStatus == noErr,
                      hotKeyID.signature == GlobalSelectionShortcut.signature,
                      hotKeyID.id == GlobalSelectionShortcut.hotKeyID
                else {
                    return noErr
                }

                let shortcut = Unmanaged<GlobalSelectionShortcut>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                Task { @MainActor in
                    shortcut.action?()
                }

                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else {
            print("Global shortcut handler registration failed:", status)
            return
        }
    }

    private func register(shortcut: KeyboardShortcut) {
        unregisterHotKey()

        var newRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        guard status == noErr, let newRef else {
            print("Global \(shortcut.symbolDescription) shortcut registration failed:", status)
            return
        }

        hotKeyRef = newRef
        currentShortcut = shortcut
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        currentShortcut = nil
    }
}

enum SelectedTextCapture {
    enum Result {
        case success(String)
        case accessibilityPermissionNeeded
        case noText
    }

    static func capture() async -> Result {
        guard isAccessibilityTrusted() else {
            return .accessibilityPermissionNeeded
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(from: pasteboard)

        pasteboard.clearContents()
        let copyStartChangeCount = pasteboard.changeCount

        postCopyShortcut()

        let copiedText = await waitForCopiedText(
            on: pasteboard,
            after: copyStartChangeCount
        )

        snapshot.restore(to: pasteboard)

        guard let text = copiedText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return .noText
        }

        return .success(text)
    }

    private static func isAccessibilityTrusted() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    private static func postCopyShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(kVK_ANSI_C)

        let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        )
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        )
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func waitForCopiedText(
        on pasteboard: NSPasteboard,
        after changeCount: Int
    ) async -> String? {
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if pasteboard.changeCount != changeCount {
                return pasteboard.string(forType: .string)
            }
        }

        return pasteboard.string(forType: .string)
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(from pasteboard: NSPasteboard) {
        self.items = pasteboard.pasteboardItems?.map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let pasteboardItems = items.compactMap { contents -> NSPasteboardItem? in
            guard !contents.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }

        if !pasteboardItems.isEmpty {
            pasteboard.writeObjects(pasteboardItems)
        }
    }
}
