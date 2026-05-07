import SwiftUI

struct StreamingPlaceholder: View {
    let palette: Palette
    @State private var animating = false

    private let widths: [CGFloat] = [0.92, 0.88, 0.96, 0.70, 0.84, 0.90, 0.60]

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(widths.enumerated()), id: \.offset) { i, w in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(palette.border)
                        .frame(width: proxy.size.width * w - 36, height: 14)
                        .opacity(animating ? 0.85 : 0.55)
                        .animation(
                            .easeInOut(duration: 1.2)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.08),
                            value: animating
                        )
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .onAppear { animating = true }
        }
    }
}
