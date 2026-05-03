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
        return AttachedImage(
            fileName: url.lastPathComponent,
            mimeType: mime,
            base64: data.base64EncodedString(),
            width: w,
            height: h,
            byteSize: data.count
        )
    }

    static func makeAttached(from nsImage: NSImage, suggestedName: String?) -> AttachedImage? {
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:])
        else { return nil }
        let (w, h) = pixelSize(of: nsImage, bitmap: rep)
        let name = suggestedName ?? "Pasted image \(timestampString()).png"
        return AttachedImage(
            fileName: name,
            mimeType: "image/png",
            base64: pngData.base64EncodedString(),
            width: w,
            height: h,
            byteSize: pngData.count
        )
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
