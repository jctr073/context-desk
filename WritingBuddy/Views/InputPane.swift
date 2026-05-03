import SwiftUI

struct InputPane: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack(alignment: .bottom) {
                editor
                footer
            }
        }
        .background(palette.panel)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            SectionLabel(text: "Input", palette: palette)
            Spacer()
            ForEach(WritingOp.allCases) { op in
                Chip(label: op.label,
                     systemImage: op.sfSymbol,
                     kbd: op.kbdHint,
                     isActive: state.ops.contains(op),
                     palette: palette) {
                    state.toggleOp(op)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.border)
                .frame(height: 1)
        }
    }

    // MARK: - Editor

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            // TextEditor with transparent background
            EditorView(text: $state.input, palette: palette)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 50) // leave space for footer

            if state.input.isEmpty {
                Text("Paste or type what you want to improve\u{2026}")
                    .font(.system(size: 14))
                    .foregroundColor(palette.muted)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(state.wordCount) word\(state.wordCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(palette.muted)
            Spacer()
            HStack(spacing: 4) {
                KbdView(text: "\u{2318}", palette: palette)
                KbdView(text: "\u{21B5}", palette: palette)
                Text("to run")
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
            }
            ImproveButton(state: state, palette: palette)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(palette.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }
}

private struct ImproveButton: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        Button(action: { state.run() }) {
            HStack(spacing: 6) {
                if state.running {
                    Spinner(color: .white, size: 11)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(state.running ? "Improving\u{2026}" : "Improve")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.accent)
            )
            .opacity(state.canRun || state.running ? 1.0 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!state.canRun)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

struct SectionLabel: View {
    let text: String
    let palette: Palette
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .heavy))
            .tracking(0.7)
            .foregroundColor(palette.muted)
            .padding(.trailing, 4)
    }
}

/// Wraps NSTextView for a transparent background TextEditor that respects palette colors.
private struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let palette: Palette

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 0, height: 0)
        tv.font = NSFont.systemFont(ofSize: 14)
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        applyColors(tv)
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        if tv.string != text {
            tv.string = text
        }
        applyColors(tv)
    }

    private func applyColors(_ tv: NSTextView) {
        tv.textColor = NSColor(palette.text)
        tv.insertionPointColor = NSColor(palette.accent)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: EditorView
        init(_ parent: EditorView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
