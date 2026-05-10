import SwiftUI
import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - ToolKind

enum ToolKind {
    case webSearch
    case webFetch
    case code
    case generic

    static func from(name: String) -> ToolKind {
        switch name {
        case "web_search":            return .webSearch
        case "web_fetch":             return .webFetch
        case "code_execution",
             "bash_code_execution",
             "bash",
             "computer":               return .code
        default:                       return .generic
        }
    }

    var defaultLabel: String {
        switch self {
        case .webSearch: return "Web search"
        case .webFetch:  return "Fetch"
        case .code:      return "Ran code"
        case .generic:   return "Tool call"
        }
    }

    var runningLabel: String {
        switch self {
        case .webSearch: return "Searching"
        case .webFetch:  return "Fetching"
        case .code:      return "Running code"
        case .generic:   return "Running"
        }
    }

    var symbol: String {
        switch self {
        case .webSearch: return "magnifyingglass"
        case .webFetch:  return "globe"
        case .code:      return "chevron.left.forwardslash.chevron.right"
        case .generic:   return "wrench.adjustable"
        }
    }

    var tint: Color {
        switch self {
        case .webSearch: return Color(hex: 0x0A84FF)
        case .webFetch:  return Color(hex: 0x5EBF7C)
        case .code:      return Color(hex: 0xBF5AF2)
        case .generic:   return Color(hex: 0x0A84FF)
        }
    }
}

// MARK: - Result parsers

struct WebSearchHit: Hashable {
    let title: String
    let url: String

    var domain: String {
        guard let host = URL(string: url)?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var faviconLetters: String {
        let host = domain
        let parts = host.split(separator: ".").map(String.init)
        if parts.count >= 2 {
            let a = parts[parts.count - 2].prefix(1)
            let b = parts.last.map { $0.prefix(1) } ?? ""
            return (a + b).uppercased()
        }
        return host.prefix(2).uppercased()
    }
}

enum ToolResultParser {
    /// Anthropic web_search returns a JSON array of `web_search_result`
    /// objects. OpenAI's hosted web_search returns just the status string
    /// (`"completed"` / `"failed"`) — no rich payload available here.
    static func webSearchHits(from content: String) -> [WebSearchHit] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else { return [] }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return arr.compactMap(makeHit)
        }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = dict["results"] as? [[String: Any]] {
            return arr.compactMap(makeHit)
        }
        return []
    }

    private static func makeHit(_ dict: [String: Any]) -> WebSearchHit? {
        guard let url = dict["url"] as? String, !url.isEmpty,
              let title = dict["title"] as? String, !title.isEmpty
        else { return nil }
        return WebSearchHit(title: title, url: url)
    }

    /// Web search args arrive as `{"query": "..."}`. Extract just the query
    /// string so the card header isn't a JSON blob.
    static func extractedArgument(name: String, argumentsJSON: String) -> String? {
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "{}",
              let data = trimmed.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        switch name {
        case "web_search":
            return (dict["query"] as? String).map { "\u{201C}\($0)\u{201D}" }
        case "web_fetch":
            return dict["url"] as? String
        case "code_execution", "bash", "bash_code_execution":
            // Show first non-empty line of the code.
            let code = (dict["code"] as? String) ?? (dict["command"] as? String) ?? ""
            let line = code.split(whereSeparator: \.isNewline)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                .map(String.init) ?? ""
            return line.isEmpty ? nil : line
        default:
            return nil
        }
    }
}

enum ExternalURLPolicy {
    private static let allowedSchemes: Set<String> = ["http", "https"]

    static func webURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        return url
    }

    static func openWebURL(from raw: String) {
#if canImport(AppKit)
        guard let url = webURL(from: raw) else { return }
        NSWorkspace.shared.open(url)
#endif
    }
}

// MARK: - ToolCardView

