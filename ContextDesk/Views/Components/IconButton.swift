import SwiftUI

/// 26x26 square icon-only button. Hover background, active state with accent border.
struct IconButton<Content: View>: View {
    let palette: Palette
    var isActive: Bool = false
    var isDisabled: Bool = false
    var help: String? = nil
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .foregroundColor(foreground)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isActive ? palette.accent : Color.clear, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { h in hovering = h && !isDisabled }
        .help(help ?? "")
    }

    private var background: Color {
        if isActive { return palette.sidebarActive }
        if hovering { return palette.sidebarHover }
        return .clear
    }

    private var foreground: Color {
        if isDisabled { return palette.muted }
        if isActive   { return palette.accent }
        if hovering   { return palette.text }
        return palette.muted
    }
}
