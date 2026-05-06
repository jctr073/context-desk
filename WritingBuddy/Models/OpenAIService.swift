import Foundation

enum AIWritingServiceError: LocalizedError {
    case invalidResponse
    case unsupportedProvider(AIProvider)
    case apiError(String)
    case missingOutput
    case invalidStructuredOutput(underlying: Error)
    case emptyBlocks

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The AI provider returned an invalid response."
        case .unsupportedProvider(let provider):
            return "\(provider.keyLabel) is not wired up for live requests yet."
        case .apiError(let message):
            return message
        case .missingOutput:
            return "The AI provider did not return any improved text."
        case .invalidStructuredOutput:
            return "The AI provider returned output we couldn't parse. Try again, or switch models."
        case .emptyBlocks:
            return "The AI provider returned an empty response."
        }
    }
}

enum AIWritingService {
    static func supports(_ provider: AIProvider) -> Bool {
        switch provider {
        case .anthropic, .openai:
            return true
        case .google:
            return false
        }
    }

    static func submit(
        input: String,
        context: String = "",
        customInstructions: String = "",
        inputImages: [AttachedImage] = [],
        contextImages: [AttachedImage] = [],
        operation: Operation,
        model: AIModel,
        apiKey: String
    ) async throws -> [OutputBlock] {
        let prompt = SubmitPrompt(
            model: model,
            operation: operation,
            input: input,
            context: context,
            customInstructions: customInstructions,
            inputImages: inputImages,
            contextImages: contextImages
        )

        let blocks: [OutputBlock]
        switch model.provider {
        case .openai:
            blocks = try await OpenAIService.submit(prompt: prompt, apiKey: apiKey)
        case .anthropic:
            blocks = try await AnthropicService.submit(prompt: prompt, apiKey: apiKey)
        case .google:
            throw AIWritingServiceError.unsupportedProvider(model.provider)
        }

        guard !blocks.isEmpty else {
            throw AIWritingServiceError.emptyBlocks
        }

        return blocks
    }
}

enum OpenAIService {
    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    static func submit(prompt: SubmitPrompt, apiKey: String) async throws -> [OutputBlock] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAISubmitRequest(prompt: prompt))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIWritingServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? "OpenAI request failed with status \(httpResponse.statusCode)."
            throw AIWritingServiceError.apiError(message)
        }

        return try decodeBlocks(from: data)
    }

    static func decodeBlocks(from data: Data) throws -> [OutputBlock] {
        let body = try JSONDecoder().decode(OpenAIResponseBody.self, from: data)
        let text = body.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AIWritingServiceError.missingOutput
        }

        do {
            let structured = try JSONDecoder().decode(StructuredOutput.self, from: Data(text.utf8))
            return structured.blocks
        } catch {
            throw AIWritingServiceError.invalidStructuredOutput(underlying: error)
        }
    }
}

enum AnthropicService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    static func submit(prompt: SubmitPrompt, apiKey: String) async throws -> [OutputBlock] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AnthropicSubmitRequest(prompt: prompt))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIWritingServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            let message = errorResponse?.error.message ?? "Anthropic request failed with status \(httpResponse.statusCode)."
            throw AIWritingServiceError.apiError(message)
        }

        return try decodeBlocks(from: data)
    }

    static func decodeBlocks(from data: Data) throws -> [OutputBlock] {
        let body = try JSONDecoder().decode(AnthropicResponseBody.self, from: data)
        guard let toolBlock = body.content.first(where: { $0.type == "tool_use" }) else {
            throw AIWritingServiceError.missingOutput
        }
        guard let structured = toolBlock.input else {
            throw AIWritingServiceError.invalidStructuredOutput(
                underlying: DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "tool_use block missing structured input")
                )
            )
        }
        return structured.blocks
    }
}

struct SubmitPrompt {
    let model: AIModel
    let input: String
    let instructions: String
    let inputImages: [AttachedImage]
    let contextImages: [AttachedImage]

    var hasImages: Bool { !inputImages.isEmpty || !contextImages.isEmpty }

