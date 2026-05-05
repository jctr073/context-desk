import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InputPane: View {
    @ObservedObject var state: AppState
    let palette: Palette

    @State private var dragHover: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack(alignment: .topLeading) {
                if state.inputTab == .context {
                    contextHint
                }
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        if !currentImages.isEmpty {
                            ImageStrip(
                                images: currentImages,
                                lastAddedID: state.lastAddedImageID,
                                palette: palette,
                                onTap: { state.showLightbox($0) },
                                onRemove: { state.removeImage($0, from: state.inputTab) }
                            )
                            .padding(.horizontal, 18)
                            .padding(.top, 12)
                        }
                        editor
                    }
                    footer
                        .frame(maxHeight: .infinity, alignment: .bottom)

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
                .padding(.top, state.inputTab == .context ? 36 : 0)
                .onDrop(of: [.image, .png, .jpeg, .tiff, .gif, .fileURL], isTargeted: $dragHover) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .background(palette.panel)
        .animation(.easeOut(duration: 0.18), value: state.pasteFlash)
        .animation(.easeOut(duration: 0.18), value: dragHover)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            tabButton(.input)
            tabButton(.context)

            instructionsButton
                .padding(.leading, 4)

            attachButton

            resetButton

            Rectangle()
                .fill(palette.border)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)

            ModePill(mode: state.mode, palette: palette) { newMode in
                state.setMode(newMode)
            }

            Rectangle()
                .fill(palette.border)
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)

            Spacer(minLength: 8)

            Text("Action")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.muted)
                .padding(.trailing, 2)

            ActionDropdown(
                mode: state.mode,
                writingOp: state.ops.first ?? .cleanup,
                chatOp: state.chatOp,
                palette: palette,
                onSelectWritingOp: { state.toggleOp($0) },
                onSelectChatOp: { state.setChatOp($0) }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.border)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: InputTab) -> some View {
        let isActive = state.inputTab == tab
        let count = imageCount(for: tab)
        Button {
            if state.inputTab != tab {
                state.inputTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Text(tab.label.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.7)
                if count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "photo")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(count)")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundColor(isActive ? palette.accent : palette.muted)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(palette.surfaceInset)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(palette.chipBorder, lineWidth: 1)
                    )
                }
            }
            .foregroundColor(isActive ? palette.text : palette.muted)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? palette.surfaceInset : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isActive ? palette.chipBorder : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tab == .context
              ? "Add reference material that informs the rewrite"
              : "The text to be rewritten")
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
              ? "Custom direction applied to every run (click to edit)"
              : "Add a custom direction for the rewrite")
    }

    @ViewBuilder
    private var resetButton: some View {
        Button(action: { state.newSession() }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .medium))
                Text("Reset")
                    .font(.system(size: 12, weight: .medium))
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
                    .stroke(palette.chipBorder, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Clear input, context, instructions, images, and output")
    }

    @ViewBuilder
    private var attachButton: some View {
        let count = state.currentTabImageCount
        let active = count > 0
        Button(action: pickImages) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .font(.system(size: 11, weight: .medium))
                Text("Attach")
                    .font(.system(size: 12, weight: .medium))
                if active {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(
                            Capsule().fill(palette.accent)
                        )
                }
            }
            .foregroundColor(active ? palette.accent : palette.text)
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
        .help("Attach image(s) to the \(state.inputTab.label.lowercased()) — paste or drag also work")
    }

    // MARK: - Editor

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            EditorView(
                text: editorBinding,
                palette: palette,
                onPasteImages: { images in
                    state.attachImages(images, to: state.inputTab)
                }
            )
            .padding(.horizontal, 18)
            .padding(.top, currentImages.isEmpty ? 14 : 8)
            .padding(.bottom, 50)

            if currentText.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundColor(palette.muted)
                    .padding(.horizontal, 24)
                    .padding(.top, currentImages.isEmpty ? 18 : 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorBinding: Binding<String> {
        switch state.inputTab {
        case .input:   return $state.input
        case .context: return $state.context
        }
    }

    private var currentText: String {
        state.inputTab == .input ? state.input : state.context
    }

    private var currentImages: [AttachedImage] {
        state.inputTab == .input ? state.inputImages : state.contextImages
    }

    private func imageCount(for tab: InputTab) -> Int {
        tab == .input ? state.inputImages.count : state.contextImages.count
    }

    private var placeholder: String {
        switch state.inputTab {
        case .input:
            return "Paste or type what you want to improve\u{2026}"
        case .context:
            return "e.g. \"Audience: technical execs at our top 25 enterprise customers. Voice: direct, no marketing fluff. Reference our Q3 launch which slipped 2 weeks due to billing migration\u{2026}\""
        }
    }

    private var contextHint: some View {
        Text("Reference material to inform the rewrite \u{2014} not text to be rewritten. Paste briefs, style guides, prior emails, transcripts, or audience notes.")
            .font(.system(size: 11))
            .foregroundColor(palette.muted)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surfaceInset)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.border).frame(height: 1)
            }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(state.wordCount) word\(state.wordCount == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(palette.muted)
            if state.currentTabImageCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(state.currentTabImageCount) image\(state.currentTabImageCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundColor(palette.accent)
            }
            Spacer()
            HStack(spacing: 4) {
                KbdView(text: "\u{2318}", palette: palette)
                KbdView(text: "\u{21B5}", palette: palette)
                Text("to run")
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
            }
            SubmitButton(state: state, palette: palette)
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

    // MARK: - Image attach helpers

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .image].compactMap { $0 }
        panel.prompt = "Attach"
        panel.title = "Attach images to \(state.inputTab.label.lowercased())"
        guard panel.runModal() == .OK else { return }
        let images = panel.urls.compactMap { AttachedImageLoader.load(from: $0) }
        if !images.isEmpty {
            state.attachImages(images, to: state.inputTab)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let targetTab = state.inputTab
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
                state.attachImages(collected, to: targetTab)
            }
        }

        return anyHandled
    }
}

