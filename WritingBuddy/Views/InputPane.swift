import SwiftUI

struct InputPane: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack(alignment: .topLeading) {
                if state.inputTab == .context {
                    contextHint
                }
                ZStack(alignment: .bottom) {
                    editor
                    footer
                }
                .padding(.top, state.inputTab == .context ? 36 : 0)
            }
        }
        .background(palette.panel)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            tabButton(.input)
            tabButton(.context)

            instructionsButton
                .padding(.leading, 4)

            Rectangle()
                .fill(palette.border)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)

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

    @ViewBuilder
    private func tabButton(_ tab: InputTab) -> some View {
        let isActive = state.inputTab == tab
        Button {
            if state.inputTab != tab {
                state.inputTab = tab
            }
        } label: {
            Text(tab.label.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.7)
                .foregroundColor(isActive ? palette.text : palette.muted)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? palette.surfaceInset : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isActive ? palette.chipBorder : Color.clear, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tab == .context
              ? "Add reference material that informs the rewrite"
              : "The text to be rewritten")
    }

    @ViewBuilder
    private var instructionsButton: some View {
        let active = state.hasCustomInstructions
        Button {
            state.startEditingInstructions()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11, weight: .medium))
                Text("Instructions")
                    .font(.system(size: 12, weight: .medium))
                if active {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundColor(palette.text)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.chip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(active ? palette.accent.opacity(0.6) : palette.chipBorder,
                            lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(active
              ? "Custom direction applied to every run (click to edit)"
              : "Add a custom direction for the rewrite")
    }

    // MARK: - Editor

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            EditorView(text: editorBinding, palette: palette)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 50)

            if currentText.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundColor(palette.muted)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorBinding: Binding<String> {
        switch state.inputTab {
        case .input:   return $state.input
        case .context: return $state.context
        }
    }

    private var currentText: String {
        state.inputTab == .input ? state.input : state.context
    }

    private var placeholder: String {
        switch state.inputTab {
        case .input:
            return "Paste or type what you want to improve\u{2026}"
        case .context:
            return "e.g. \"Audience: technical execs at our top 25 enterprise customers. Voice: direct, no marketing fluff. Reference our Q3 launch which slipped 2 weeks due to billing migration\u{2026}\""
        }
    }

    private var contextHint: some View {
        Text("Reference material to inform the rewrite \u{2014} not text to be rewritten. Paste briefs, style guides, prior emails, transcripts, or audience notes.")
            .font(.system(size: 11))
            .foregroundColor(palette.muted)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surfaceInset)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.border).frame(height: 1)
            }
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
        context.coordinator.parent = self
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
        var parent: EditorView
        init(_ parent: EditorView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