    init(
        model: AIModel,
        operation: Operation,
        input: String,
        context: String,
        customInstructions: String,
        inputImages: [AttachedImage] = [],
        contextImages: [AttachedImage] = []
    ) {
        self.model = model
        self.input = input
        self.inputImages = inputImages
        self.contextImages = contextImages

        var sections: [String] = [
            operation.instructions,
        ]

        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContext.isEmpty {
            sections.append("""
            Reference context (use as supporting material — do not rewrite it directly). Treat it as examples to emulate, additional details to weave in, or background to draw on so the rewrite is richer, more accurate, and better aligned in tone, voice, and audience:
            \(trimmedContext)
            """)
        }

        let trimmedCustom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            sections.append("""
            Custom direction from the user — treat this as an additional op in their own words, on top of the named operation above. Apply it together with that operation's treatment to shape how the rewrite is approached:
            \(trimmedCustom)
            """)
        }

        if !contextImages.isEmpty {
            sections.append("""
            Reference context images are attached at the start of the user message. Treat them the same way as text context: as supporting material to draw on for tone, audience, or detail — do not transcribe or describe them unless that's plainly what the user wants.
            """)
        }

        if !inputImages.isEmpty {
            sections.append("""
            Input images are attached after the context images and before the input text. Treat them as part of the input the user wants improved — visual content the user is referring to, asking about, or wants you to fold into the rewrite.
            """)
        }

        sections.append("""
        Global output rules (apply to every response, override any conflicting guidance above):
        - Always emit your final answer using the structured output schema. Do not reply with prose only — every response must populate the `blocks` array. (Anthropic providers: call the `\(StructuredOutputSchema.toolName)` tool exactly once.)
        - Never use em dashes (—, U+2014) in the output. This applies to all prose, bullets, headings, table cells, and any other generated text.
        - Do not substitute en dashes (–) for em dashes either. Rewrite the sentence using a comma, semicolon, colon, parentheses, or two shorter sentences instead.
        """)

        self.instructions = sections.joined(separator: "\n\n")
    }
}

struct OpenAISubmitRequest: Encodable {
    let model: String
    let reasoning: Reasoning?
    let instructions: String
    let input: OpenAIInput
    let text: OpenAIText

    init(prompt: SubmitPrompt) {
        self.model = prompt.model.apiModelID
        self.reasoning = prompt.model.reasoningEffort.map { Reasoning(effort: $0.rawValue) }
        self.instructions = prompt.instructions
        if prompt.hasImages {
            var parts: [OpenAIInputContent] = []
            for img in prompt.contextImages {
                parts.append(.image(url: img.dataURL))
            }
            for img in prompt.inputImages {
                parts.append(.image(url: img.dataURL))
            }
            let trimmedInput = prompt.input.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedInput.isEmpty {
                parts.append(.text(prompt.input))
            }
            self.input = .multimodal([
                OpenAIInputItem(role: "user", content: parts)
            ])
        } else {
            self.input = .text(prompt.input)
        }
        self.text = OpenAIText(
            format: OpenAIResponseFormat(
                name: StructuredOutputSchema.responseFormatName,
                schema: RawJSON(StructuredOutputSchema.schemaData)
            )
        )
    }
}

struct OpenAIText: Encodable {
    let format: OpenAIResponseFormat
}

struct OpenAIResponseFormat: Encodable {
    let type = "json_schema"
    let name: String
    let schema: RawJSON
    let strict = true

    private enum CodingKeys: String, CodingKey {
        case type, name, schema, strict
    }
}

enum OpenAIInput: Encodable {
    case text(String)
    case multimodal([OpenAIInputItem])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .multimodal(let items):
            try container.encode(items)
        }
    }
}

struct OpenAIInputItem: Encodable {
    let role: String
    let content: [OpenAIInputContent]
}

enum OpenAIInputContent: Encodable {
    case text(String)
    case image(url: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try c.encode("input_text", forKey: .type)
            try c.encode(value, forKey: .text)
        case .image(let url):
            try c.encode("input_image", forKey: .type)
            try c.encode(url, forKey: .imageURL)
        }
    }
}

struct Reasoning: Encodable {
    let effort: String
}

