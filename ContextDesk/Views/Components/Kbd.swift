import SwiftUI

/// Monospaced keyboard-key visual. Mirrors the `<Kbd>` helper in the prototype.
struct KbdView: View {
    let text: String
    let palette: Palette

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(palette.muted)
            .frame(minWidth: 14)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(palette.chip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(palette.chipBorder, lineWidth: 1)
            )
    }
}
