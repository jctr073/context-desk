import SwiftUI

struct OutputBody: View {
    let blocks: [OutputBlock]?
    let renderMode: RenderMode
    let palette: Palette

    var body: some View {
        if let blocks = blocks, !blocks.isEmpty {
            switch renderMode {
            case .rendered:
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            renderBlock(block)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .raw:
                RawMarkdownView(text: blocks.markdown, palette: palette)
            }
        } else {
            EmptyOutputState(palette: palette)
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: OutputBlock) -> some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(14 * 0.55) // approximates line-height 1.55
                .foregroundColor(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

        case .heading(let text):
            Text(text.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(palette.muted)
                .padding(.top, 14)
                .padding(.bottom, 8)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\u{2022}")
                            .foregroundColor(palette.text)
                        Text(item)
                            .font(.system(size: 14))
                            .lineSpacing(14 * 0.55)
                            .foregroundColor(palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.bottom, 12)

        case .table(let head, let rows):
            TableBlock(head: head, rows: rows, palette: palette)
                .padding(.vertical, 4)
                .padding(.bottom, 12)
        }
    }
}

private struct TableBlock: View {
    let head: [String]
    let rows: [[String]]
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                ForEach(Array(head.enumerated()), id: \.offset) { _, h in
                    Text(h.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(palette.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(palette.surfaceInset)
            Divider().background(palette.border)

            // Rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: 12.5))
                            .foregroundColor(palette.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if rIdx != rows.count - 1 {
                    Divider().background(palette.border)
                }
            }
        }
        .background(palette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RawMarkdownView: View {
    let text: String
    let palette: Palette

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(palette.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
        }
    }
}

struct EmptyOutputState: View {
    let palette: Palette

    var body: some View {
        VStack(spacing: 8) {
            Text("Output will appear here")
                .font(.system(size: 14))
                .foregroundColor(palette.text.opacity(0.7))
            HStack(spacing: 6) {
                Text("Pick what you want done, then press")
                KbdView(text: "\u{2318}\u{21B5}", palette: palette)
            }
            .font(.system(size: 13))
            .foregroundColor(palette.muted)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
