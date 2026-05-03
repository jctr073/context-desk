import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()

    var body: some View {
        let palette = Palette.native(for: state.theme)

        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                Titlebar(state: state, palette: palette)
                body(palette: palette)
            }
            .background(palette.bg)
            .preferredColorScheme(state.theme.colorScheme)
            // Hidden keyboard shortcuts for op chips
            .background(KeyboardShortcuts(state: state))

            TweaksPanel(state: state, palette: palette)
                .padding(.trailing, 16)
                .padding(.bottom, 16)

            apiKeyOverlay(palette: palette)
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(WindowAccessor())
        .onAppear {
            GlobalSelectionShortcut.shared.start {
                state.importSelectedTextFromActiveApp()
            }
        }
        .onDisappear {
            GlobalSelectionShortcut.shared.stop()
        }
    }

    @ViewBuilder
    private func apiKeyOverlay(palette: Palette) -> some View {
        ZStack {
            if let provider = state.addingKeyFor {
                palette.modalScrim
                    .ignoresSafeArea()
                    .onTapGesture { state.cancelAddingKey() }
                    .transition(.opacity)

                AddAPIKeySheet(state: state, provider: provider, palette: palette)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.addingKeyFor)
    }

    @ViewBuilder
    private func body(palette: Palette) -> some View {
        HStack(spacing: 0) {
            HistorySidebar(state: state, palette: palette)
            mainPanes(palette: palette)
        }
    }

    @ViewBuilder
    private func mainPanes(palette: Palette) -> some View {
        if state.layout == .stacked {
            VStack(spacing: 0) {
                InputPane(state: state, palette: palette)
                Rectangle().fill(palette.border).frame(height: 1)
                OutputPane(state: state, palette: palette)
            }
        } else {
            HStack(spacing: 0) {
                InputPane(state: state, palette: palette)
                Rectangle().fill(palette.border).frame(width: 1)
                OutputPane(state: state, palette: palette)
            }
        }
    }
}

/// Invisible buttons that bind ⌘1-⌘4 to operation selection.
private struct KeyboardShortcuts: View {
    @ObservedObject var state: AppState
    var body: some View {
        ZStack {
            ForEach(WritingOp.allCases) { op in
                Button("") { state.toggleOp(op) }
                    .keyboardShortcut(KeyEquivalent(Character(op.keyEquivalent)),
                                      modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
            }
        }
    }
}

/// NSViewRepresentable that taps NSWindow to make the title bar transparent
/// and hide the title text — keeps traffic lights, drops the chrome.
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let window = v.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
