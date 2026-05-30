import Foundation

/// Rule for recognizing which concrete API model ids belong to a family.
struct Lineage: Hashable {
    /// Required leading token, e.g. "claude-opus", "gpt-5".
    let prefix: String
    /// Extra negative filters beyond the global junk denylist.
    var excludeSubstrings: [String] = []
}

/// Ordered version key parsed out of a model id, used to pick the *latest*
/// concrete model within a family.
///
/// - "claude-opus-4-8"           → components [4, 8], snapshot nil
/// - "claude-haiku-4-5-20251001" → components [4, 5], snapshot 20251001
/// - "gpt-5.5"                    → components [5, 5], snapshot nil
/// - "gpt-5.5-2025-08-07"         → components [5, 5], snapshot 20250807
struct ModelVersionRank: Comparable, Hashable {
    let components: [Int]
    /// A trailing date snapshot, or nil for a bare alias. On a version tie the
    /// bare alias is preferred (ranks higher) — it's the stabler id to cache.
    let snapshot: Int?

    static func parse(_ rawID: String) -> ModelVersionRank {
        var id = rawID.lowercased()
        var snapshot: Int?

        // Strip a trailing date snapshot: -YYYYMMDD or -YYYY-MM-DD.
        if let range = id.range(
            of: "[-_](20[0-9]{2})-?([0-9]{2})-?([0-9]{2})$",
            options: .regularExpression
        ) {
            let digits = id[range].filter(\.isNumber)
            snapshot = Int(digits)
            id.removeSubrange(range)
        }

        var numbers: [Int] = []
        var current = ""
        for char in id {
            if char.isNumber {
                current.append(char)
            } else if !current.isEmpty {
                numbers.append(Int(current) ?? 0)
                current = ""
            }
        }
        if !current.isEmpty { numbers.append(Int(current) ?? 0) }

        return ModelVersionRank(components: numbers, snapshot: snapshot)
    }

    static func < (lhs: ModelVersionRank, rhs: ModelVersionRank) -> Bool {
        if lhs.components != rhs.components {
            return lexicographicallyLess(lhs.components, rhs.components)
        }
        // Same version number: a bare alias (nil snapshot) outranks a dated one.
        switch (lhs.snapshot, rhs.snapshot) {
        case (nil, nil):            return false
        case (nil, .some):          return false   // lhs (bare) is greater
        case (.some, nil):          return true    // lhs (dated) is lesser
        case let (.some(a), .some(b)): return a < b
        }
    }

    private static func lexicographicallyLess(_ a: [Int], _ b: [Int]) -> Bool {
        for (x, y) in zip(a, b) where x != y { return x < y }
        return a.count < b.count
    }
}

/// The runtime discovery result for one family: the latest concrete model id
/// plus its derived display name. Persisted in the on-disk catalog cache.
struct ResolvedFamily: Codable, Hashable {
    let familyID: String
    let apiModelID: String
    let displayName: String
}

/// A curated model family. The local table of families is the source of truth
/// for *which* models the picker offers and which reasoning efforts they
/// support; the live `/models` API only supplies the latest concrete id and
/// display version within each family (see `FamilyResolver`).
struct ModelFamily: Identifiable, Hashable {
    let id: String                       // stable key: "claude-opus", "gpt-5"
    let provider: AIProvider
    let displayBaseName: String          // "Claude Opus" — version appended at runtime
    let supportedEfforts: [ReasoningEffort]   // empty ⇒ non-reasoning
    let defaultEffort: ReasoningEffort?
    let lineage: Lineage
    let baselineAPIModelID: String       // offline fallback concrete id
    let baselineDisplayVersion: String?  // e.g. "4.7"
    /// Separator between the base name and version: " " for Claude, "-" for GPT.
    var versionSeparator: String = " "

    var isReasoning: Bool { !supportedEfforts.isEmpty }

    /// Display name when no live id is available (offline / pre-fetch).
    var bundledDisplayName: String {
        guard let version = baselineDisplayVersion else { return displayBaseName }
        return "\(displayBaseName)\(versionSeparator)\(version)"
    }

