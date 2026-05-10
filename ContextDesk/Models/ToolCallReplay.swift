import Foundation

/// Heterogeneous input item for the OpenAI Responses API. The current
/// (pre-tools) request body uses `OpenAIInputItem` which is always a
/// role+content message. Once tool use lands, the input array must be able
/// to interleave `function_call` and `function_call_output` items between
/// messages. `OpenAIRequestInputItem` is that representation.
///
/// Not yet wired into `OpenAISubmitRequest` / `OpenAIChatRequest` — the
/// future tool branch swaps those over.
enum OpenAIRequestInputItem: Encodable {
    case message(role: String, content: [OpenAIInputContent])
    case functionCall(callID: String, name: String, argumentsJSON: String)
    case functionCallOutput(callID: String, output: String)

    private enum CodingKeys: String, CodingKey {
        case type, role, content
        case name, arguments
        case callID = "call_id"
        case output
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let role, let content):
            try c.encode("message", forKey: .type)
            try c.encode(role, forKey: .role)
            try c.encode(content, forKey: .content)
        case .functionCall(let callID, let name, let argumentsJSON):
            try c.encode("function_call", forKey: .type)
            try c.encode(callID, forKey: .callID)
            try c.encode(name, forKey: .name)
            try c.encode(argumentsJSON, forKey: .arguments)
        case .functionCallOutput(let callID, let output):
            try c.encode("function_call_output", forKey: .type)
            try c.encode(callID, forKey: .callID)
            try c.encode(output, forKey: .output)
        }
    }
}

/// Expands a single assistant `ChatMessage` (whose `blocks` may contain
/// interleaved `.toolCall` / `.toolResult` entries) into the multi-message
/// shape each provider's API expects on replay.
///
/// Unused in this branch — the system prompt still instructs the model not
/// to emit tool blocks, so every assistant message has only prose blocks
/// and the helper degrades to a single message. The future tool branch
/// calls this from the chat-request encoders to reconstruct mid-turn tool
/// activity.
enum ToolCallReplay {

    /// Convert an assistant message into a sequence of Anthropic messages.
    /// Prose blocks become `text` content. `.toolCall` blocks become
    /// `tool_use` content on the assistant side. `.toolResult` blocks
    /// become a separate `user`-role message carrying `tool_result` blocks.
    /// User and unknown blocks are passed through as text where applicable.
    static func anthropicMessages(from message: ChatMessage) -> [AnthropicMessage] {
        precondition(message.role == .assistant, "replay expects an assistant message")
        var messages: [AnthropicMessage] = []
        var assistantBlocks: [AnthropicContentBlock] = []
        var resultBlocks: [AnthropicContentBlock] = []

        func flushAssistant() {
            guard !assistantBlocks.isEmpty else { return }
            messages.append(AnthropicMessage(role: "assistant", content: .blocks(assistantBlocks)))
            assistantBlocks = []
        }
        func flushResults() {
            guard !resultBlocks.isEmpty else { return }
            messages.append(AnthropicMessage(role: "user", content: .blocks(resultBlocks)))
            resultBlocks = []
        }

        for block in message.blocks {
            switch block {
            case .toolResult(let callID, let content, let isError):
                flushAssistant()
                resultBlocks.append(.toolResult(toolUseID: callID, content: content, isError: isError))
            case .toolCall(let id, let name, let argumentsJSON):
                flushResults()
                let inputData = Data(argumentsJSON.utf8)
                assistantBlocks.append(.toolUse(id: id, name: name, input: RawJSON(inputData)))
            default:
                flushResults()
                assistantBlocks.append(.text(plainText(of: block)))
            }
        }
        flushAssistant()
        flushResults()
        return messages
    }

    /// Convert an assistant message into a sequence of Responses API input
    /// items. Prose collapses into a single assistant `message` item per
    /// run; `.toolCall` becomes `function_call`; `.toolResult` becomes
    /// `function_call_output`.
    static func openAIInputItems(from message: ChatMessage) -> [OpenAIRequestInputItem] {
        precondition(message.role == .assistant, "replay expects an assistant message")
        var items: [OpenAIRequestInputItem] = []
        var prose: [OpenAIInputContent] = []

        func flushProse() {
            guard !prose.isEmpty else { return }
            items.append(.message(role: "assistant", content: prose))
            prose = []
        }

        for block in message.blocks {
            switch block {
            case .toolCall(let id, let name, let argumentsJSON):
                flushProse()
                items.append(.functionCall(callID: id, name: name, argumentsJSON: argumentsJSON))
            case .toolResult(let callID, let content, _):
                flushProse()
                items.append(.functionCallOutput(callID: callID, output: content))
            default:
                let text = plainText(of: block)
                if !text.isEmpty {
                    prose.append(.outputText(text))
                }
            }
        }
        flushProse()
        return items
    }

    private static func plainText(of block: OutputBlock) -> String {
        switch block {
        case .paragraph(let t, _):  return t
        case .heading(let t):       return t
        case .bulletList(let it):   return it.map { "- \($0)" }.joined(separator: "\n")
        case .table(_, let rows):   return rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
        case .codeBlock(_, let c):  return c
        case .toolCall, .toolResult: return ""
        case .unknown:              return ""
        }
    }
}
