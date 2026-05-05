import SwiftUI

/// Animated two-state pill for switching between Writing and Chat & Tasks modes.
/// Mirrors the `ModePill` component in the v3 prototype.
struct ModePill: View {
    let mode: WritingMode
    let palette: Palette
    let onChange: (WritingMode) -> Void

    private static let segmentWidth: CGFloat = 110

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(palette.text.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(palette.chipBorder, lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(palette.chipBorder, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 1, y: 1)
                .frame(width: Self.segmentWidth - 4, height: 22)
                .padding(2)
                .offset(x: mode == .writing ? 0 : Self.segmentWidth)
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: mode)

            HStack(spacing: 0) {
                segmentButton(.writing)
                segmentButton(.chat)
            }
        }
        .frame(width: Self.segmentWidth * 2, height: 26)
        .fixedSize()
    }

    @ViewBuilder
    private func segmentButton(_ target: WritingMode) -> some View {
        let active = mode == target
        Button { onChange(target) } label: {
            HStack(spacing: 5) {
                Image(systemName: target.sfSymbol)
                    .font(.system(size: 11, weight: active ? .semibold : .medium))
                Text(target.label)
                    .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(active ? palette.accent : palette.muted)
            .frame(width: Self.segmentWidth, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