    func matches(_ apiID: String) -> Bool {
        let id = apiID.lowercased()
        guard id.hasPrefix(lineage.prefix) else { return false }
        for exclude in lineage.excludeSubstrings where id.contains(exclude) { return false }
        return true
    }

    func versionRank(of apiID: String) -> ModelVersionRank {
        ModelVersionRank.parse(apiID)
    }

    /// "4.8" from "claude-opus-4-8"; falls back to the bundled version.
    func versionSuffix(forAPIID apiID: String) -> String? {
        let rank = ModelVersionRank.parse(apiID)
        guard !rank.components.isEmpty else { return baselineDisplayVersion }
        return rank.components.map(String.init).joined(separator: ".")
    }

    func displayName(forAPIID apiID: String) -> String {
        guard let suffix = versionSuffix(forAPIID: apiID) else { return bundledDisplayName }
        return "\(displayBaseName)\(versionSeparator)\(suffix)"
    }

    /// Persisted / selection id. Reasoning: "<id>#<effort>"; otherwise "<id>".
    func compositeID(effort: ReasoningEffort?) -> String {
        guard let effort else { return id }
        return "\(id)#\(effort.rawValue)"
    }

    /// Build the request-ready `AIModel` for this family at the given effort,
    /// using the live `resolved` discovery when present, else the baseline.
    func aiModel(effort: ReasoningEffort?, resolved: ResolvedFamily?) -> AIModel {
        let apiModelID = resolved?.apiModelID ?? baselineAPIModelID
        let baseName = resolved?.displayName ?? bundledDisplayName
        let effort: ReasoningEffort? = isReasoning ? (effort ?? defaultEffort) : nil
        let name = effort.map { "\(baseName) \($0.displayLabel)" } ?? baseName
        return AIModel(
            id: compositeID(effort: effort),
            name: name,
            provider: provider,
            apiModelID: apiModelID,
            reasoningEffort: effort
        )
    }
}

// MARK: - Bundled catalog + id resolution

extension ModelFamily {
    static let bundled: [ModelFamily] = [
        ModelFamily(
            id: "claude-opus", provider: .anthropic, displayBaseName: "Claude Opus",
            supportedEfforts: [.low, .medium, .high, .xhigh, .max], defaultEffort: .high,
            lineage: Lineage(prefix: "claude-opus"),
            baselineAPIModelID: "claude-opus-4-7", baselineDisplayVersion: "4.7"
        ),
        ModelFamily(
            id: "claude-sonnet", provider: .anthropic, displayBaseName: "Claude Sonnet",
            supportedEfforts: [], defaultEffort: nil,
            lineage: Lineage(prefix: "claude-sonnet"),
            baselineAPIModelID: "claude-sonnet-4-6", baselineDisplayVersion: "4.6"
        ),
        ModelFamily(
            id: "claude-haiku", provider: .anthropic, displayBaseName: "Claude Haiku",
            supportedEfforts: [], defaultEffort: nil,
            lineage: Lineage(prefix: "claude-haiku"),
            baselineAPIModelID: "claude-haiku-4-5-20251001", baselineDisplayVersion: "4.5"
        ),
        ModelFamily(
            id: "gpt-5", provider: .openai, displayBaseName: "GPT",
            supportedEfforts: [.low, .medium, .high, .xhigh], defaultEffort: .medium,
            lineage: Lineage(prefix: "gpt-5"),
            baselineAPIModelID: "gpt-5.5", baselineDisplayVersion: "5.5",
            versionSeparator: "-"
        ),
        ModelFamily(
            id: "gemini-pro", provider: .google, displayBaseName: "Gemini",
            supportedEfforts: [], defaultEffort: nil,
            lineage: Lineage(prefix: "gemini-2.5-pro"),
            baselineAPIModelID: "gemini-2.5-pro", baselineDisplayVersion: "2.5 Pro"
        ),
    ]

    static let byID: [String: ModelFamily] =
        Dictionary(uniqueKeysWithValues: bundled.map { ($0.id, $0) })

