import SwiftUI

struct Titlebar: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        ZStack {
            // Background gradient
            palette.titlebarGradient

            // Centered title
            Text("ContextDesk")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(palette.text)
                .kerning(-0.1)
                .allowsHitTesting(false)

            // Left + right content
            HStack(spacing: 0) {
                TrafficLightsArea(width: 78)
                Spacer()
                ModelPicker(state: state, palette: palette)
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.borderStrong).frame(height: 0.5)
        }
    }
}
