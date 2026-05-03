import SwiftUI

struct HistorySidebar: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Recents.all) { item in
                        RecentRow(item: item,
                                  isSelected: state.activeRecentID == item.id,
                                  palette: palette,
                                  onTap: { state.activeRecentID = item.id })
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            footer
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(palette.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.border).frame(width: 1)
        }
    }

    private var header: some View {
        HStack {
            Text("HISTORY")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(palette.muted)
            Spacer()
            Button(action: { state.newSession() }) {
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
            .help("New (\u{2318}N)")
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
            Text("\(Recents.all.count) recent")
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
}

private struct RecentRow: View {
    let item: RecentItem
    let isSelected: Bool
    let palette: Palette
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.preview)
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(item.when)
                        .font(.system(size: 10.5))
                        .foregroundColor(palette.muted)
                    ForEach(item.actions, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10))
                            .foregroundColor(palette.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(palette.border, lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 4)
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
    }

    private var background: Color {
        if isSelected { return palette.sidebarActive }
        if hovering   { return palette.sidebarHover }
        return .clear
    }
}
