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
            .background(KeyboardShortcuts(state: state))

            TweaksPanel(state: state, palette: palette)
                .padding(.trailing, 16)
                .padding(.bottom, 16)

            apiKeyOverlay(palette: palette)
            instructionsOverlay(palette: palette)
            contextOverlay(palette: palette)
            lightboxOverlay(palette: palette)
        }
        .frame(minWidth: 900, minHeight: 580)
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

                APIKeySetupSheet(state: state, provider: provider, palette: palette)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.addingKeyFor)
    }

    @ViewBuilder
    private func instructionsOverlay(palette: Palette) -> some View {
        ZStack {
            if state.editingInstructions {
                palette.modalScrim
                    .ignoresSafeArea()
                    .onTapGesture { state.cancelEditingInstructions() }
                    .transition(.opacity)

                CustomInstructionsSheet(state: state, palette: palette)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.editingInstructions)
    }

    @ViewBuilder
    private func contextOverlay(palette: Palette) -> some View {
        ZStack {
            if state.editingContext {
                palette.modalScrim
                    .ignoresSafeArea()
                    .onTapGesture { state.cancelEditingContext() }
                    .transition(.opacity)

                ContextSheet(state: state, palette: palette)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.editingContext)
    }

    @ViewBuilder
    private func lightboxOverlay(palette: Palette) -> some View {
        ZStack {
            if let image = state.lightboxImage {
                palette.modalScrim
                    .ignoresSafeArea()
                    .onTapGesture { state.dismissLightbox() }
                    .transition(.opacity)

                ImageLightbox(state: state, image: image, palette: palette)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.lightboxImage)
    }

    @ViewBuilder
    private func body(palette: Palette) -> some View {
        HStack(spacing: 0) {
            ConversationSidebar(state: state, palette: palette)
            GeometryReader { geo in
                let total = geo.size.width
                HStack(spacing: 0) {
                    if state.canvasVisible {
                        ChatPane(state: state, palette: palette)
                            .frame(width: max(0, total * state.canvasSplit))
                        DraggableDivider(
                            isStacked: false,
                            totalSize: total,
                            fraction: $state.canvasSplit,
                            palette: palette,
                            minFraction: 0.45,
                            maxFraction: 0.85
                        )
                        OutputCanvas(state: state, palette: palette)
                            .frame(maxWidth: .infinity)
                    } else {
                        ChatPane(state: state, palette: palette)
                            .frame(maxWidth: .infinity)
                        OutputCanvas(state: state, palette: palette)
                            .frame(width: 38)
                    }
                }
                .coordinateSpace(name: "panes")
            }
        }
        .animation(.easeInOut(duration: 0.22), value: state.historyVisible)
        .animation(.easeInOut(duration: 0.22), value: state.canvasVisible)
    }
}

/// Hidden buttons that bind ⌘1-⌘5 to the active mode's operations.
private struct KeyboardShortcuts: View {
    @ObservedObject var state: AppState
    var body: some View {
        ZStack {
            switch state.mode {
            case .writing:
                ForEach(WritingOp.allCases) { op in
                    Button("") { state.toggleOp(op) }
                        .keyboardShortcut(KeyEquivalent(Character(op.keyEquivalent)),
                                          modifiers: .command)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                }
            case .chat:
                ForEach(ChatOp.allCases) { op in
                    Button("") { state.setChatOp(op) }
                        .keyboardShortcut(KeyEquivalent(Character(op.keyEquivalent)),
                                          modifiers: .command)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                }
            }
        }
    }
}

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
