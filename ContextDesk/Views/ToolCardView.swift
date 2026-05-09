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

// MARK: - ToolGroupView

/// Wraps a cluster of consecutive tool units in a Codex-style "Worked for"
/// header. Single-unit clusters skip the wrapper entirely.
struct ToolGroupView: View {
    let units: [ToolUnit]
    let palette: Palette

    @State private var expanded: Bool

    init(units: [ToolUnit], palette: Palette) {
        self.units = units
        self.palette = palette
        // Default-expand any group that has at least one running call so
        // the user sees activity; otherwise default-expand too — the user
        // wanted to see the smart summary out of the box.
        _expanded = State(initialValue: true)
    }

    private var anyRunning: Bool {
        units.contains(where: { $0.result == nil })
    }
    private var totalSources: Int {
        units.reduce(0) { acc, unit in
            guard let result = unit.result, !result.isError else { return acc }
            let kind = ToolKind.from(name: unit.call.name)
            guard kind == .webSearch else { return acc }
            return acc + ToolResultParser.webSearchHits(from: result.content).count
        }
    }
    private var headerTitle: String {
        if anyRunning { return "Working" }
        return "Worked"
    }
    private var headerMeta: String {
        var parts: [String] = []
        let toolCount = units.count
        parts.append("\(toolCount) tool\(toolCount == 1 ? "" : "s")")
        if totalSources > 0 {
            parts.append("\(totalSources) source\(totalSources == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }

            if expanded {
                Divider().background(palette.border)
                VStack(spacing: 8) {
                    ForEach(Array(ToolUnitWalker.subCluster(units).enumerated()), id: \.offset) { _, sub in
                        switch sub {
                        case .codeRun(let codeUnits):
                            CodeSessionRollView(units: codeUnits, palette: palette)
                        case .single(let unit):
                            ToolCardView(
                                id: unit.call.id,
                                toolName: unit.call.name,
                                argumentsJSON: unit.call.argumentsJSON,
                                resultContent: unit.result?.content,
                                isError: unit.result?.isError ?? false,
                                palette: palette,
                                defaultExpanded: defaultExpanded(for: unit)
                            )
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(palette.text.opacity(0.018))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Expand the first card in the group that has a smart summary.
    private func defaultExpanded(for unit: ToolUnit) -> Bool {
        guard let result = unit.result, !result.isError else { return false }
        let kind = ToolKind.from(name: unit.call.name)
        guard kind == .webSearch else { return false }
        let hits = ToolResultParser.webSearchHits(from: result.content)
        guard !hits.isEmpty else { return false }
        for prior in units {
            if prior.call.id == unit.call.id { return true }
            if let r = prior.result, !r.isError,
               ToolKind.from(name: prior.call.name) == .webSearch,
               !ToolResultParser.webSearchHits(from: r.content).isEmpty {
                return false
            }
        }
        return true
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.16))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle().stroke(palette.accent.opacity(0.45), lineWidth: 1)
                    )
                Image(systemName: anyRunning ? "bolt.fill" : "bolt")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(palette.accent)
            }

            Text(headerTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(palette.text)

            Text("· \(headerMeta)")
                .font(.system(size: 11.5))
                .foregroundColor(palette.muted)

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(palette.muted)
                .rotationEffect(.degrees(expanded ? 0 : -90))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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

    /// Sub-cluster within a tool group: a run of consecutive code-execution
    /// units rolls into a `CodeSessionRollView`; everything else stays a
    /// single `ToolCardView`.
    enum SubCluster {
        case codeRun([ToolUnit])
        case single(ToolUnit)
    }

    static func subCluster(_ units: [ToolUnit]) -> [SubCluster] {
        var out: [SubCluster] = []
        var codeRun: [ToolUnit] = []
        func flushCode() {
            if !codeRun.isEmpty {
                out.append(.codeRun(codeRun))
                codeRun.removeAll()
            }
        }
        for u in units {
            if ToolKind.from(name: u.call.name) == .code {
                codeRun.append(u)
            } else {
                flushCode()
                out.append(.single(u))
            }
        }
        flushCode()
        return out
    }
}

// MARK: - CodeSessionRollView

/// "Rolled-up" code-execution session — a single collapsible card with
/// numbered, monospace lines per step. Collapsed by default.
struct CodeSessionRollView: View {
    let units: [ToolUnit]
    let palette: Palette

    @State private var expanded: Bool = false

    private var errorCount: Int {
        units.reduce(0) { $0 + ((($1.result?.isError) == true) ? 1 : 0) }
    }
    private var anyRunning: Bool {
        units.contains(where: { $0.result == nil })
    }
    private var latestLine: String {
        for unit in units.reversed() {
            if let line = ToolResultParser.extractedArgument(
                name: unit.call.name, argumentsJSON: unit.call.argumentsJSON
            ) {
                return line
            }
        }
        return ""
    }
    private var latestPreview: String {
        let count = units.count
        let stepWord = count == 1 ? "step" : "steps"
        if latestLine.isEmpty { return "\(count) \(stepWord)" }
        return "\(count) \(stepWord) · last: \(latestLine)"
    }
    private var metaText: String {
        if anyRunning {
            return errorCount > 0 ? "\(errorCount) errors · running" : "running"
        }
        if errorCount > 0 {
            return "\(errorCount) error\(errorCount == 1 ? "" : "s")"
        }
        return ""
    }

    private static let codeTint = Color(hex: 0xBF5AF2)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }
            if expanded {
                Divider().background(palette.border)
                bodyRows
            }
        }
        .background(palette.text.opacity(0.025))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Self.codeTint.opacity(0.14))
                    .frame(width: 24, height: 24)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Self.codeTint)
            }

            Text("CODE SESSION")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(palette.muted)
                .fixedSize()

            Text(latestPreview)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(palette.text.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !metaText.isEmpty {
                Text(metaText)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(errorCount > 0 ? Color(hex: 0xFF453A) : palette.muted)
                    .fixedSize()
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(palette.muted)
                .rotationEffect(.degrees(expanded ? 0 : -90))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private var bodyRows: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(units.enumerated()), id: \.offset) { idx, unit in
                    row(idx: idx + 1, unit: unit)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 280)
        .background(Color.black.opacity(0.18))
    }

    @ViewBuilder
    private func row(idx: Int, unit: ToolUnit) -> some View {
        let line = ToolResultParser.extractedArgument(
            name: unit.call.name, argumentsJSON: unit.call.argumentsJSON
        ) ?? ""
        let isError = (unit.result?.isError ?? false)
        let isComment = line.trimmingCharacters(in: .whitespaces).hasPrefix("#")

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(format: "%02d", idx))
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(isError ? Color(hex: 0xFF453A) : palette.text.opacity(0.25))
                .frame(width: 28, alignment: .trailing)

            Text(line)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(rowColor(isError: isError, isComment: isComment))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            if isError {
                Text("\u{2715}")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(Color(hex: 0xFF453A))
            } else if unit.result == nil {
                Text("…")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(palette.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }

    private func rowColor(isError: Bool, isComment: Bool) -> Color {
        if isError { return Color(hex: 0xFF8E88) }
        if isComment { return palette.text.opacity(0.45) }
        return palette.text
    }
}