private struct SubmitButton: View {
    @ObservedObject var state: AppState
    let palette: Palette

    var body: some View {
        Button(action: { state.run() }) {
            HStack(spacing: 6) {
                if state.running {
                    Spinner(color: .white, size: 11)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(state.running ? "Submitting\u{2026}" : "Submit")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.accent)
            )
            .opacity(state.canRun || state.running ? 1.0 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!state.canRun)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

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

// MARK: - Image strip

private struct ImageStrip: View {
    let images: [AttachedImage]
    let lastAddedID: String?
    let palette: Palette
    let onTap: (AttachedImage) -> Void
    let onRemove: (AttachedImage) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { image in
                    ImageThumb(
                        image: image,
                        palette: palette,
                        isLastAdded: image.id == lastAddedID,
                        onTap: { onTap(image) },
                        onRemove: { onRemove(image) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 96)
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
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let nsImage = image.nsImage {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 22, weight: .light))
                                .foregroundColor(palette.muted)
                        }
                    }
                    .frame(width: 110, height: 80)
                    .clipped()

                    Text(image.dimensionsLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.black.opacity(0.55))
                        )
                        .padding(5)
                }
                .frame(width: 110, height: 80)
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
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(Color.black.opacity(0.65))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(4)
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

// MARK: - Drop overlay

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

// MARK: - Paste flash badge

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
        .background(
            Capsule().fill(palette.accent)
        )
        .shadow(color: palette.accent.opacity(0.35), radius: 8, y: 3)
    }
}

// MARK: - Editor (NSTextView wrapper)

/// Wraps NSTextView for a transparent background TextEditor that respects palette colors.
private struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let palette: Palette
    let onPasteImages: ([AttachedImage]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ImagePasteTextView.scrollableTextView()
        let tv = scroll.documentView as! ImagePasteTextView
        tv.delegate = context.coordinator
        tv.onPasteImages = onPasteImages
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 0, height: 0)
        tv.font = NSFont.systemFont(ofSize: 14)
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        applyColors(tv)
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let tv = scroll.documentView as! ImagePasteTextView
        tv.onPasteImages = onPasteImages
        if tv.string != text {
            tv.string = text
        }
        applyColors(tv)
    }

    private func applyColors(_ tv: NSTextView) {
        tv.textColor = NSColor(palette.text)
        tv.insertionPointColor = NSColor(palette.accent)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        init(_ parent: EditorView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

/// NSTextView subclass that intercepts image data on paste before falling back
/// to default text behavior. A plain (non-rich) NSTextView won't list image
/// types in `readablePasteboardTypes`, so overriding `paste(_:)` directly is
/// the only way to catch screenshots / file copies from the clipboard.
private final class ImagePasteTextView: NSTextView {
    var onPasteImages: (([AttachedImage]) -> Void)?

    override func paste(_ sender: Any?) {
        if consumeImages(from: NSPasteboard.general) { return }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if consumeImages(from: NSPasteboard.general) { return }
        super.pasteAsPlainText(sender)
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Make sure the Paste menu item stays enabled when only images are on
        // the pasteboard — otherwise the system disables it on a plain text
        // view because it sees no readable text.
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
}
