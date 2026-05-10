import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Center column in the chat redesign — shows the conversation thread above
/// and the composer pinned at the bottom.
struct ChatPane: View {
    @ObservedObject var state: AppState
    let palette: Palette

    @State private var dragHover: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            threadHeader
            ZStack {
                ChatThreadView(state: state, palette: palette)
                if dragHover {
                    DropOverlay(palette: palette)
                        .padding(8)
                        .allowsHitTesting(false)
                }
                if state.pasteFlash {
                    PasteFlashBadge(palette: palette)
                        .padding(.top, 14)
                        .padding(.trailing, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .allowsHitTesting(false)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ChatComposer(state: state, palette: palette)
        }
        .background(palette.bg)
        .onDrop(of: [.image, .png, .jpeg, .tiff, .gif, .fileURL], isTargeted: $dragHover) { providers in
            handleDrop(providers: providers)
        }
        .animation(.easeOut(duration: 0.18), value: state.pasteFlash)
        .animation(.easeOut(duration: 0.18), value: dragHover)
    }

    // MARK: - Header

    private var threadHeader: some View {
        HStack(spacing: 10) {
            Text(state.activeConversation?.title ?? "New conversation")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(palette.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            ModePill(mode: state.mode, palette: palette) { newMode in
                state.setMode(newMode)
            }
            ActionDropdown(
                mode: state.mode,
                writingOp: state.ops.first ?? .cleanup,
                chatOp: state.chatOp,
                palette: palette,
                onSelectWritingOp: { state.toggleOp($0) },
                onSelectChatOp: { state.setChatOp($0) }
            )
            webButton
            instructionsButton
            contextButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var webButton: some View {
        let active = state.webAccessEnabled
        Button {
            state.webAccessEnabled.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                Text("Web")
                    .font(.system(size: 12, weight: .medium))
                if active {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundColor(palette.text)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.chip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(active ? palette.accent.opacity(0.6) : palette.chipBorder,
                            lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(active
              ? "Web search and fetch are enabled for this conversation"
              : "Enable web search and fetch for this conversation")
    }

    @ViewBuilder
    private var contextButton: some View {
        let active = state.hasContext
        Button {
            state.startEditingContext()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11, weight: .medium))
                Text("Context")
                    .font(.system(size: 12, weight: .medium))
                if active {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundColor(palette.text)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.chip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(active ? palette.accent.opacity(0.6) : palette.chipBorder,
                            lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(active
              ? "Reference material attached to every message (click to edit)"
              : "Add reference material to attach to every message")
    }

    @ViewBuilder
    private var instructionsButton: some View {
        let active = state.hasCustomInstructions
        Button {
            state.startEditingInstructions()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11, weight: .medium))
                Text("Instructions")
                    .font(.system(size: 12, weight: .medium))
                if active {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundColor(palette.text)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.chip)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(active ? palette.accent.opacity(0.6) : palette.chipBorder,
                            lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(active
              ? "Conversation-wide direction (click to edit)"
              : "Add a conversation-wide direction")
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var anyHandled = false
        let group = DispatchGroup()
        var collected: [AttachedImage] = []
        let lock = NSLock()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                anyHandled = true
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let u = item as? URL {
                        url = u
                    } else {
                        url = nil
                    }
                    guard let resolved = url, let image = AttachedImageLoader.load(from: resolved) else { return }
                    lock.lock()
                    collected.append(image)
                    lock.unlock()
                }
            } else if let imageType = [UTType.png, UTType.jpeg, UTType.tiff, UTType.gif, UTType.image]
                .first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                anyHandled = true
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: imageType.identifier) { data, _ in
                    defer { group.leave() }
                    guard let data, let nsImage = NSImage(data: data) else { return }
                    guard let image = AttachedImageLoader.makeAttached(from: nsImage, suggestedName: nil) else { return }
                    lock.lock()
                    collected.append(image)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            if !collected.isEmpty {
                state.attachImages(collected)
            }
        }
        return anyHandled
    }
}

// MARK: - Chat thread (scrolling messages)

struct ChatThreadView: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.activeMessages.enumerated()), id: \.offset) { idx, msg in
                        MessageView(
                            message: msg,
                            isStreamingPlaceholder: state.streamingMessageIndex == idx && msg.blocks.isEmpty,
                            palette: palette,
                            onCopy: { copyMessage(msg) },
                            onSelectAsCanvas: { state.selectPinnedReply(idx) }
                        )
                        .id("msg-\(idx)")
                    }
                    Color.clear.frame(height: 16).id("bottom")
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
            .onChange(of: state.activeMessages.count) { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: state.activeConversationID) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func copyMessage(_ msg: ChatMessage) {
        let text = msg.blocks.isEmpty
            ? msg.text
            : MockGenerator.plainText(from: msg.blocks)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

// MARK: - Single message bubble

struct MessageView: View {
    let message: ChatMessage
    let isStreamingPlaceholder: Bool
    let palette: Palette
    let onCopy: () -> Void
    let onSelectAsCanvas: () -> Void

    var body: some View {
        if message.role == .user {
            userMessage
        } else {
            assistantMessage
        }
    }

    // MARK: User

    private var userMessage: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(message.attachments) { img in
                    AttachmentRow(image: img, palette: palette)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 13))
                        .foregroundColor(palette.text)
                        .lineSpacing(13 * 0.55)
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(palette.accent.opacity(0.18))
                        )
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 14,
                                bottomLeadingRadius: 14,
                                bottomTrailingRadius: 14,
                                topTrailingRadius: 4
                            )
                        )
                        .frame(maxWidth: 540, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Assistant

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AssistantBadge(palette: palette)
                Text("ContextDesk")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(palette.text)
                Text("\u{00B7} \(timeLabel)")
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.muted)
                Spacer()
                if !isStreamingPlaceholder && !message.blocks.isEmpty {
                    Button(action: onSelectAsCanvas) {
                        Image(systemName: "square.split.2x1")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.muted)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show in output canvas")
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.muted)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                }
            }
            if isStreamingPlaceholder {
                TypingDots(palette: palette).padding(.leading, 26)
            } else if message.blocks.isEmpty {
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundColor(palette.text)
                    .lineSpacing(13 * 0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                AssistantBlocks(blocks: message.blocks, palette: palette)
            }
        }
        .padding(.vertical, 10)
    }

    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: message.createdAt)
    }
}

