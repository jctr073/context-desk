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

    var getKeyURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai:    return URL(string: "https://platform.openai.com/api-keys")!
        case .google:    return URL(string: "https://aistudio.google.com/app/apikey")!
        }
    }

    var keychainAccount: String { rawValue }
}

enum ReasoningEffort: String, Codable, Hashable {
    case low
    case medium
    case high
    case xhigh
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

    static let claudeSonnet45 = AIModel(id: "claude-sonnet-4.5", name: "Claude Sonnet 4.5", provider: .anthropic)
    static let claudeOpus4    = AIModel(id: "claude-opus-4",     name: "Claude Opus 4",     provider: .anthropic)
    static let claudeHaiku45  = AIModel(id: "claude-haiku-4.5",  name: "Claude Haiku 4.5",  provider: .anthropic)
    static let gpt55Low       = AIModel(id: "gpt-5.5-low",       name: "GPT-5.5 Low",       provider: .openai, apiModelID: "gpt-5.5", reasoningEffort: .low)
    static let gpt55Medium    = AIModel(id: "gpt-5.5-medium",    name: "GPT-5.5 Medium",    provider: .openai, apiModelID: "gpt-5.5", reasoningEffort: .medium)
    static let gpt55High      = AIModel(id: "gpt-5.5-high",      name: "GPT-5.5 High",      provider: .openai, apiModelID: "gpt-5.5", reasoningEffort: .high)
    static let gpt55XHigh     = AIModel(id: "gpt-5.5-xhigh",     name: "GPT-5.5 xhigh",     provider: .openai, apiModelID: "gpt-5.5", reasoningEffort: .xhigh)
    static let gemini25Pro    = AIModel(id: "gemini-2.5-pro",    name: "Gemini 2.5 Pro",    provider: .google)

    static let all: [AIModel] = [
        .claudeSonnet45, .claudeOpus4, .claudeHaiku45,
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
        return all.first { $0.id == id }
    }
}