struct AnthropicSubmitRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let thinking: AnthropicThinking?
    let outputConfig: AnthropicOutputConfig?
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]
    let toolChoice: AnthropicToolChoice

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case thinking
        case outputConfig = "output_config"
        case messages
        case tools
        case toolChoice = "tool_choice"
    }

    init(prompt: SubmitPrompt) {
        self.model = prompt.model.apiModelID
        self.maxTokens = prompt.model.anthropicMaxTokens
        self.system = prompt.instructions
        let thinkingEnabled = prompt.model.provider == .anthropic && prompt.model.reasoningEffort != nil
        if thinkingEnabled, let effort = prompt.model.reasoningEffort {
            self.thinking = AnthropicThinking(type: "adaptive")
            self.outputConfig = AnthropicOutputConfig(effort: effort.rawValue)
        } else {
            self.thinking = nil
            self.outputConfig = nil
        }
        if prompt.hasImages {
            var blocks: [AnthropicContentBlock] = []
            for img in prompt.contextImages {
                blocks.append(.image(mediaType: img.mimeType, data: img.base64))
            }
            for img in prompt.inputImages {
                blocks.append(.image(mediaType: img.mimeType, data: img.base64))
            }
            let trimmedInput = prompt.input.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedInput.isEmpty {
                blocks.append(.text(prompt.input))
            }
            self.messages = [AnthropicMessage(role: "user", content: .blocks(blocks))]
        } else {
            self.messages = [AnthropicMessage(role: "user", content: .text(prompt.input))]
        }
        self.tools = [
            AnthropicTool(
                name: StructuredOutputSchema.toolName,
                description: StructuredOutputSchema.description,
                inputSchema: RawJSON(StructuredOutputSchema.schemaData)
            )
        ]
        self.toolChoice = thinkingEnabled ? .auto : .forceAny
    }
}

struct AnthropicThinking: Encodable {
    let type: String
}

struct AnthropicOutputConfig: Encodable {
    let effort: String
}

struct AnthropicMessage: Encodable {
    let role: String
    let content: AnthropicMessageContent
}

enum AnthropicMessageContent: Encodable {
    case text(String)
    case blocks([AnthropicContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

enum AnthropicContentBlock: Encodable {
    case text(String)
    case image(mediaType: String, data: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, source
    }

    private enum SourceKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try c.encode("text", forKey: .type)
            try c.encode(value, forKey: .text)
        case .image(let mediaType, let data):
            try c.encode("image", forKey: .type)
            var source = c.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try source.encode("base64", forKey: .type)
            try source.encode(mediaType, forKey: .mediaType)
            try source.encode(data, forKey: .data)
        }
    }
}

struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let inputSchema: RawJSON

    private enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

enum AnthropicToolChoice: Encodable {
    /// Forces the model to call exactly one tool. Used when extended thinking
    /// is OFF.
    case forceAny
    /// Lets the model decide. Required when extended thinking is ON —
    /// Anthropic rejects both `tool` and `any` in that mode. Combined with
    /// an explicit prompt directive, the model still reliably calls our
    /// single tool.
    case auto

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .forceAny:
            try c.encode("any", forKey: .type)
            try c.encode(true, forKey: .disableParallelToolUse)
        case .auto:
            try c.encode("auto", forKey: .type)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case disableParallelToolUse = "disable_parallel_tool_use"
    }
}

private extension AIModel {
    var anthropicMaxTokens: Int {
        switch reasoningEffort {
        case .xhigh, .max:
            return 20_000
        case .low, .medium, .high, nil:
            return 4096
        }
    }
}

struct OpenAIResponseBody: Decodable {
    let output: [OutputItem]

    var outputText: String {
        output
            .flatMap(\.content)
            .compactMap { content -> String? in
                guard content.type == "output_text" else { return nil }
                return content.text
            }
            .joined(separator: "\n")
    }
}

struct OutputItem: Decodable {
    let content: [OutputContent]

    private enum CodingKeys: String, CodingKey {
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = (try? container.decode([OutputContent].self, forKey: .content)) ?? []
    }
}

struct OutputContent: Decodable {
    let type: String
    let text: String?
}

struct AnthropicResponseBody: Decodable {
    let content: [AnthropicOutputContent]
}

struct AnthropicOutputContent: Decodable {
    let type: String
    let text: String?
    let name: String?
    let input: StructuredOutput?
}

struct APIErrorResponse: Decodable {
    let error: APIError
}

struct APIError: Decodable {
    let message: String
}
