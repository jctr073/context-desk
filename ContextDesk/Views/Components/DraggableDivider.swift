import AppKit
import SwiftUI

/// Blocks the window-drag gesture (`isMovableByWindowBackground`) for whatever
/// view it backs. Without this, clicks on the SwiftUI hit area get swallowed
/// by AppKit's window-drag handler before our DragGesture sees them.
private struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NoDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class NoDragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

/// Hairline divider that thickens to the accent color and shows a small handle
/// on hover/drag, and adjusts a split fraction as it's dragged. Mirrors the
/// `DragDivider` component in the v3 prototype.
struct DraggableDivider: View {
    let isStacked: Bool
    let totalSize: CGFloat
    @Binding var fraction: Double
    let palette: Palette

    var minFraction: Double = 0.2
    var maxFraction: Double = 0.8
    var coordinateSpaceName: AnyHashable = "panes"

    @State private var startFraction: Double? = nil
    @State private var hover = false

    private var dragging: Bool { startFraction != nil }
    private var active: Bool { hover || dragging }

    private static let hitSize: CGFloat = 7
    private static let handleLength: CGFloat = 36
    private static let handleThickness: CGFloat = 4

    var body: some View {
        ZStack {
            // Hairline at the center of the hit area
            Rectangle()
                .fill(active ? palette.accent : palette.border)
                .frame(
                    width: isStacked ? nil : 1,
                    height: isStacked ? 1 : nil
                )
                .frame(maxWidth: isStacked ? .infinity : nil,
                       maxHeight: isStacked ? nil : .infinity)
                .animation(.easeOut(duration: 0.14), value: active)

            // Handle pill in the middle, fades in when active
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.accent)
                .frame(
                    width: isStacked ? Self.handleLength : Self.handleThickness,
                    height: isStacked ? Self.handleThickness : Self.handleLength
                )
                .shadow(color: Color.black.opacity(active ? 0.18 : 0),
                        radius: 2, y: 1)
                .opacity(active ? 0.9 : 0)
                .animation(.easeOut(duration: 0.14), value: active)
        }
        .frame(
            width: isStacked ? nil : Self.hitSize,
            height: isStacked ? Self.hitSize : nil
        )
        .frame(maxWidth: isStacked ? .infinity : nil,
               maxHeight: isStacked ? nil : .infinity)
        .background(WindowDragBlocker())
        .contentShape(Rectangle())
        .onHover { hovering in
            hover = hovering
            #if os(macOS)
            if hovering {
                (isStacked ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push()
            } else if !dragging {
                NSCursor.pop()
            }
            #endif
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
                .onChanged { value in
                    if startFraction == nil { startFraction = fraction }
                    guard totalSize > 0 else { return }
                    let delta = isStacked ? value.translation.height : value.translation.width
                    let raw = (startFraction ?? fraction) + Double(delta) / Double(totalSize)
                    fraction = max(minFraction, min(maxFraction, raw))
                }
                .onEnded { _ in
                    startFraction = nil
                    #if os(macOS)
                    if !hover { NSCursor.pop() }
                    #endif
                }
        )
    }
}
