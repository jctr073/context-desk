import SwiftUI
import AppKit

struct APIKeySetupSheet: View {
    @ObservedObject var state: AppState
    let provider: AIProvider
    let palette: Palette

    private var profileList: String {
        APIKeyStore.profileFileLabels.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(provider.keyLabel) API key not found")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.text)
                Text("WritingBuddy looks for \(provider.shellAPIKeyLabel) in your shell profiles and inherited environment, then sends it only to \(provider.apiHost).")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ADD TO PROFILE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(palette.muted)
                    .kerning(0.4)

                Text(provider.shellAPIKeyExample)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(palette.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(palette.surfaceInset)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(palette.border, lineWidth: 1)
                    )
            }

            Text("Profiles checked: \(profileList). Try again after updating your profile.")
                .font(.system(size: 12))
                .foregroundColor(palette.muted)
                .fixedSize(horizontal: false, vertical: true)

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
                copyButton
                doneButton
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 30, y: 12)
    }

    @ViewBuilder
    private var copyButton: some View {
        Button(action: copyExample) {
            Text("Copy Export")
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
    }

    @ViewBuilder
    private var doneButton: some View {
        Button(action: { state.cancelAddingKey() }) {
            Text("Done")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.accent)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }

    private func copyExample() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(provider.shellAPIKeyExample, forType: .string)
    }
}
