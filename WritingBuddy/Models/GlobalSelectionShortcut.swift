import AppKit
import ApplicationServices
import Carbon

@MainActor
final class GlobalSelectionShortcut {
    static let shared = GlobalSelectionShortcut()

    private static let signature = OSType(0x5742484B) // WBHK
    private static let importSelectionID = UInt32(1)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    private init() {}

    func start(action: @escaping () -> Void) {
        self.action = action
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
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
                      hotKeyID.id == GlobalSelectionShortcut.importSelectionID
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

        guard handlerStatus == noErr else {
            print("Global shortcut handler registration failed:", handlerStatus)
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.importSelectionID
        )

        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            UInt32(controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if hotKeyStatus != noErr {
            print("Global Control-A shortcut registration failed:", hotKeyStatus)
            stop()
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
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
