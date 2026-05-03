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

struct AIModel: Identifiable, Hashable {
    let id: String
    let name: String
    let provider: AIProvider

    static let claudeSonnet45 = AIModel(id: "claude-sonnet-4.5", name: "Claude Sonnet 4.5", provider: .anthropic)
    static let claudeOpus4    = AIModel(id: "claude-opus-4",     name: "Claude Opus 4",     provider: .anthropic)
    static let claudeHaiku45  = AIModel(id: "claude-haiku-4.5",  name: "Claude Haiku 4.5",  provider: .anthropic)
    static let gpt55          = AIModel(id: "gpt-5.5",           name: "GPT-5.5",           provider: .openai)
    static let gpt41          = AIModel(id: "gpt-4.1",           name: "GPT-4.1",           provider: .openai)
    static let gpt41mini      = AIModel(id: "gpt-4.1-mini",      name: "GPT-4.1 mini",      provider: .openai)
    static let gemini25Pro    = AIModel(id: "gemini-2.5-pro",    name: "Gemini 2.5 Pro",    provider: .google)

    static let all: [AIModel] = [
        .claudeSonnet45, .claudeOpus4, .claudeHaiku45,
        .gpt55, .gpt41, .gpt41mini,
        .gemini25Pro,
    ]

    static func models(for provider: AIProvider) -> [AIModel] {
        all.filter { $0.provider == provider }
    }

    static func model(withID id: String) -> AIModel? {
        all.first { $0.id == id }
    }
}
