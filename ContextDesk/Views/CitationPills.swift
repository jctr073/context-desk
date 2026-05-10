import SwiftUI
import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - CitationSource

struct CitationSource: Hashable {
    let url: String
    let title: String

    var host: String {
        guard let h = URL(string: url)?.host, !h.isEmpty else { return url }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// Two-letter abbreviation for the favicon mini-badge. Uses the
    /// registrable label (second-to-last DNS part), so `dot.ca.gov` → "CA",
    /// `en.wikipedia.org` → "WI".
    var faviconLetters: String {
        let parts = host.split(separator: ".").map(String.init)
        let label = parts.count >= 2 ? parts[parts.count - 2] : host
        return String(label.prefix(2)).uppercased()
    }

    /// Short, human-friendly source name. Try the title's tail after a
    /// publisher separator (em/en-dash, pipe, middle-dot); fall back to the
    /// capitalized host primary label.
    var displayLabel: String {
        let separators: [String] = [" — ", " – ", " - ", " | ", " · ", "—", "–"]
        for sep in separators {
            if let r = title.range(of: sep, options: .backwards) {
                let tail = title[r.upperBound...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty && tail.count <= 60 { return tail }
            }
        }
        let parts = host.split(separator: ".").map(String.init)
        if parts.count >= 2 { return parts[parts.count - 2].capitalized }
        return host
    }
}

// MARK: - CitationRegistry

/// Resolves `<cite index="X-Y">` indexes to their source. The numbering
/// convention assumed: X is the 1-indexed position of a `web_search` /
/// `web_fetch` server-tool-use among the message's tool blocks; Y is the
/// 1-indexed hit within that tool's results. Falls back to a flat
/// global ordering for `index="N"`.
struct CitationRegistry {
    let byIndex: [String: CitationSource]
    let flat: [CitationSource]

    static let empty = CitationRegistry(byIndex: [:], flat: [])

    static func build(from blocks: [OutputBlock]) -> CitationRegistry {
        var byIndex: [String: CitationSource] = [:]
        var flat: [CitationSource] = []
        var toolCounter = 0

        for unit in ToolUnitWalker.walk(blocks) {
            guard case .tool(let t) = unit else { continue }
            let kind = ToolKind.from(name: t.call.name)
            guard kind == .webSearch || kind == .webFetch else { continue }
            toolCounter += 1
            guard let result = t.result, !result.isError else { continue }

            let sources: [CitationSource] = {
                switch kind {
                case .webSearch:
                    return ToolResultParser.webSearchHits(from: result.content).map {
                        CitationSource(url: $0.url, title: $0.title)
                    }
                case .webFetch:
                    if let s = parseFetchSource(args: t.call.argumentsJSON, content: result.content) {
                        return [s]
                    }
                    return []
                default:
                    return []
                }
            }()

            for (i, source) in sources.enumerated() {
                byIndex["\(toolCounter)-\(i + 1)"] = source
                flat.append(source)
            }
        }

        return CitationRegistry(byIndex: byIndex, flat: flat)
    }

    /// URLs that appear behind `<cite index="…">` tags in the prose of
    /// `blocks`. Used by the sources-first card to badge which rows are
    /// actually referenced inline.
    func citedURLs(in blocks: [OutputBlock]) -> Set<String> {
        var out: Set<String> = []
        for block in blocks {
            let text: String
            switch block {
            case .paragraph(let t): text = t
            case .heading(let t):   text = t
            case .bulletList(let items): text = items.joined(separator: "\n")
            case .table(_, let rows): text = rows.flatMap { $0 }.joined(separator: "\n")
            default: continue
            }
            for segment in CitationParser.parse(text) {
                if case .cite(_, let index) = segment, let src = lookup(index) {
                    out.insert(src.url)
                }
            }
        }
        return out
    }

    func lookup(_ index: String) -> CitationSource? {
        if let direct = byIndex[index] { return direct }
        // Flat fallback: "N" → flat[N-1].
        if let n = Int(index), n > 0, n <= flat.count {
            return flat[n - 1]
        }
        // "X-Y" with no direct match: try flat by Y, then by X.
        let parts = index.split(separator: "-").compactMap { Int($0) }
        if parts.count == 2 {
            let y = parts[1]
            if y > 0 && y <= flat.count { return flat[y - 1] }
        }
        return nil
    }

    private static func parseFetchSource(args: String, content: String) -> CitationSource? {
        // web_fetch result content is `{url, content: {title?, text?}, ...}`.
        // Use the request URL from args as the canonical source URL; pull
        // a title out of the result if available.
        guard let argsData = args.data(using: .utf8),
              let argsDict = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any],
              let url = argsDict["url"] as? String, !url.isEmpty
        else { return nil }

        var title: String = url
        if let resultData = content.data(using: .utf8),
           let resultDict = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
            if let inner = resultDict["content"] as? [String: Any],
               let t = inner["title"] as? String, !t.isEmpty {
                title = t
            } else if let t = resultDict["title"] as? String, !t.isEmpty {
                title = t
            }
        }
        return CitationSource(url: url, title: title)
    }
}

