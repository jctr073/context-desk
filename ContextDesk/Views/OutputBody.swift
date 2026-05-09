import SwiftUI
import Foundation
import Highlightr

struct OutputBody: View {
    let blocks: [OutputBlock]?
    let renderMode: RenderMode
    let containerFormat: OutputContainerFormat
    let palette: Palette

    var body: some View {
        if let blocks = blocks, !blocks.isEmpty {
            switch renderMode {
            case .rendered:
                let registry = CitationRegistry.build(from: blocks)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let clusters = ToolUnitWalker.cluster(ToolUnitWalker.walk(blocks))
                        ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                            renderCluster(cluster, registry: registry)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .raw:
                RawTextView(text: blocks.text(for: containerFormat), palette: palette)
            }
        } else {
            EmptyOutputState(palette: palette)
        }
    }

    @ViewBuilder
    private func renderCluster(_ cluster: ToolUnitWalker.Cluster, registry: CitationRegistry) -> some View {
        switch cluster {
        case .block(let block):
            renderBlock(block, registry: registry)
        case .toolCluster(let units):
            if units.count == 1, let unit = units.first {
                ToolCardView(
                    id: unit.call.id,
                    toolName: unit.call.name,
                    argumentsJSON: unit.call.argumentsJSON,
                    resultContent: unit.result?.content,
                    isError: unit.result?.isError ?? false,
                    palette: palette,
                    defaultExpanded: shouldDefaultExpand(unit)
                )
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.bottom, 12)
            } else {
                ToolGroupView(units: units, palette: palette)
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.bottom, 12)
            }
        }
    }

    private func shouldDefaultExpand(_ unit: ToolUnit) -> Bool {
        guard let result = unit.result, !result.isError else { return false }
        guard ToolKind.from(name: unit.call.name) == .webSearch else { return false }
        return !ToolResultParser.webSearchHits(from: result.content).isEmpty
    }

    @ViewBuilder
    private func renderBlock(_ block: OutputBlock, registry: CitationRegistry) -> some View {
        switch block {
        case .paragraph(let text):
            proseText(text, registry: registry)
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
                        proseText(item, registry: registry)
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

        case .codeBlock(let language, let code):
            CodeBlock(language: language, code: code, palette: palette)
                .padding(.bottom, 12)

        case .toolCall, .toolResult:
            // Should be paired into a ToolCardView by the unit walker.
            // Reaching here means an orphan result with no preceding call;
            // render a minimal pretty fallback so it's not invisible.
            if case .toolResult(let cid, let content, let isError) = block {
                ToolCardView(
                    id: cid,
                    toolName: "tool",
                    argumentsJSON: "",
                    resultContent: content,
                    isError: isError,
                    palette: palette
                )
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.bottom, 12)
            }

        case .unknown(let kind, _):
            UnsupportedBlock(kind: kind, palette: palette)
                .padding(.bottom, 12)
        }
    }

    private func proseText(_ s: String, registry: CitationRegistry) -> Text {
        ProseTextBuilder.text(
            s,
            registry: registry,
            palette: palette,
            slack: containerFormat == .slack
        )
    }
}

private struct CodeBlock: View {
    let language: String?
    let code: String
    let palette: Palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if let language, !language.isEmpty {
                HStack {
                    Text(language.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(palette.muted)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(palette.surfaceInset)
                Divider().background(palette.border)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                Text(highlighted)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(palette.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var highlighted: AttributedString {
        let themeName = colorScheme == .dark ? "atom-one-dark" : "xcode"
        if let ns = SyntaxHighlighter.highlight(code, language: language, themeName: themeName) {
            return AttributedString(ns)
        }
        return AttributedString(code)
    }
}

private enum SyntaxHighlighter {
    static let shared: Highlightr? = Highlightr()

    static func highlight(_ code: String, language: String?, themeName: String) -> NSAttributedString? {
        guard let h = shared else { return nil }
        h.setTheme(to: themeName)
        h.theme.setCodeFont(NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        let normalized = (language?.isEmpty ?? true) ? nil : language
        return h.highlight(code, as: normalized, fastRender: true)
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

private struct UnsupportedBlock: View {
    let kind: String
    let palette: Palette

    var body: some View {
        Text("Unsupported block: \(kind)")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(palette.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.surfaceInset)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct RawTextView: View {
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
