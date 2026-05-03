import SwiftUI
import AppKit

struct AddAPIKeySheet: View {
    @ObservedObject var state: AppState
    let provider: AIProvider
    let palette: Palette

    @State private var key: String = ""
    @State private var revealed: Bool = false
    @FocusState private var inputFocused: Bool

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add \(provider.keyLabel) API key")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.text)
                Text("Paste your \(provider.keyLabel) API key. WritingBuddy stores it in your Mac Keychain and only sends it to \(provider.apiHost).")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("API KEY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(palette.muted)
                    .kerning(0.4)

                inputRow
            }

            HStack(spacing: 0) {
                Text("Don't have one? ")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                Button {
                    NSWorkspace.shared.open(provider.getKeyURL)
                } label: {
                    Text("Get a key from \(provider.keyLabel)")
                        .font(.system(size: 12))
                        .foregroundColor(palette.accent)
                }
                .buttonStyle(.plain)
                Text(" \u{2014} opens in your browser.")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
            }

            HStack(spacing: 8) {
                Spacer()
                cancelButton
                saveButton
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 30, y: 12)
        .onAppear { inputFocused = true }
        .onSubmit { submit() }
    }

    @ViewBuilder
    private var inputRow: some View {
        HStack(spacing: 6) {
            Group {
                if revealed {
                    TextField(provider.keyPlaceholder, text: $key)
                } else {
                    SecureField(provider.keyPlaceholder, text: $key)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(palette.text)
            .focused($inputFocused)
            .onSubmit { submit() }

            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.system(size: 13))
                    .foregroundColor(palette.muted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(revealed ? "Hide key" : "Show key")
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var cancelButton: some View {
        Button(action: { state.cancelAddingKey() }) {
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
            Text("Save to Keychain")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.accent)
                )
                .opacity(trimmedKey.isEmpty ? 0.5 : 1.0)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(trimmedKey.isEmpty)
        .keyboardShortcut(.defaultAction)
    }

    private func submit() {
        guard !trimmedKey.isEmpty else { return }
        state.saveAPIKey(key)
    }
}