struct ToolCardView: View {
    let id: String
    let toolName: String
    let argumentsJSON: String
    /// `nil` means the call is still running.
    let resultContent: String?
    let isError: Bool
    let palette: Palette

    @State private var expanded: Bool
    @State private var pulse: Bool = false
    @State private var showRaw: Bool = false

    init(
        id: String,
        toolName: String,
        argumentsJSON: String,
        resultContent: String?,
        isError: Bool,
        palette: Palette,
        defaultExpanded: Bool = false
    ) {
        self.id = id
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.resultContent = resultContent
        self.isError = isError
        self.palette = palette
        _expanded = State(initialValue: defaultExpanded)
    }

    private var kind: ToolKind { .from(name: toolName) }
    private var isRunning: Bool { resultContent == nil && !isError }
    private var headerLabel: String {
        if isError { return "Failed" }
        return isRunning ? kind.runningLabel : kind.defaultLabel
    }
    private var headerName: String? {
        ToolResultParser.extractedArgument(name: toolName, argumentsJSON: argumentsJSON)
    }
    private var hits: [WebSearchHit] {
        guard let resultContent, kind == .webSearch else { return [] }
        return ToolResultParser.webSearchHits(from: resultContent)
    }
    private var hasExpandableBody: Bool {
        if isError { return !(resultContent ?? "").isEmpty }
        if isRunning { return false }
        if !hits.isEmpty { return true }
        if let resultContent, !resultContent.isEmpty, resultContent != "completed" { return true }
        return !argumentsJSON.isEmpty && argumentsJSON != "{}"
    }
    private var metaText: String? {
        if isRunning { return nil }
        if isError { return nil }
        if !hits.isEmpty {
            return "\(hits.count) source\(hits.count == 1 ? "" : "s")"
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
                .contentShape(Rectangle())
                .onTapGesture {
                    guard hasExpandableBody else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }

            if expanded && hasExpandableBody {
                Divider().background(borderColor)
                bodySection
                if showRaw, let resultContent, !resultContent.isEmpty {
                    Divider().background(borderColor)
                    prettyText(resultContent)
                }
                Divider().background(borderColor)
                footer
            }
        }
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear {
            guard isRunning else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
    }

    // MARK: Top row

    private var topRow: some View {
        HStack(spacing: 10) {
            iconBadge

            Text(headerLabel.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(isError ? Color(hex: 0xFF453A) : palette.muted)
                .fixedSize()

            if let headerName {
                Text(headerName)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            if let metaText {
                Text(metaText)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundColor(palette.muted)
                    .fixedSize()
            }

            if hasExpandableBody {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(palette.muted)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(iconBadgeFill)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(iconBadgeStroke, lineWidth: 1)
                        .opacity(isRunning ? (pulse ? 1.0 : 0.0) : 0.0)
                )
            Image(systemName: isError ? "exclamationmark.triangle.fill" : kind.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isError ? Color(hex: 0xFF453A) : kind.tint)
        }
        .opacity(isRunning ? (pulse ? 0.6 : 1.0) : 1.0)
    }

    private var iconBadgeFill: Color {
        if isError { return Color(hex: 0xFF453A).opacity(0.16) }
        return kind.tint.opacity(0.14)
    }

    private var iconBadgeStroke: Color {
        kind.tint.opacity(0.45)
    }

    // MARK: Body

    @ViewBuilder
    private var bodySection: some View {
        if !hits.isEmpty {
            smartSummary
        } else if let resultContent, !resultContent.isEmpty {
            prettyText(resultContent)
        } else if !argumentsJSON.isEmpty && argumentsJSON != "{}" {
            prettyText(argumentsJSON)
        }
    }

    private var smartSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOP RESULTS")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(palette.muted)
                .padding(.bottom, 2)

            ForEach(Array(hits.enumerated()), id: \.offset) { idx, hit in
                hitRow(hit, isLast: idx == hits.count - 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hitRow(_ hit: WebSearchHit, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                FaviconBadge(letters: hit.faviconLetters)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 2 }

                Text(hit.title)
                    .font(.system(size: 12.5))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(hit.domain)
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 6)

            if !isLast {
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ExternalURLPolicy.openWebURL(from: hit.url)
        }
    }

    private func prettyText(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(palette.text.opacity(0.65))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(maxHeight: 240)
        .background(insetBackground)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if !hits.isEmpty {
                Text("\(hits.count) source\(hits.count == 1 ? "" : "s")")
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.muted)
            }
            Spacer(minLength: 0)
            if let resultContent, !resultContent.isEmpty {
                Button(action: { withAnimation(.easeInOut(duration: 0.12)) { showRaw.toggle() } }) {
                    Text(showRaw ? "Hide raw" : "Show raw")
                        .font(.system(size: 11.5))
                        .foregroundColor(palette.muted)
                        .underline(true, pattern: .dash)
                }
                .buttonStyle(.plain)
                .help("Toggle the raw tool result (\(resultContent.count) chars)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: Styling

    private var cardBackground: Color {
        if isError { return Color(hex: 0xFF453A).opacity(0.06) }
        return palette.text.opacity(0.025)
    }

    private var borderColor: Color {
        if isError { return Color(hex: 0xFF453A).opacity(0.40) }
        return palette.border
    }

    private var insetBackground: Color {
        Color.black.opacity(0.18)
    }
}

// MARK: - FaviconBadge

private struct FaviconBadge: View {
    let letters: String

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(gradient)
            .frame(width: 14, height: 14)
            .overlay(
                Text(letters)
                    .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            )
    }

    private var gradient: LinearGradient {
        let seed = abs(letters.hashValue)
        let palette: [(Color, Color)] = [
            (Color(hex: 0x5AC8FA), Color(hex: 0x0A84FF)),
            (Color(hex: 0xFFD60A), Color(hex: 0xFF9F0A)),
            (Color(hex: 0xFF6B35), Color(hex: 0xC1272D)),
            (Color(hex: 0x30D158), Color(hex: 0x0A7A2F)),
            (Color(hex: 0xBF5AF2), Color(hex: 0x6E2EAF)),
            (Color(hex: 0x64D2FF), Color(hex: 0x5E5CE6)),
        ]
        let pair = palette[seed % palette.count]
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - ToolUnit pairing

/// One tool-call card render unit: a `.toolCall` and (optionally) its
/// matching `.toolResult`.
struct ToolUnit {
    let call: (id: String, name: String, argumentsJSON: String)
    let result: (content: String, isError: Bool)?
}

enum ToolUnitWalker {
    /// Render units = either a non-tool block or a paired tool unit.
    enum Unit {
        case block(OutputBlock)
        case tool(ToolUnit)
    }

    static func walk(_ blocks: [OutputBlock]) -> [Unit] {
        var out: [Unit] = []
        var consumedResultIDs: Set<String> = []
        var i = 0
        while i < blocks.count {
            let block = blocks[i]
            if case .toolCall(let id, let name, let args) = block {
                var resultIdx: Int? = nil
                for j in (i + 1)..<blocks.count {
                    if case .toolCall = blocks[j] { break }
                    if case .toolResult(let cid, _, _) = blocks[j], cid == id {
                        resultIdx = j
                        break
                    }
                }
                if let r = resultIdx, case .toolResult(let cid, let content, let isError) = blocks[r] {
                    out.append(.tool(ToolUnit(
                        call: (id, name, args),
                        result: (content, isError)
                    )))
                    consumedResultIDs.insert(cid)
                } else {
                    out.append(.tool(ToolUnit(
                        call: (id, name, args),
                        result: nil
                    )))
                }
                i += 1
                continue
            }
            if case .toolResult(let cid, _, _) = block, consumedResultIDs.contains(cid) {
                i += 1
                continue
            }
            out.append(.block(block))
            i += 1
        }
        return out
    }

    /// Group the flat unit list so consecutive tool units cluster into
    /// one wrapper. Single tools render unwrapped (the renderer reads
    /// `cluster.count` to decide).
    enum Cluster {
        case block(OutputBlock)
        case toolCluster([ToolUnit])
    }

    static func cluster(_ units: [Unit]) -> [Cluster] {
        var out: [Cluster] = []
        var pending: [ToolUnit] = []
        func flush() {
            if !pending.isEmpty {
                out.append(.toolCluster(pending))
                pending.removeAll()
            }
        }
        for unit in units {
            switch unit {
            case .tool(let t):
                pending.append(t)
            case .block(let b):
                flush()
                out.append(.block(b))
            }
        }
        flush()
        return out
    }

}

// MARK: - SourcesFirstCard

/// One unified card per cluster of tool activity — a vertical "Searched &
/// read N sources" list at the top, with a footer of click-to-expand
/// pellets summarizing the demoted noise (code steps, fetches without
/// titles, errors). Replaces the prior per-tool cards plus their group
/// wrapper.
struct SourcesFirstCard: View {
    let units: [ToolUnit]
    let citedURLs: Set<String>
    let palette: Palette

    @State private var expanded: Bool = true
    @State private var openPellets: Set<PelletKind> = []

    enum PelletKind: Hashable { case code, fetch, warning }

    private struct SourceRow: Identifiable {
        let id = UUID()
        let url: String
        let title: String
        let domain: String
        let cited: Bool
        let faviconLetters: String
    }

    // MARK: Aggregation

    private var sources: [SourceRow] {
        var seen: Set<String> = []
        var out: [SourceRow] = []
        for unit in units {
            guard let result = unit.result, !result.isError else { continue }
            switch ToolKind.from(name: unit.call.name) {
            case .webSearch:
                for hit in ToolResultParser.webSearchHits(from: result.content) {
                    guard !seen.contains(hit.url) else { continue }
                    seen.insert(hit.url)
                    out.append(SourceRow(
                        url: hit.url,
                        title: hit.title,
                        domain: hit.domain,
                        cited: citedURLs.contains(hit.url),
                        faviconLetters: hit.faviconLetters
                    ))
                }
            case .webFetch:
                guard let url = fetchURL(from: unit.call.argumentsJSON),
                      !seen.contains(url) else { continue }
                seen.insert(url)
                let source = CitationSource(
                    url: url,
                    title: fetchTitle(from: result.content) ?? url
                )
                out.append(SourceRow(
                    url: url,
                    title: source.title,
                    domain: source.host,
                    cited: citedURLs.contains(url),
                    faviconLetters: source.faviconLetters
                ))
            default:
                break
            }
        }
        return out
    }

    private var codeUnits: [ToolUnit] {
        units.filter { ToolKind.from(name: $0.call.name) == .code }
    }

    /// Errors stand alone as a "warnings" pellet — the user wanted them
    /// surfaced even though their underlying call already shows up in
    /// the relevant kind's bucket.
    private var errorUnits: [ToolUnit] {
        units.filter { ($0.result?.isError ?? false) }
    }

    private var anyRunning: Bool {
        units.contains(where: { $0.result == nil })
    }

    private var primaryKind: ToolKind {
        if !sources.isEmpty {
            // Prefer search if any unit produced search hits.
            if units.contains(where: { ToolKind.from(name: $0.call.name) == .webSearch
                                       && (($0.result.map { !$0.isError && !ToolResultParser.webSearchHits(from: $0.content).isEmpty }) ?? false) }) {
                return .webSearch
            }
            return .webFetch
        }
        if !codeUnits.isEmpty { return .code }
        return .generic
    }

    private var headerLabel: String {
        let n = sources.count
        let cN = codeUnits.count
        switch primaryKind {
        case .webSearch:
            return anyRunning
                ? "Searching the web"
                : "Searched & read \(n) source\(n == 1 ? "" : "s")"
        case .webFetch:
            return anyRunning
                ? "Fetching"
                : "Fetched \(n) page\(n == 1 ? "" : "s")"
        case .code:
            return anyRunning
                ? "Running code"
                : "Code analysis · \(cN) step\(cN == 1 ? "" : "s")"
        case .generic:
            return anyRunning ? "Running tool" : "Tool activity"
        }
    }

    /// First search query encountered, monospace-displayed beside the
    /// label like the design's `qy` slot.
    private var headerQuery: String? {
        for unit in units where ToolKind.from(name: unit.call.name) == .webSearch {
            if let q = ToolResultParser.extractedArgument(name: unit.call.name, argumentsJSON: unit.call.argumentsJSON) {
                return q
            }
        }
        return nil
    }

    private var hasExpandableBody: Bool {
        !sources.isEmpty || !pellets.isEmpty
    }

    // MARK: Pellets

    private struct Pellet { let kind: PelletKind; let count: Int; let units: [ToolUnit] }

    private var pellets: [Pellet] {
        var out: [Pellet] = []
        if !codeUnits.isEmpty {
            out.append(Pellet(kind: .code, count: codeUnits.count, units: codeUnits))
        }
        // Fetches whose URL didn't make it into sources (rare — malformed
        // payload). Counted by parsing the args.
        let strandedFetches = units.filter {
            ToolKind.from(name: $0.call.name) == .webFetch
                && fetchURL(from: $0.call.argumentsJSON) == nil
        }
        if !strandedFetches.isEmpty {
            out.append(Pellet(kind: .fetch, count: strandedFetches.count, units: strandedFetches))
        }
        if !errorUnits.isEmpty {
            out.append(Pellet(kind: .warning, count: errorUnits.count, units: errorUnits))
        }
        return out
    }

    // MARK: View

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture {
                    guard hasExpandableBody else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }

            if expanded && !sources.isEmpty {
                Divider().background(palette.border)
                sourceList
            }
            if expanded && !pellets.isEmpty {
                pelletFooter
            }
        }
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            iconBadge

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headerLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .fixedSize()
                if let headerQuery {
                    Text(headerQuery)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(palette.text.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasExpandableBody {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(palette.muted)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(primaryKind.tint.opacity(0.14))
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(primaryKind.tint.opacity(0.45), lineWidth: 1)
                        .opacity(anyRunning ? 1 : 0)
                )
            Image(systemName: primaryKind.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(primaryKind.tint)
        }
    }

    private var sourceList: some View {
        VStack(spacing: 0) {
            ForEach(Array(sources.enumerated()), id: \.offset) { idx, src in
                sourceRow(src, isLast: idx == sources.count - 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private func sourceRow(_ src: SourceRow, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                FaviconBadge(letters: src.faviconLetters)
                Text(src.title)
                    .font(.system(size: 12.5))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if src.cited {
                    Text("cited")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: 0x5CD97A))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: 0x30D158).opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(hex: 0x30D158).opacity(0.2), lineWidth: 1)
                        )
                }
                Text(src.domain)
                    .font(.system(size: 11.5))
                    .foregroundColor(palette.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, 8)

            if !isLast {
                Rectangle().fill(palette.border.opacity(0.4)).frame(height: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { ExternalURLPolicy.openWebURL(from: src.url) }
    }

    @ViewBuilder
    private var pelletFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Array(pellets.enumerated()), id: \.offset) { _, p in
                    pelletButton(p)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            ForEach(Array(pellets.enumerated()), id: \.offset) { _, p in
                if openPellets.contains(p.kind) {
                    pelletDetail(p)
                }
            }
        }
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border).frame(height: 0.5)
        }
    }

    private func pelletButton(_ p: Pellet) -> some View {
        let open = openPellets.contains(p.kind)
        return HStack(spacing: 6) {
            Image(systemName: pelletSymbol(p.kind))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(pelletColor(p.kind))
            Text("\(p.count)")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(palette.text)
            Text(pelletLabel(p.kind, count: p.count))
                .font(.system(size: 11.5))
                .foregroundColor(palette.text.opacity(0.7))
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(pelletBackground(p.kind, open: open))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(pelletBorder(p.kind, open: open), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if openPellets.contains(p.kind) {
                    openPellets.remove(p.kind)
                } else {
                    openPellets.insert(p.kind)
                }
            }
        }
    }

    @ViewBuilder
    private func pelletDetail(_ p: Pellet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pelletLabel(p.kind, count: p.count).uppercased() + " · \(p.count)")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(palette.muted)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(Array(p.units.enumerated()), id: \.offset) { idx, unit in
                pelletDetailRow(unit, isLast: idx == p.units.count - 1)
            }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.border.opacity(0.6)).frame(height: 0.5)
        }
    }