// MARK: - CitationParser

enum InlineSegment: Equatable {
    case text(String)
    case cite(claim: String, index: String)
}

enum CitationParser {
    /// Splits `<cite index="X-Y">CLAIM</cite>` runs out of a paragraph,
    /// keeping all surrounding text intact. Tags with no `index` attribute
    /// or with malformed structure are passed through as plain text.
    static func parse(_ input: String) -> [InlineSegment] {
        let pattern = #"<cite\b([^>]*)>(.*?)</cite>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return [.text(input)]
        }
        let ns = input as NSString
        let full = NSRange(location: 0, length: ns.length)
        var segments: [InlineSegment] = []
        var cursor = 0

        regex.enumerateMatches(in: input, range: full) { match, _, _ in
            guard let match = match else { return }
            if match.range.location > cursor {
                let pre = ns.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor
                ))
                if !pre.isEmpty { segments.append(.text(pre)) }
            }
            let attrs = ns.substring(with: match.range(at: 1))
            let claim = ns.substring(with: match.range(at: 2))
            if let idx = extractIndex(from: attrs), !idx.isEmpty {
                segments.append(.cite(claim: claim, index: idx))
            } else {
                segments.append(.text(claim))
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            let tail = ns.substring(with: NSRange(
                location: cursor,
                length: ns.length - cursor
            ))
            if !tail.isEmpty { segments.append(.text(tail)) }
        }

        return segments.isEmpty ? [.text(input)] : segments
    }

    private static func extractIndex(from attrs: String) -> String? {
        // index="..." or index='...'
        let patterns = [#"index\s*=\s*"([^"]+)""#, #"index\s*=\s*'([^']+)'"#]
        let ns = attrs as NSString
        let full = NSRange(location: 0, length: ns.length)
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p) else { continue }
            if let m = regex.firstMatch(in: attrs, range: full) {
                return ns.substring(with: m.range(at: 1))
            }
        }
        return nil
    }
}

// MARK: - CitationPillView

/// Compact inline pill: 12px favicon thumbnail + short source label,
/// rounded capsule background. Sized to be roughly text-line-height tall.
struct CitationPillView: View {
    let source: CitationSource
    let palette: Palette

    var body: some View {
        HStack(spacing: 4) {
            CitationFavicon(letters: source.faviconLetters)
            Text(source.displayLabel)
                .font(.system(size: 11.5))
                .foregroundColor(palette.text.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 1.5)
        .background(
            Capsule(style: .continuous)
                .fill(palette.text.opacity(0.06))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        )
        .fixedSize()
    }
}

private struct CitationFavicon: View {
    let letters: String

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(gradient)
            .frame(width: 13, height: 13)
            .overlay(
                Text(letters)
                    .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                    .foregroundColor(textColor)
            )
    }

