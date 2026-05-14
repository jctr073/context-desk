import SwiftUI
import AppKit

/// Floating panel pinned to the bottom-right of the window. The chat redesign
/// commits to a single layout (Variant A: history rail + thread + canvas),
/// so the panel keeps a theme switch and a render-mode hint.
struct TweaksPanel: View {
    @ObservedObject var state: AppState
    let palette: Palette
    @State private var collapsed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !collapsed {
                Divider().background(palette.border)
                content
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
        .frame(width: 220)
    }

    private var header: some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() } }) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.muted)
                Text("Tweaks")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(palette.text)
                Spacer()
                Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(palette.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(label: "Theme") {
                segmentedTheme
            }
            section(label: "Default Mode") {
                segmentedDefaultMode
            }
            section(label: "Global Import Selection") {
                ShortcutRecorder(state: state, palette: palette)
            }
        }
        .padding(12)
    }

    private func section<Content: View>(label: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(palette.muted)
            content()
        }
    }

    private var segmentedTheme: some View {
        HStack(spacing: 6) {
            ForEach(AppTheme.allCases) { t in
                segChip(label: t.label, isActive: state.theme == t) {
                    state.theme = t
                }
            }
        }
    }

    private var segmentedDefaultMode: some View {
        HStack(spacing: 6) {
            ForEach(WritingMode.allCases) { m in
                segChip(label: m.label, isActive: state.defaultMode == m) {
                    state.defaultMode = m
                }
            }
        }
    }

    private func segChip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? palette.chipActiveText : palette.text)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? palette.chipActive : palette.chip)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isActive ? palette.chipActive : palette.chipBorder,
                                lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Click-to-record chip for the global "import selection" hotkey. While
/// recording, an NSEvent local monitor swallows key presses so they don't
/// reach the rest of the app.
private struct ShortcutRecorder: View {
    @ObservedObject var state: AppState
    let palette: Palette

    @State private var recording = false
    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                chip
                if !recording, state.importSelectionShortcut != .defaultImportSelection {
                    Button(action: resetToDefault) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(palette.muted)
                            .frame(width: 18, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(palette.chip)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(palette.chipBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default (\(KeyboardShortcut.defaultImportSelection.symbolDescription))")
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundColor(palette.muted)
            } else if recording {
                Text("Press a combo · Esc to cancel")
                    .font(.system(size: 10))
                    .foregroundColor(palette.muted)
            }
        }
        .onDisappear { stopMonitoring() }
    }

    private var chip: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 6) {
                Text(recording ? "Recording…" : state.importSelectionShortcut.symbolDescription)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(recording ? palette.chipActiveText : palette.text)
                Spacer(minLength: 0)
                Image(systemName: recording ? "xmark.circle.fill" : "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(recording ? palette.chipActiveText : palette.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(recording ? palette.chipActive : palette.chip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(recording ? palette.chipActive : palette.chipBorder,
                            lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func toggleRecording() {
        if recording {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    private func startMonitoring() {
        errorMessage = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyDown(event)
            return nil
        }
    }

    private func stopMonitoring() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Esc cancels.
        if event.keyCode == 0x35 {
            stopMonitoring()
            return
        }
        guard let shortcut = KeyboardShortcut(event: event) else { return }
        guard shortcut.hasModifier else {
            errorMessage = "Needs ⌃, ⌥, ⇧, or ⌘"
            return
        }
        state.importSelectionShortcut = shortcut
        stopMonitoring()
    }

    private func resetToDefault() {
        state.importSelectionShortcut = .defaultImportSelection
    }
}