private struct AssistantBadge: View {
    let palette: Palette
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(
                    colors: [palette.accent, Color(hex: 0x6C5CE7)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 18, height: 18)
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

private struct AssistantBlocks: View {
    let blocks: [OutputBlock]
    let palette: Palette
    var body: some View {
        let registry = CitationRegistry.build(from: blocks)
        let cited = registry.citedURLs(in: blocks)
        VStack(alignment: .leading, spacing: 0) {
            let clusters = ToolUnitWalker.cluster(ToolUnitWalker.walk(blocks))
            ForEach(Array(clusters.enumerated()), id: \.offset) { _, cluster in
                renderCluster(cluster, registry: registry, cited: cited)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func renderCluster(
        _ cluster: ToolUnitWalker.Cluster,
        registry: CitationRegistry,
        cited: Set<String>
    ) -> some View {
        switch cluster {
        case .block(let block):
            renderBlock(block, registry: registry)
        case .toolCluster(let units):
            SourcesFirstCard(units: units, citedURLs: cited, palette: palette)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: OutputBlock, registry: CitationRegistry) -> some View {
        switch block {
        case .paragraph(let text, let citations):
            ProseTextBuilder.text(text, registry: registry, palette: palette, structuredCitations: citations)
                .font(.system(size: 13))
                .lineSpacing(13 * 0.6)
                .foregroundColor(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
        case .heading(let text):
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(palette.text)
                .padding(.top, 6)
                .padding(.bottom, 6)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\u{2022}").foregroundColor(palette.text)
                        ProseTextBuilder.text(item, registry: registry, palette: palette)
                            .font(.system(size: 13))
                            .lineSpacing(13 * 0.55)
                            .foregroundColor(palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.bottom, 10)
        case .table, .codeBlock, .toolCall, .toolResult, .unknown:
            // Reuse the rich renderer used by the output canvas for tables /
            // code / forward-compat unknown blocks. Tool blocks are paired
            // upstream — reaching here means an orphan, which OutputBody
            // also gracefully handles.
            OutputBody(blocks: [block], renderMode: .rendered, containerFormat: .markdown, palette: palette)
                .padding(.bottom, 10)
        }
    }
}

private struct AttachmentRow: View {
    let image: AttachedImage
    let palette: Palette
    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let nsImage = image.nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 14))
                        .foregroundColor(palette.muted)
                }
            }
            .frame(width: 40, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(image.fileName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                Text(image.dimensionsLabel)
                    .font(.system(size: 10.5))
                    .foregroundColor(palette.muted)
            }
        }
        .padding(6)
        .padding(.trailing, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        )
    }
}

private struct TypingDots: View {
    let palette: Palette
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(palette.muted)
                    .frame(width: 5, height: 5)
                    .opacity(phase == i ? 1.0 : 0.3)
            }
        }
        .frame(height: 16)
        .onAppear { startAnimating() }
    }

    private func startAnimating() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

// MARK: - Composer

