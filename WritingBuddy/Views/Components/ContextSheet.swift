import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContextSheet: View {
    @ObservedObject var state: AppState
    let palette: Palette

    @State private var draft: String = ""
    @State private var images: [AttachedImage] = []
    @State private var lastAddedID: String? = nil
    @State private var dragHover: Bool = false
    @FocusState private var inputFocused: Bool

    private let placeholder = "Reference material the model should keep in mind for every message in this conversation \u{2014} a transcript, a brief, source notes, etc."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Context")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(palette.text)
                Text("Reference text and images that get sent alongside every message in this conversation. Useful for grounding the model in source material.")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            editor
                .frame(height: 180)

            imageStrip

            HStack(spacing: 8) {
                Text("Applied to every message in this conversation")
                    .font(.system(size: 12))
                    .foregroundColor(palette.muted)
                Spacer()
                cancelButton
                saveButton
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 560)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 30, y: 12)
        .onDrop(of: [.image, .png, .jpeg, .tiff, .gif, .fileURL], isTargeted: $dragHover) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            draft = state.contextText
            images = state.contextImages
            lastAddedID = nil
            inputFocused = true
        }
    }

    @ViewBuilder
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.surfaceInset)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(dragHover ? palette.accent : palette.border, lineWidth: 1)

            ContextEditor(
                text: $draft,
                palette: palette,
                onPasteImages: { addImages($0) }
            )
            .focused($inputFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if draft.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundColor(palette.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var imageStrip: some View {
        HStack(spacing: 8) {
            Button(action: pickImages) {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11, weight: .medium))
                    Text(images.isEmpty ? "Attach images" : "Add image")
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

            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(images) { image in
                            ContextImageThumb(
                                image: image,
                                palette: palette,
                                isLastAdded: image.id == lastAddedID,
                                onRemove: {
                                    images.removeAll { $0.id == image.id }
                                    if lastAddedID == image.id { lastAddedID = nil }
                                }
                            )
                        }
                    }
                }
                .frame(height: 60)
            } else {
                Text("Drop or paste images here too")
                    .font(.system(size: 11))
                    .foregroundColor(palette.muted)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var cancelButton: some View {
        Button(action: { state.cancelEditingContext() }) {
            Text("Cancel")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.text)
                .padding(.horizontal, 14)
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
        .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private var saveButton: some View {
        Button(action: submit) {
            Text("Save")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.accent)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: .command)
    }

    private func submit() {
        state.saveContext(
            text: draft.trimmingCharacters(in: .whitespacesAndNewlines),
            images: images
        )
    }

    private func addImages(_ newImages: [AttachedImage]) {
        guard !newImages.isEmpty else { return }
        images.append(contentsOf: newImages)
        lastAddedID = newImages.last?.id
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .image].compactMap { $0 }
        panel.prompt = "Attach"
        panel.title = "Attach context images"
        guard panel.runModal() == .OK else { return }
        let loaded = panel.urls.compactMap { AttachedImageLoader.load(from: $0) }
        addImages(loaded)
    }

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
                    lock.lock(); collected.append(image); lock.unlock()
                }
            } else if let imageType = [UTType.png, UTType.jpeg, UTType.tiff, UTType.gif, UTType.image]
                .first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                anyHandled = true
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: imageType.identifier) { data, _ in
                    defer { group.leave() }
                    guard let data, let nsImage = NSImage(data: data) else { return }
                    guard let image = AttachedImageLoader.makeAttached(from: nsImage, suggestedName: nil) else { return }
                    lock.lock(); collected.append(image); lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            if !collected.isEmpty { addImages(collected) }
        }
        return anyHandled
    }
}

private struct ContextImageThumb: View {
    let image: AttachedImage
    let palette: Palette
    let isLastAdded: Bool
    let onRemove: () -> Void

    @State private var hovering: Bool = false
    @State private var bounceScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let nsImage = image.nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundColor(palette.muted)
                }
            }
            .frame(width: 64, height: 48)
            .clipped()
            .background(palette.surfaceInset)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(palette.chipBorder, lineWidth: 1)
            )

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(2)
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

private struct ContextEditor: NSViewRepresentable {
    @Binding var text: String
    let palette: Palette
    let onPasteImages: ([AttachedImage]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ContextEditorTextView.scrollableTextView()
        let tv = scroll.documentView as! ContextEditorTextView
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
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.font = NSFont.systemFont(ofSize: 13)
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.borderType = .noBorder
        apply(tv)
        tv.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let tv = scroll.documentView as! ContextEditorTextView
        tv.onPasteImages = onPasteImages
        if tv.string != text {
            tv.string = text
        }
        apply(tv)
    }

    private func apply(_ tv: NSTextView) {
        tv.textColor = NSColor(palette.text)
        tv.insertionPointColor = NSColor(palette.accent)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ContextEditor
        init(_ parent: ContextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

private final class ContextEditorTextView: NSTextView {
    var onPasteImages: (([AttachedImage]) -> Void)?

    override func paste(_ sender: Any?) {
        if consumeImages(from: NSPasteboard.general) { return }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if consumeImages(from: NSPasteboard.general) { return }
        super.pasteAsPlainText(sender)
    }

    private func consumeImages(from pasteboard: NSPasteboard) -> Bool {
        let outcome = AttachedImageLoader.load(from: pasteboard)
        guard !outcome.images.isEmpty else { return false }
        onPasteImages?(outcome.images)
        return true
    }
}