    /// Gov sources (`*.gov`-style 2-letter codes like CA, NY, US, GO)
    /// render in the gold gradient from the design; everything else uses
    /// a deterministic seeded palette.
    private var gradient: LinearGradient {
        let govLike: Set<String> = ["CA", "NY", "TX", "WA", "FL", "US", "UK", "GO", "EU"]
        if govLike.contains(letters) {
            return LinearGradient(
                colors: [Color(hex: 0xFFD60A), Color(hex: 0xFF9F0A)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        let seed = abs(letters.hashValue)
        let palette: [(Color, Color)] = [
            (Color(hex: 0x5AC8FA), Color(hex: 0x0A84FF)),
            (Color(hex: 0xFF6B35), Color(hex: 0xC1272D)),
            (Color(hex: 0x30D158), Color(hex: 0x0A7A2F)),
            (Color(hex: 0xBF5AF2), Color(hex: 0x6E2EAF)),
            (Color(hex: 0x64D2FF), Color(hex: 0x5E5CE6)),
        ]
        let pair = palette[seed % palette.count]
        return LinearGradient(colors: [pair.0, pair.1],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var textColor: Color {
        let govLike: Set<String> = ["CA", "NY", "TX", "WA", "FL", "US", "UK", "GO", "EU"]
        return govLike.contains(letters) ? Color(hex: 0x3a2a00) : .white
    }
}

// MARK: - ProseTextBuilder

/// Builds a single concatenated `Text` containing prose runs (with
/// markdown applied) interleaved with inline pill glyphs rendered via
/// `ImageRenderer`. The result wraps natively because every run is
/// merged into one `Text`.
@MainActor
enum ProseTextBuilder {
    static func text(
        _ raw: String,
        registry: CitationRegistry,
        palette: Palette,
        slack: Bool = false
    ) -> Text {
        let segments = CitationParser.parse(raw)
        var out: Text = Text("")
        var hasContent = false

        for segment in segments {
            let next: Text
            switch segment {
            case .text(let s):
                next = markdownText(slack ? slackInlineAsMarkdown(s) : s)
            case .cite(let claim, let index):
                let claimSrc = slack ? slackInlineAsMarkdown(claim) : claim
                let claimText = markdownText(claimSrc)
                if let source = registry.lookup(index),
                   let img = pillImage(source: source, palette: palette) {
                    next = claimText
                        + Text(" ")
                        + Text(Image(nsImage: img)).baselineOffset(-1)
                } else {
                    next = claimText
                }
            }
            out = hasContent ? out + next : next
            hasContent = true
        }
        return hasContent ? out : Text(raw)
    }

    private static func markdownText(_ s: String) -> Text {
        let processed = autoLinkURLs(s)
        if let attr = try? AttributedString(markdown: processed, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )) {
            return Text(attr)
        }
        return Text(s)
    }

    /// Wrap bare `http(s)://` URLs that contain `<placeholder>` segments in
    /// explicit `[url](url)` markdown syntax. The default markdown auto-linker
    /// terminates at the first `<`, which fragments URLs like
    /// `https://github.com/<owner>/<repo>/graphs/traffic`.
    static func autoLinkURLs(_ s: String) -> String {
        guard s.contains("<"),
              s.range(of: "http://") != nil || s.range(of: "https://") != nil
        else { return s }

        let pattern = #"(?<![(\[<])\bhttps?://\S+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }

        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        let trailingPunct: Set<Character> = [
            ".", ",", ";", ":", "!", "?", ")", "]", "`", "\"", "'",
        ]
        var result = ""
        var cursor = 0

        regex.enumerateMatches(in: s, range: full) { match, _, _ in
            guard let match = match else { return }
            let r = match.range
            if r.location > cursor {
                result += ns.substring(with: NSRange(
                    location: cursor, length: r.location - cursor
                ))
            }
            var url = ns.substring(with: r)
            var trail = ""
            while let last = url.last, trailingPunct.contains(last) {
                trail = String(last) + trail
                url.removeLast()
            }
            if !url.isEmpty && url.contains("<") {
                let display = url
                    .replacingOccurrences(of: #"\"#, with: #"\\"#)
                    .replacingOccurrences(of: "<", with: #"\<"#)
                    .replacingOccurrences(of: ">", with: #"\>"#)
                result += "[\(display)](\(url))" + trail
            } else {
                result += url + trail
            }
            cursor = r.location + r.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(
                location: cursor, length: ns.length - cursor
            ))
        }
        return result
    }

    private static func slackInlineAsMarkdown(_ text: String) -> String {
        var out = text
        out = replacing(out, pattern: #"<([^|>]+)\|([^>]+)>"#, template: #"[$2]($1)"#)
        out = replacing(out, pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, template: #"**$1**"#)
        out = replacing(out, pattern: #"(?<!_)_([^_\n]+)_(?!_)"#, template: #"*$1*"#)
        out = replacing(out, pattern: #"(?<!~)~([^~\n]+)~(?!~)"#, template: #"~~$1~~"#)
        return out
    }

    private static func replacing(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func pillImage(source: CitationSource, palette: Palette) -> NSImage? {
        let cacheKey = PillCacheKey(url: source.url, label: source.displayLabel)
        if let cached = PillImageCache.shared.image(for: cacheKey) {
            return cached
        }
        let view = CitationPillView(source: source, palette: palette)
            .padding(0)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        guard let image = renderer.nsImage else { return nil }
        PillImageCache.shared.set(image, for: cacheKey)
        return image
    }
}

// MARK: - PillImageCache

private struct PillCacheKey: Hashable {
    let url: String
    let label: String
}

@MainActor
private final class PillImageCache {
    static let shared = PillImageCache()
    private var storage: [PillCacheKey: NSImage] = [:]
    private let maxEntries = 256

    func image(for key: PillCacheKey) -> NSImage? { storage[key] }

    func set(_ image: NSImage, for key: PillCacheKey) {
        if storage.count >= maxEntries {
            storage.removeAll(keepingCapacity: true)
        }
        storage[key] = image
    }
}
