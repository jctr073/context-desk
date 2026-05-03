import SwiftUI

/// Multi-select chip with optional icon, label, and keyboard hint.
/// Mirrors the `Chip` component in the prototype (28pt height, native vibe).
struct Chip: View {
    let label: String
    let systemImage: String?
    let kbd: String?
    let isActive: Bool
    let palette: Palette
    let action: () -> Void

    init(label: String,
         systemImage: String? = nil,
         kbd: String? = nil,
         isActive: Bool,
         palette: Palette,
         action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.kbd = kbd
        self.isActive = isActive
        self.palette = palette
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let sym = systemImage {
                    Image(systemName: sym)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                if let kbd = kbd {
                    Text(kbd)
                        .font(.system(size: 10, design: .monospaced))
                        .opacity(isActive ? 0.85 : 0.55)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(isActive
                                        ? Color.white.opacity(0.30)
                                        : palette.chipBorder,
                                        lineWidth: 1)
                        )
                        .padding(.leading, 2)
                }
            }
            .foregroundColor(isActive ? palette.chipActiveText : palette.text)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? palette.chipActive : palette.chip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isActive ? palette.chipActive : palette.chipBorder,
                            lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(ChipPressStyle())
    }
}

private struct ChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 0.5 : 0)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}
