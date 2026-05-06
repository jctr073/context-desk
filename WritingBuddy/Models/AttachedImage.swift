import AppKit
import Foundation
import UniformTypeIdentifiers

struct AttachedImage: Identifiable, Hashable, Codable {
    let id: String
    let fileName: String
    let mimeType: String
    /// Base64-encoded raw image bytes (no `data:` prefix).
    let base64: String
    let width: Int
    let height: Int
    let byteSize: Int

    init(
        id: String = UUID().uuidString,
        fileName: String,
        mimeType: String,
        base64: String,
        width: Int,
        height: Int,
        byteSize: Int
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.base64 = base64
        self.width = width
        self.height = height
        self.byteSize = byteSize
    }

    var dataURL: String { "data:\(mimeType);base64,\(base64)" }

    var dimensionsLabel: String { "\(width)\u{00D7}\(height)" }

    var sizeLabel: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(byteSize))
    }

    var nsImage: NSImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return NSImage(data: data)
    }
}

enum AttachedImageLoader {
    private static let supportedMimeTypes: Set<String> = [
        "image/png", "image/jpeg", "image/gif", "image/webp"
    ]

    /// Anthropic recommends ≤1568px long edge; OpenAI tiles at 768px so smaller is also cheaper there.
    private static let maxLongEdge = 1568

    /// Result of attempting to ingest images from a pasteboard or set of URLs.
    struct Outcome {
        var images: [AttachedImage] = []
        var rejected: Int = 0
    }

    static func load(from pasteboard: NSPasteboard) -> Outcome {
        var outcome = Outcome()
        // Files first (paste of file from Finder, or drag-drop URLs)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            for url in urls {
                if let image = load(from: url) {
                    outcome.images.append(image)
                } else {
                    outcome.rejected += 1
                }
            }
            if !outcome.images.isEmpty || outcome.rejected > 0 {
                return outcome
            }
        }
        // Inline image data (e.g. screenshot copy)
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], !images.isEmpty {
            for nsImage in images {
                if let image = makeAttached(from: nsImage, suggestedName: nil) {
                    outcome.images.append(image)
                } else {
                    outcome.rejected += 1
                }
            }
        }
        return outcome
    }

    static func load(from url: URL) -> AttachedImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let mime = mimeType(for: url, fallback: data)
        guard supportedMimeTypes.contains(mime) else { return nil }
        guard let nsImage = NSImage(data: data) else { return nil }
        let (w, h) = pixelSize(of: nsImage)
        let resolved = downscaleIfNeeded(data: data, mimeType: mime) ?? (data, mime, w, h)
        return AttachedImage(
            fileName: url.lastPathComponent,
            mimeType: resolved.1,
            base64: resolved.0.base64EncodedString(),
            width: resolved.2,
            height: resolved.3,
            byteSize: resolved.0.count
        )
    }

    static func makeAttached(from nsImage: NSImage, suggestedName: String?) -> AttachedImage? {
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:])
        else { return nil }
        let (w, h) = pixelSize(of: nsImage, bitmap: rep)
        let name = suggestedName ?? "Pasted image \(timestampString()).png"
        let resolved = downscaleIfNeeded(data: pngData, mimeType: "image/png") ?? (pngData, "image/png", w, h)
        return AttachedImage(
            fileName: name,
            mimeType: resolved.1,
            base64: resolved.0.base64EncodedString(),
            width: resolved.2,
            height: resolved.3,
            byteSize: resolved.0.count
        )
    }

    /// Resize the image so its long edge is ≤ `maxLongEdge`. Returns nil to mean
    /// "use the original bytes" — already small enough, animated GIF (would lose
    /// animation if redrawn), or any decode/encode failure.
    private static func downscaleIfNeeded(
        data: Data,
        mimeType: String
    ) -> (Data, String, Int, Int)? {
        if mimeType == "image/gif" { return nil }
        guard let src = NSBitmapImageRep(data: data) else { return nil }
        let srcW = src.pixelsWide
        let srcH = src.pixelsHigh
        let longEdge = max(srcW, srcH)
        guard longEdge > maxLongEdge else { return nil }

        let scale = Double(maxLongEdge) / Double(longEdge)
        let dstW = max(1, Int((Double(srcW) * scale).rounded()))
        let dstH = max(1, Int((Double(srcH) * scale).rounded()))

        let hasAlpha = src.hasAlpha
        guard let dst = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: dstW,
            pixelsHigh: dstH,
            bitsPerSample: 8,
            samplesPerPixel: hasAlpha ? 4 : 3,
            hasAlpha: hasAlpha,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        dst.size = NSSize(width: dstW, height: dstH)

        guard let ctx = NSGraphicsContext(bitmapImageRep: dst) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        src.draw(
            in: NSRect(x: 0, y: 0, width: dstW, height: dstH),
            from: NSRect(x: 0, y: 0, width: srcW, height: srcH),
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        let outMime: String
        let outData: Data?
        switch mimeType {
        case "image/jpeg":
            outMime = "image/jpeg"
            outData = dst.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        default:
            // PNG and WebP both re-encode as PNG (NSBitmapImageRep cannot write WebP).
            outMime = "image/png"
            outData = dst.representation(using: .png, properties: [:])
        }
        guard let outData else { return nil }
        return (outData, outMime, dstW, dstH)
    }

    private static func mimeType(for url: URL, fallback data: Data) -> String {
        if let ut = UTType(filenameExtension: url.pathExtension), let mime = ut.preferredMIMEType {
            return mime
        }
        // Sniff PNG / JPEG headers as a last resort.
        let header = data.prefix(8)
        if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if header.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if header.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        return "application/octet-stream"
    }

    private static func pixelSize(of image: NSImage, bitmap: NSBitmapImageRep? = nil) -> (Int, Int) {
        if let bitmap {
            return (bitmap.pixelsWide, bitmap.pixelsHigh)
        }
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        return (Int(image.size.width.rounded()), Int(image.size.height.rounded()))
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }
}