struct ChatComposer: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            if !state.draftImages.isEmpty {
                ImageStrip(state: state, palette: palette)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
            composerCard
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .padding(.top, state.draftImages.isEmpty ? 8 : 4)
        }
        .background(palette.bg)
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            ComposerEditor(
                text: Binding(get: { state.draft }, set: { state.draft = $0 }),
                palette: palette,
                placeholder: state.mode == .writing
                    ? "Describe what you want to write\u{2026}"
                    : "Ask a follow-up, or paste something to chew on\u{2026}",
                promptHistoryEntries: state.composerPromptHistory,
                onSubmit: { state.send() },
                onPasteImages: { state.attachImages($0) }
            )
            .frame(minHeight: 36, maxHeight: 140)
            HStack(spacing: 6) {
                Button(action: pickImages) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(palette.muted)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach images")

                Button(action: { state.newConversation() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11, weight: .medium))
                        Text("New")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(palette.muted)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Start a new conversation")

                Spacer()

                HStack(spacing: 4) {
                    KbdView(text: "\u{2318}", palette: palette)
                    KbdView(text: "\u{21B5}", palette: palette)
                }

                SendButton(state: state, palette: palette)
            }
        }
        .padding(8)
        .padding(.leading, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.borderStrong, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 16, y: 4)
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .image].compactMap { $0 }
        panel.prompt = "Attach"
        panel.title = "Attach images"
        guard panel.runModal() == .OK else { return }
        let images = panel.urls.compactMap { AttachedImageLoader.load(from: $0) }
        if !images.isEmpty {
            state.attachImages(images)
        }
    }
}

private struct SendButton: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        Button(action: { state.send() }) {
            HStack(spacing: 6) {
                if state.running {
                    Spinner(color: .white, size: 11)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(state.running ? "Sending\u{2026}" : "Send")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.accent)
            )
            .opacity(state.canSend || state.running ? 1.0 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!state.canSend)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

private struct ImageStrip: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.draftImages) { image in
                    ImageThumb(
                        image: image,
                        palette: palette,
                        isLastAdded: image.id == state.lastAddedImageID,
                        onTap: { state.showLightbox(image) },
                        onRemove: { state.removeImage(image) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 80)
    }
}

private struct ImageThumb: View {
    let image: AttachedImage
    let palette: Palette
    let isLastAdded: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    @State private var hovering: Bool = false
    @State private var bounceScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                Group {
                    if let nsImage = image.nsImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundColor(palette.muted)
                    }
                }
                .frame(width: 90, height: 64)
                .clipped()
                .background(palette.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(palette.chipBorder, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(3)
            .opacity(hovering ? 1.0 : 0.0)
            .help("Remove \(image.fileName)")
        }
        .scaleEffect(bounceScale)
        .onHover { hovering = $0 }
        .help(image.fileName)
        .onAppear {
            guard isLastAdded else { return }
            bounceScale = 0.7
            withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                bounceScale = 1.0
            }
        }
    }
}

private struct DropOverlay: View {
    let palette: Palette
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.accent.opacity(0.08))
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 28, weight: .light))
                    Text("Drop images here")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(palette.accent)
            )
    }
}

private struct PasteFlashBadge: View {
    let palette: Palette
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Pasted")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(palette.accent))
        .shadow(color: palette.accent.opacity(0.35), radius: 8, y: 3)
    }
}

// MARK: - NSTextView-backed editor

struct ComposerEditor: NSViewRepresentable {
    @Binding var text: String
    let palette: Palette
    let placeholder: String
    let promptHistoryEntries: [String]
    let onSubmit: () -> Void
    let onPasteImages: ([AttachedImage]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ChatComposerTextView.scrollableTextView()
        let tv = scroll.documentView as! ChatComposerTextView
        tv.delegate = context.coordinator
        tv.onSubmit = onSubmit
        tv.onPasteImages = onPasteImages
        let coordinator = context.coordinator
        tv.onProgrammaticTextChange = { newText in
            coordinator.parent.text = newText
        }
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.font = NSFont.systemFont(ofSize: 14)
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        applyColors(tv, palette: palette)
        tv.string = text
        tv.placeholder = placeholder
        tv.setPromptHistoryEntries(promptHistoryEntries)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let tv = scroll.documentView as! ChatComposerTextView
        tv.onSubmit = onSubmit
        tv.onPasteImages = onPasteImages
        let coordinator = context.coordinator
        tv.onProgrammaticTextChange = { newText in
            coordinator.parent.text = newText
        }
        tv.placeholder = placeholder
        tv.setPromptHistoryEntries(promptHistoryEntries)
        if tv.string != text {
            tv.string = text
            tv.resetPromptHistoryNavigation()
            tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        applyColors(tv, palette: palette)
        tv.updatePlaceholderVisibility()
    }

    private func applyColors(_ tv: NSTextView, palette: Palette) {
        tv.textColor = NSColor(palette.text)
        tv.insertionPointColor = NSColor(palette.accent)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerEditor
        init(_ parent: ComposerEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            if let composer = tv as? ChatComposerTextView {
                composer.handleTextDidChange()
            }
        }
    }
}

private final class ChatComposerTextView: NSTextView {
    private enum PromptHistoryDirection {
        case older
        case newer
    }

