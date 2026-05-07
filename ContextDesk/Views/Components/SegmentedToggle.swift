import SwiftUI

/// Two-option pill-style segmented control. Mirrors the "Rendered / Raw"
/// toggle in the prototype — a single rounded outline wraps both segments,
/// with the active segment getting a filled background.
struct SegmentedToggle<Value: Hashable>: View {
    let options: [Value]
    let label: (Value) -> String
    @Binding var selection: Value
    let palette: Palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                segment(for: option)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(palette.chipBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func segment(for option: Value) -> some View {
        let isActive = option == selection
        Button {
            selection = option
        } label: {
            Text(label(option))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? palette.text : palette.muted)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isActive ? palette.panel : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isActive ? palette.chipBorder : Color.clear, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
