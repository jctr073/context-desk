import SwiftUI

struct OutputPane: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            content
            footer
        }
        .background(palette.panel)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            SectionLabel(text: "Output", palette: palette)
            Spacer()

            Chip(label: "Automatic",
                 systemImage: "sparkles",
                 kbd: nil,
                 isActive: state.isAutomaticFormat,
                 palette: palette) {
                state.setAutomaticFormat()
            }

            ForEach(OutputFormat.allCases) { fmt in
                Chip(label: fmt.label,
                     systemImage: fmt.sfSymbol,
                     kbd: nil,
                     isActive: state.fmts.contains(fmt),
                     palette: palette) {
                    state.toggleFormat(fmt)
                }
            }

            Rectangle()
                .fill(palette.border)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 2)

            FormatDropdown(selection: $state.containerFormat, palette: palette)

            SegmentedToggle(
                options: RenderMode.allCases,
                label: { $0.label },
                selection: $state.renderMode,
                palette: palette
            )

            Rectangle()
                .fill(palette.border)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 2)

            IconButton(palette: palette,
                       isActive: state.diffMode,
                       help: "Show diff",
                       action: { state.diffMode.toggle() }) {
                Image(systemName: "doc.text.below.ecg")
                    .font(.system(size: 12, weight: .medium))
            }

            IconButton(palette: palette,
                       isDisabled: state.running,
                       help: "Regenerate",
                       action: { state.run() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }

            IconButton(palette: palette,
                       help: state.copiedFlash ? "Copied" : "Copy",
                       action: { state.copyOutput() }) {
                Image(systemName: state.copiedFlash ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ZStack {
            palette.surfaceInset
            if state.running {
                StreamingPlaceholder(palette: palette)
            } else if state.diffMode {
                DiffView(original: state.input, current: state.output, palette: palette)
            } else {
                OutputBody(blocks: state.output,
                           renderMode: state.renderMode,
                           palette: palette)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(state.outputWordCount) word\(state.outputWordCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(palette.muted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(palette.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }
}
