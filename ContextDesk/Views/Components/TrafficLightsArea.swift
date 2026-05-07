import SwiftUI

/// Reserves the left-side space the OS uses for traffic-light buttons in
/// hidden-titlebar windows. The actual buttons are drawn by AppKit; this just
/// keeps our content from overlapping them.
struct TrafficLightsArea: View {
    var width: CGFloat = 78
    var body: some View {
        Color.clear.frame(width: width, height: 16)
    }
}
