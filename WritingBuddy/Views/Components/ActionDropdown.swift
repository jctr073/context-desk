import SwiftUI

/// Single primary-button dropdown that replaces the inline action chips.
/// Shows the current operation's label with an accent fill, opens a menu of
/// operations for the active mode (with keyboard shortcut hints) on click.
/// Mirrors the `ActionDropdown` component in the v3 prototype.
struct ActionDropdown: View {
    let mode: WritingMode
    let writingOp: WritingOp
    let chatOp: ChatOp
    let palette: Palette
    let onSelectWritingOp: (WritingOp) -> Void
    let onSelectChatOp: (ChatOp) -> Void

    private var current: Operation {
        switch mode {
        case .writing: return writingOp
        case .chat:    return chatOp
        }
    }

    var body: some View {
        Menu {
            Section(mode == .writing ? "Writing actions" : "Chat & task actions") {
                switch mode {
                case .writing:
                    ForEach(WritingOp.allCases) { op in
                        Button {
                            onSelectWritingOp(op)
                        } label: {
                            menuRow(label: op.label,
                                    sfSymbol: op.sfSymbol,
                                    kbd: op.kbdHint,
                                    isActive: op == writingOp)
                        }
                    }
                case .chat:
                    ForEach(ChatOp.allCases) { op in
                        Button {
                            onSelectChatOp(op)
                        } label: {
                            menuRow(label: op.label,
                                    sfSymbol: op.sfSymbol,
                                    kbd: op.kbdHint,
                                    isActive: op == chatOp)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: current.sfSymbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(current.label)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.75)
                    .padding(.leading, 1)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.accent)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(mode == .writing ? "Choose a writing action" : "Choose a chat action")
    }

    @ViewBuilder
    private func menuRow(label: String, sfSymbol: String, kbd: String, isActive: Bool) -> some View {
        // SwiftUI Menu cannot fully style its rows on macOS — use a plain
        // Label which the system renders with native menu styling.
        Label {
            HStack {
                Text(label)
                Spacer()
                Text(kbd)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        } icon: {
            Image(systemName: sfSymbol)
        }
    }
}
