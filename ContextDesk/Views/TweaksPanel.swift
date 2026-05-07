import SwiftUI

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
