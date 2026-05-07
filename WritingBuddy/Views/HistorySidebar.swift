import SwiftUI

/// Left rail in the chat redesign — lists conversations (whole multi-turn
/// threads) and offers New / Clear-all controls.
struct ConversationSidebar: View {
    @ObservedObject var state: AppState
    let palette: Palette
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if state.historyVisible {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if state.conversations.isEmpty {
                            emptyState
                        }
                        ForEach(state.conversations) { convo in
                            ConversationRow(
                                conversation: convo,
                                isSelected: state.activeConversationID == convo.id,
                                palette: palette,
                                onTap: { state.selectConversation(convo.id) },
                                onDelete: { state.deleteConversation(convo.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                footer
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(width: state.historyVisible ? 220 : 38)
        .frame(maxHeight: .infinity)
        .background(palette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.border).frame(width: 1)
        }
        .confirmationDialog(
            "Clear all conversations?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) { state.clearAllConversations() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all \(state.conversations.count) saved conversations. This cannot be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: { state.toggleHistoryVisible() }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.muted)
                    .frame(width: 22, height: 22)
                    .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(state.historyVisible
                  ? "Hide history (\u{2318}\u{2325}S)"
                  : "Show history (\u{2318}\u{2325}S)")
            .keyboardShortcut("s", modifiers: [.command, .option])

            if state.historyVisible {
                Text("HISTORY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(palette.muted)
                Spacer()
                Menu {
                    Button(role: .destructive) {
                        confirmingClear = true
                    } label: {
                        Label("Clear All\u{2026}", systemImage: "trash")
                    }
                    .disabled(state.conversations.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(palette.muted)
                        .frame(width: 22, height: 22)
                        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22, height: 22)
                .help("More")
                Button(action: { state.newConversation() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(palette.muted)
                        .frame(width: 22, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(palette.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("New conversation (\u{2318}N)")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 11))
            Text("\(state.conversations.count) conversation\(state.conversations.count == 1 ? "" : "s")")
                .font(.system(size: 11))
        }
        .foregroundColor(palette.muted)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No conversations yet")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(palette.text)
            Text("Hit + to start a new chat.")
                .font(.system(size: 11))
                .foregroundColor(palette.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let isSelected: Bool
    let palette: Palette
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(conversation.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(palette.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text(conversation.when)
                        .font(.system(size: 10.5))
                        .foregroundColor(palette.muted)
                }
                HStack(spacing: 6) {
                    Text(conversation.mode.label)
                        .font(.system(size: 10))
                        .foregroundColor(palette.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(palette.surfaceInset)
                        )
                    Text(conversation.preview)
                        .font(.system(size: 11))
                        .foregroundColor(palette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Text("\(conversation.messages.count)")
                        .font(.system(size: 10.5))
                        .foregroundColor(palette.muted.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var background: Color {
        if isSelected { return palette.sidebarActive }
        if hovering   { return palette.sidebarHover }
        return .clear
    }
}
