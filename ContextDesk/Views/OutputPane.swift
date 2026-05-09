import SwiftUI

/// Right column in the chat redesign — focused output canvas tracking the
/// pinned assistant reply, with Reply 1/2/… tabs at top and format chips.
struct OutputCanvas: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            header
            if state.canvasVisible {
                replyTabs
                formatToolbar
                content
                footer
            } else {
                Spacer(minLength: 0)
            }
        }
        .background(palette.surfaceInset)
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.border).frame(width: 1)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: { state.toggleCanvasVisible() }) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.muted)
                    .frame(width: 22, height: 22)
                    .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(state.canvasVisible
                  ? "Hide canvas (\u{2318}\u{2325}O)"
                  : "Show canvas (\u{2318}\u{2325}O)")
            .keyboardShortcut("o", modifiers: [.command, .option])

            if state.canvasVisible {
                Text("Output")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.text)
                Spacer()
                if state.mode == .writing {
                    IconButton(palette: palette,
                               isActive: state.diffMode,
                               isDisabled: !canShowDiff,
                               help: state.diffMode ? "Hide diff" : "Show diff against input",
                               action: { state.diffMode.toggle() }) {
                        Image(systemName: "doc.text.below.ecg")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                IconButton(palette: palette, help: "Copy", action: { state.copyPinnedReply() }) {
                    Image(systemName: state.copiedFlash ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                }
                IconButton(palette: palette,
                           isDisabled: state.running || state.pinnedReplyIdx == nil,
                           help: "Regenerate",
                           action: { state.regeneratePinnedReply() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .padding(.horizontal, state.canvasVisible ? 12 : 8)
        .padding(.vertical, 8)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    // MARK: - Reply tabs

    private var replyTabs: some View {
        let assistantIdxs = state.assistantIndices
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(assistantIdxs.enumerated()), id: \.offset) { k, idx in
                    let isActive = state.pinnedReplyIdx == idx
                    let isLatest = k == assistantIdxs.count - 1
                    Button(action: { state.selectPinnedReply(idx) }) {
                        HStack(spacing: 4) {
                            Text("Reply \(k + 1)")
                                .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                            if isLatest {
                                Circle()
                                    .fill(Color(red: 25/255, green: 195/255, blue: 50/255))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .foregroundColor(isActive ? palette.text : palette.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isActive ? palette.panel : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isActive ? palette.borderStrong : Color.clear, lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if assistantIdxs.isEmpty {
                    Text("No replies yet")
                        .font(.system(size: 11))
                        .foregroundColor(palette.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    // MARK: - Format toolbar

    private var formatToolbar: some View {
        HStack(spacing: 4) {
            FormatChip(label: "Auto",
                       icon: "sparkles",
                       isActive: state.isAutomaticFormat,
                       palette: palette) { state.setAutomaticFormat() }
            ForEach(OutputFormat.allCases) { fmt in
                FormatChip(label: fmt.label,
                           icon: fmt.sfSymbol,
                           isActive: state.fmts.contains(fmt),
                           palette: palette) { state.toggleFormat(fmt) }
            }
            Spacer()
            SegmentedToggle(
                options: OutputContainerFormat.allCases.filter { $0.isAvailable },
                label: { $0.label },
                selection: $state.containerFormat,
                palette: palette
            )
            SegmentedToggle(
                options: RenderMode.allCases,
                label: { $0.label },
                selection: $state.renderMode,
                palette: palette
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        if let msg = state.pinnedMessage, msg.role == .assistant {
            if state.streamingMessageIndex == state.pinnedReplyIdx && msg.blocks.isEmpty {
                StreamingPlaceholder(palette: palette)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.diffMode && state.mode == .writing && !msg.blocks.isEmpty {
                DiffView(
                    original: state.pinnedReplyOriginalUserText,
                    current: msg.blocks,
                    palette: palette
                )
            } else if msg.blocks.isEmpty {
                ScrollView {
                    Text(msg.text)
                        .font(.system(size: 13))
                        .foregroundColor(palette.text)
                        .lineSpacing(13 * 0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            } else {
                OutputBody(
                    blocks: msg.blocks,
                    renderMode: state.renderMode,
                    containerFormat: state.containerFormat,
                    palette: palette
                )
            }
        } else {
            EmptyOutputState(palette: palette)
        }
    }

    private var canShowDiff: Bool {
        guard let msg = state.pinnedMessage,
              msg.role == .assistant,
              !msg.blocks.isEmpty else { return false }
        return !state.pinnedReplyOriginalUserText.isEmpty
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(wordCount) word\(wordCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(palette.muted)
            Spacer()
            if let pinnedIdx = state.pinnedReplyIdx,
               let position = state.assistantIndices.firstIndex(of: pinnedIdx) {
                Text("Reply \(position + 1) of \(state.assistantIndices.count)")
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 36)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    private var wordCount: Int {
        guard let msg = state.pinnedMessage, msg.role == .assistant else { return 0 }
        let text = msg.blocks.isEmpty ? msg.text : MockGenerator.plainText(from: msg.blocks)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.split { $0.isWhitespace }.count
    }
}

private struct FormatChip: View {
    let label: String
    let icon: String?
    let isActive: Bool
    let palette: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                } else {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundColor(isActive ? palette.chipActiveText : palette.muted)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isActive ? palette.chipActive : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isActive ? palette.chipActive : palette.chipBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
