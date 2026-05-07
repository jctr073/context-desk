import SwiftUI

struct Spinner: View {
    var color: Color = .white
    var size: CGFloat = 12
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .background(
                Circle()
                    .stroke(color.opacity(0.25), lineWidth: 2)
                    .frame(width: size, height: size)
            )
            .onAppear {
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
