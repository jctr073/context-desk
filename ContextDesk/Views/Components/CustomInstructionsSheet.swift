import SwiftUI
import AppKit

struct CustomInstructionsSheet: View {
    @ObservedObject var state: AppState
    let palette: Palette

    @State private var draft: String = ""
    @FocusState private var inputFocused: Bool

    private let placeholder = "e.g. \"Rewrite my final summary for this interview\" or \"Reframe as a casual Slack message to my team.\""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom instructions")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.text)
                Text("Your own direction for the rewrite \u{2014} like Rephrase, Expand, Shorten, or Clean up, but in your own words. Applied alongside whichever op is selected.")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            editor
                .frame(height: 180)

            HStack(spacing: 8) {
                Text("Applies to every run in this session")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                Spacer()
                cancelButton
                saveButton
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 30, y: 12)
        .onAppear {
            draft = state.customInstructions
            inputFocused = true
        }
    }

    @ViewBuilder
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.surfaceInset)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.border, lineWidth: 1)

            InstructionsEditor(text: $draft, palette: palette)
                .focused($inputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            if draft.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundColor(palette.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var cancelButton: some View {
        Button(action: { state.cancelEditingInstructions() }) {
            Text("Cancel")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.text)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.chip)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(palette.chipBorder, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private var saveButton: some View {
        Button(action: submit) {
            Text("Save")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.accent)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
    }

    private func submit() {
        state.saveCustomInstructions(draft.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct InstructionsEditor: NSViewRepresentable {
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
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.font = NSFont.systemFont(ofSize: 13)
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        apply(tv)
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let tv = scroll.documentView as! NSTextView
        if tv.string != text {
            tv.string = text
        }
        apply(tv)
    }

    private func apply(_ tv: NSTextView) {
        tv.textColor = NSColor(palette.text)
        tv.insertionPointColor = NSColor(palette.accent)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InstructionsEditor
        init(_ parent: InstructionsEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}