    private func pelletDetailRow(_ unit: ToolUnit, isLast: Bool) -> some View {
        let isError = unit.result?.isError ?? false
        let isRunning = unit.result == nil
        let arg: String = {
            if let line = ToolResultParser.extractedArgument(
                name: unit.call.name, argumentsJSON: unit.call.argumentsJSON
            ) { return line }
            return unit.call.name
        }()
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isError
                          ? Color(hex: 0xFF453A)
                          : (isRunning ? primaryKind.tint : Color(hex: 0x30D158)))
                    .frame(width: 6, height: 6)
                Text(arg)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(isError ? Color(hex: 0xFF8E88) : palette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if isError {
                    Text("error")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: 0xFF8E88))
                } else if isRunning {
                    Text("…")
                        .font(.system(size: 10.5))
                        .foregroundColor(palette.muted)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)

            if !isLast {
                Rectangle().fill(palette.border.opacity(0.3)).frame(height: 0.5)
                    .padding(.leading, 28)
            }
        }
    }

    // MARK: Pellet styling

    private func pelletSymbol(_ kind: PelletKind) -> String {
        switch kind {
        case .code:    return "chevron.left.forwardslash.chevron.right"
        case .fetch:   return "globe"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private func pelletLabel(_ kind: PelletKind, count: Int) -> String {
        switch kind {
        case .code:    return count == 1 ? "code step" : "code steps"
        case .fetch:   return count == 1 ? "fetch" : "fetches"
        case .warning: return count == 1 ? "warning" : "warnings"
        }
    }

    private func pelletColor(_ kind: PelletKind) -> Color {
        switch kind {
        case .code:    return Color(hex: 0xBF5AF2)
        case .fetch:   return Color(hex: 0x30D158)
        case .warning: return Color(hex: 0xFF453A)
        }
    }

    private func pelletBackground(_ kind: PelletKind, open: Bool) -> Color {
        if kind == .warning { return Color(hex: 0xFF453A).opacity(open ? 0.16 : 0.08) }
        return palette.text.opacity(open ? 0.08 : 0.04)
    }

    private func pelletBorder(_ kind: PelletKind, open: Bool) -> Color {
        if kind == .warning { return Color(hex: 0xFF453A).opacity(0.35) }
        return open ? palette.borderStrong : palette.border
    }

    // MARK: Card chrome

    private var cardBackground: Color {
        anyRunning
            ? Color(hex: 0x0A84FF).opacity(0.04)
            : palette.text.opacity(0.025)
    }

    private var borderColor: Color {
        anyRunning ? Color(hex: 0x0A84FF).opacity(0.30) : palette.border
    }

    // MARK: Helpers

    private func fetchURL(from argsJSON: String) -> String? {
        guard let data = argsJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (dict["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func fetchTitle(from content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let inner = dict["content"] as? [String: Any],
           let t = inner["title"] as? String, !t.isEmpty { return t }
        if let t = dict["title"] as? String, !t.isEmpty { return t }
        return nil
    }
}

