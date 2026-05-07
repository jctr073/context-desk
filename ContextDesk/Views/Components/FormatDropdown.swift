import SwiftUI

/// Output container format dropdown — Markdown / Slack (live), Plain text / HTML
/// (Soon). Mirrors the `FormatDropdown` in the v3 prototype.
struct FormatDropdown: View {
    @Binding var selection: OutputContainerFormat
    let palette: Palette

    var body: some View {
        Menu {
            Section("Output format") {
                ForEach(OutputContainerFormat.allCases) { fmt in
                    Button {
                        guard fmt.isAvailable else { return }
                        selection = fmt
                    } label: {
                        Label {
                            HStack {
                                Text(fmt.label)
                                Spacer()
                                if !fmt.isAvailable {
                                    Text("Soon")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: fmt.sfSymbol)
                        }
                    }
                    .disabled(!fmt.isAvailable)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selection.sfSymbol)
                    .font(.system(size: 11, weight: .medium))
                Text(selection.label)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.5)
                    .padding(.leading, 1)
            }
            .foregroundColor(palette.text)
            .padding(.horizontal, 10)
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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose the output container format")
    }
}
