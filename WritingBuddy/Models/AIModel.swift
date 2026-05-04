import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Hashable {
    case anthropic, openai, google

    var id: String { rawValue }

    var sectionLabel: String {
        switch self {
        case .anthropic: return "ANTHROPIC"
        case .openai:    return "OPENAI"
        case .google:    return "GOOGLE"
        }
    }

    var keyLabel: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai:    return "OpenAI"
        case .google:    return "Google"
        }
    }

    var apiHost: String {
        switch self {
        case .anthropic: return "api.anthropic.com"
        case .openai:    return "api.openai.com"
        case .google:    return "generativelanguage.googleapis.com"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-…"
        case .openai:    return "sk-…"
        case .google:    return "AIza…"
        }
    }

    var shellAPIKeyNames: [String] {
        switch self {
        case .anthropic: return ["ANTHROPIC_API_KEY"]
        case .openai:    return ["OPENAI_API_KEY"]
        case .google:    return ["GOOGLE_API_KEY", "GEMINI_API_KEY"]
        }
    }

    var shellAPIKeyLabel: String {
        shellAPIKeyNames.joined(separator: " or ")
    }

    var primaryShellAPIKeyName: String {
        shellAPIKeyNames[0]
    }

    var shellAPIKeyExample: String {
        "export \(primaryShellAPIKeyName)=\"\(keyPlaceholder)\""
    }

    var getKeyURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai:    return URL(string: "https://platform.openai.com/api-keys")!
        case .google:    return URL(string: "https://aistudio.google.com/app/apikey")!
        }
    }
}

enum ReasoningEffort: String, Codable, Hashable {
    case low
    case medium
    case high
    case xhigh
    case max
}

struct AIModel: Identifiable, Hashable {
    let id: String
    let name: String
    let provider: AIProvider
    let apiModelID: String
    let reasoningEffort: ReasoningEffort?

    init(
        id: String,
        name: String,
        provider: AIProvider,
        apiModelID: String? = nil,
        reasoningEffort: ReasoningEffort? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.apiModelID = apiModelID ?? id
        self.reasoningEffort = reasoningEffort
    }

    static let claudeOpus47Low    = AIModel(id: "claude-opus-4-7-low",    name: "Claude Opus 4.7 Low",    provider: .anthropic, apiModelID: "claude-opus-4-7", reasoningEffort: .low)
    static let claudeOpus47Medium = AIModel(id: "claude-opus-4-7-medium", name: "Claude Opus 4.7 Medium", provider: .anthropic, apiModelID: "claude-opus-4-7", reasoningEffort: .medium)
    static let claudeOpus47High   = AIModel(id: "claude-opus-4-7-high",   name: "Claude Opus 4.7 High",   provider: .anthropic, apiModelID: "claude-opus-4-7", reasoningEffort: .high)
    static let claudeOpus47XHigh  = AIModel(id: "claude-opus-4-7-xhigh",  name: "Claude Opus 4.7 xhigh",  provider: .anthropic, apiModelID: "claude-opus-4-7", reasoningEffort: .xhigh)
    static let claudeOpus47Max    = AIModel(id: "claude-opus-4-7-max",    name: "Claude Opus 4.7 Max",    provider: .anthropic, apiModelID: "claude-opus-4-7", reasoningEffort: .max)
    static let claudeOpus47       = claudeOpus47High
    static let claudeSonnet46     = AIModel(id: "claude-sonnet-4-6",      name: "Claude Sonnet 4.6",      provider: .anthropic)
    static let claudeHaiku45      = AIModel(id: "claude-haiku-4-5",       name: "Claude Haiku 4.5",       provider: .anthropic, apiModelID: "claude-haiku-4-5-20251001")
    static let gpt55Low           = AIModel(id: "gpt-5.5-low",            name: "GPT-5.5 Low",            provider: .openai, apiModelID: "gpt-5.5", reasoningEffort: .low)
    static let gpt55Medium        = AIModel(id: "gpt-5.5-medium",         name: "GPT-5.5 Medium",         provider: .openai, apiModelID: "gpt-5.5", reasoningEffort: .medium)
    static let gpt55High          = AIModel(id: "gpt-5.5-high",           name: "GPT-5.5 High",           provider: .openai, apiModelID: "gpt-5.5", reasoningEffort: .high)
    static let gpt55XHigh         = AIModel(id: "gpt-5.5-xhigh",          name: "GPT-5.5 xhigh",          provider: .openai, apiModelID: "gpt-5.5", reasoningEffort: .xhigh)
    static let gemini25Pro        = AIModel(id: "gemini-2.5-pro",         name: "Gemini 2.5 Pro",         provider: .google)

    static let all: [AIModel] = [
        .claudeOpus47Low, .claudeOpus47Medium, .claudeOpus47High, .claudeOpus47XHigh, .claudeOpus47Max,
        .claudeSonnet46, .claudeHaiku45,
        .gpt55Low, .gpt55Medium, .gpt55High, .gpt55XHigh,
        .gemini25Pro,
    ]

    static func models(for provider: AIProvider) -> [AIModel] {
        all.filter { $0.provider == provider }
    }

    static func model(withID id: String) -> AIModel? {
        if ["gpt-5.5", "gpt-4.1", "gpt-4.1-mini"].contains(id) {
            return .gpt55Medium
        }
        if ["claude-opus-4", "claude-opus-4.7", "claude-opus-4-7"].contains(id) {
            return .claudeOpus47High
        }
        if ["claude-sonnet-4.5", "claude-sonnet-4-5", "claude-sonnet-4-5-20250929", "claude-sonnet-4-6"].contains(id) {
            return .claudeSonnet46
        }
        if ["claude-haiku-4.5", "claude-haiku-4-5", "claude-haiku-4-5-20251001"].contains(id) {
            return .claudeHaiku45
        }
        return all.first { $0.id == id }
    }
}
