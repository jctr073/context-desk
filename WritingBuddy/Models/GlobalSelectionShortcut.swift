import AppKit
import ApplicationServices
import Carbon

@MainActor
final class GlobalSelectionShortcut {
    static let shared = GlobalSelectionShortcut()

    private static let signature = OSType(0x5742484B) // WBHK

    private enum HotKey: UInt32, CaseIterable {
        case importInput = 1
        case importContext = 2

        var keyCode: UInt32 {
            switch self {
            case .importInput: return UInt32(kVK_ANSI_A)
            case .importContext: return UInt32(kVK_ANSI_Q)
            }
        }

        var targetTab: InputTab {
            switch self {
            case .importInput: return .input
            case .importContext: return .context
            }
        }

        var label: String {
            switch self {
            case .importInput: return "Control-A"
            case .importContext: return "Control-Q"
            }
        }
    }

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var action: ((InputTab) -> Void)?

    private init() {}

    func start(action: @escaping (InputTab) -> Void) {
        self.action = action
        guard hotKeyRefs.isEmpty else { return }

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
                      let hotKey = HotKey(rawValue: hotKeyID.id)
                else {
                    return noErr
                }

                let shortcut = Unmanaged<GlobalSelectionShortcut>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                Task { @MainActor in
                    shortcut.action?(hotKey.targetTab)
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

        for hotKey in HotKey.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(
                signature: Self.signature,
                id: hotKey.rawValue
            )

            let hotKeyStatus = RegisterEventHotKey(
                hotKey.keyCode,
                UInt32(controlKey),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            guard hotKeyStatus == noErr, let hotKeyRef else {
                print("Global \(hotKey.label) shortcut registration failed:", hotKeyStatus)
                stop()
                return
            }

            hotKeyRefs.append(hotKeyRef)
        }
    }

    func stop() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()

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