    /// Resolve any persisted/legacy model id to its (family, effort). Handles
    /// new composite ids ("claude-opus#high"), bare family ids ("claude-sonnet"),
    /// and legacy variant/alias ids ("claude-opus-4-7-high", "gpt-5.5").
    static func resolve(id rawID: String) -> (family: ModelFamily, effort: ReasoningEffort?)? {
        if let hash = rawID.firstIndex(of: "#") {
            let familyID = String(rawID[..<hash])
            let effortRaw = String(rawID[rawID.index(after: hash)...])
            if let family = byID[familyID] {
                let effort = ReasoningEffort(rawValue: effortRaw)
                return (family, family.isReasoning ? (effort ?? family.defaultEffort) : nil)
            }
        }
        if let family = byID[rawID] {
            return (family, family.isReasoning ? family.defaultEffort : nil)
        }
        return legacyTable[rawID]
    }

    /// Legacy id → (family, effort) for ids persisted before the dynamic
    /// catalog: the old per-effort variant ids and the raw apiModelID aliases.
    private static let legacyTable: [String: (ModelFamily, ReasoningEffort?)] = {
        func family(_ id: String) -> ModelFamily { byID[id]! }
        let opus = family("claude-opus")
        let sonnet = family("claude-sonnet")
        let haiku = family("claude-haiku")
        let gpt = family("gpt-5")
        let gemini = family("gemini-pro")

        var table: [String: (ModelFamily, ReasoningEffort?)] = [:]

        table["claude-opus-4-7-low"] = (opus, .low)
        table["claude-opus-4-7-medium"] = (opus, .medium)
        table["claude-opus-4-7-high"] = (opus, .high)
        table["claude-opus-4-7-xhigh"] = (opus, .xhigh)
        table["claude-opus-4-7-max"] = (opus, .max)
        for alias in ["claude-opus-4", "claude-opus-4.7", "claude-opus-4-7"] {
            table[alias] = (opus, opus.defaultEffort)
        }

        table["gpt-5.5-low"] = (gpt, .low)
        table["gpt-5.5-medium"] = (gpt, .medium)
        table["gpt-5.5-high"] = (gpt, .high)
        table["gpt-5.5-xhigh"] = (gpt, .xhigh)
        for alias in ["gpt-5.5", "gpt-4.1", "gpt-4.1-mini"] {
            table[alias] = (gpt, gpt.defaultEffort)
        }

        for alias in ["claude-sonnet-4-6", "claude-sonnet-4.5",
                      "claude-sonnet-4-5", "claude-sonnet-4-5-20250929"] {
            table[alias] = (sonnet, nil)
        }
        for alias in ["claude-haiku-4-5", "claude-haiku-4.5", "claude-haiku-4-5-20251001"] {
            table[alias] = (haiku, nil)
        }
        table["gemini-2.5-pro"] = (gemini, nil)

        return table
    }()
}

// MARK: - Filtering / display helpers

extension ModelFamily {
    /// Substrings that mark a discovered model as non-chat (embeddings, audio,
    /// image, tool-augmented variants, legacy completion models, …).
    private static let junkSubstrings = [
        "embedding", "embed", "tts", "whisper", "dall-e", "dalle", "image",
        "audio", "realtime", "moderation", "transcribe", "instruct", "search",
        "computer-use", "rerank", "guard", "babbage", "davinci", "curie",
    ]

    /// A coarse gate: is this discovered id a flagship chat model we curate?
    /// The positive provider prefixes keep the noisy provider lists (OpenAI
    /// especially) down to the families we actually surface.
    static func isLikelyChatModel(apiID: String, provider: AIProvider) -> Bool {
        let id = apiID.lowercased()
        for junk in junkSubstrings where id.contains(junk) { return false }
        switch provider {
        case .anthropic: return id.hasPrefix("claude-")
        case .openai:    return id.hasPrefix("gpt-5")
        case .google:    return false
        }
    }

    /// Title-case a raw model id for a derived (unrecognized) row's label.
    static func prettify(_ apiID: String) -> String {
        apiID
            .split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