    var onSubmit: (() -> Void)?
    var onPasteImages: (([AttachedImage]) -> Void)?
    var onProgrammaticTextChange: ((String) -> Void)?
    private var promptHistoryEntries: [String] = []
    private var promptHistoryIndex: Int?
    private var draftBeforePromptHistory: String = ""
    private var isApplyingPromptHistoryEntry = false
    var placeholder: String = "" {
        didSet { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // return
            let mods = event.modifierFlags
            // ⌘↵ or plain ↵ → submit. Shift+↵ inserts a newline.
            if mods.contains(.shift) {
                super.keyDown(with: event)
                return
            }
            onSubmit?()
            return
        }
        if event.keyCode == 126 { // up arrow
            if navigatePromptHistory(.older, event: event) { return }
        }
        if event.keyCode == 125 { // down arrow
            if navigatePromptHistory(.newer, event: event) { return }
        }
        super.keyDown(with: event)
    }

    func setPromptHistoryEntries(_ entries: [String]) {
        guard entries != promptHistoryEntries else { return }
        promptHistoryEntries = entries
        resetPromptHistoryNavigation()
    }

    func resetPromptHistoryNavigation() {
        promptHistoryIndex = nil
        draftBeforePromptHistory = ""
    }

    func handleTextDidChange() {
        if !isApplyingPromptHistoryEntry {
            resetPromptHistoryNavigation()
        }
        updatePlaceholderVisibility()
    }

    private func navigatePromptHistory(_ direction: PromptHistoryDirection, event: NSEvent) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else { return false }
        guard !promptHistoryEntries.isEmpty else { return false }

        switch direction {
        case .older:
            if let index = promptHistoryIndex {
                promptHistoryIndex = (index + 1) % promptHistoryEntries.count
            } else {
                guard canStartPromptHistoryNavigation else { return false }
                draftBeforePromptHistory = string
                promptHistoryIndex = 0
            }
        case .newer:
            guard let index = promptHistoryIndex else { return false }
            if index == 0 {
                promptHistoryIndex = nil
                replaceComposerText(draftBeforePromptHistory)
                draftBeforePromptHistory = ""
                return true
            }
            promptHistoryIndex = index - 1
        }

        guard let index = promptHistoryIndex,
              promptHistoryEntries.indices.contains(index) else { return false }
        replaceComposerText(promptHistoryEntries[index])
        return true
    }

    private var canStartPromptHistoryNavigation: Bool {
        if string.isEmpty { return true }
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        if !string.contains("\n") { return true }
        return selection.location == 0
    }

    private func replaceComposerText(_ newText: String) {
        isApplyingPromptHistoryEntry = true
        string = newText
        isApplyingPromptHistoryEntry = false
        setSelectedRange(NSRange(location: (newText as NSString).length, length: 0))
        updatePlaceholderVisibility()
        onProgrammaticTextChange?(newText)
    }

    override func paste(_ sender: Any?) {
        if consumeImages(from: NSPasteboard.general) { return }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if consumeImages(from: NSPasteboard.general) { return }
        super.pasteAsPlainText(sender)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(paste(_:)) {
            let pb = NSPasteboard.general
            if pb.canReadObject(forClasses: [NSImage.self], options: nil) { return true }
            if pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return true }
        }
        return super.validateMenuItem(menuItem)
    }

    private func consumeImages(from pasteboard: NSPasteboard) -> Bool {
        let outcome = AttachedImageLoader.load(from: pasteboard)
        guard !outcome.images.isEmpty else { return false }
        onPasteImages?(outcome.images)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.6),
        ]
        let inset = textContainerInset
        let origin = NSPoint(x: inset.width + 1, y: inset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: attrs)
    }

    func updatePlaceholderVisibility() {
        needsDisplay = true
    }
}

// Compatibility shim — older callsite SectionLabel is still used by other views
// outside the chat pane.
struct SectionLabel: View {
    let text: String
    let palette: Palette
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .heavy))
            .tracking(0.7)
            .foregroundColor(palette.muted)
            .padding(.trailing, 4)
    }
}
