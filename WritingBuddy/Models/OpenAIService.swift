import Foundation

enum AIWritingServiceError: LocalizedError {
    case invalidResponse
    case unsupportedProvider(AIProvider)
    case apiError(String)
    case missingOutput

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
        formats: Set<OutputFormat>,
        model: AIModel,
        apiKey: String
    ) async throws -> [OutputBlock] {
        let prompt = SubmitPrompt(
            model: model,
            operation: operation,
            formats: formats,
            input: input,
            context: context,
            customInstructions: customInstructions,
            inputImages: inputImages,
            contextImages: contextImages
        )

        let text: String
        switch model.provider {
        case .openai:
            text = try await OpenAIService.submit(prompt: prompt, apiKey: apiKey)
        case .anthropic:
            text = try await AnthropicService.submit(prompt: prompt, apiKey: apiKey)
        case .google:
            throw AIWritingServiceError.unsupportedProvider(model.provider)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIWritingServiceError.missingOutput
        }

        let blocks = MarkdownOutputParser.parse(trimmed)
        guard !blocks.isEmpty else {
            throw AIWritingServiceError.missingOutput
        }

        return blocks
    }
}

private enum OpenAIService {
    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    static func submit(prompt: SubmitPrompt, apiKey: String) async throws -> String {
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

        return try JSONDecoder().decode(OpenAIResponseBody.self, from: data).outputText
    }
}

private enum AnthropicService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    static func submit(prompt: SubmitPrompt, apiKey: String) async throws -> String {
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

        return try JSONDecoder().decode(AnthropicResponseBody.self, from: data).outputText
    }
}

private struct SubmitPrompt {
    let model: AIModel
    let input: String
    let instructions: String
    let inputImages: [AttachedImage]
    let contextImages: [AttachedImage]

    var hasImages: Bool { !inputImages.isEmpty || !contextImages.isEmpty }

    init(
        model: AIModel,
        operation: Operation,
        formats: Set<OutputFormat>,
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
            OutputFormat.guidance(for: formats),
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
        - Never use em dashes (—, U+2014) in the output. This applies to all prose, bullets, headings, table cells, and any other generated text.
        - Do not substitute en dashes (–) for em dashes either. Rewrite the sentence using a comma, semicolon, colon, parentheses, or two shorter sentences instead.
        """)

        self.instructions = sections.joined(separator: "\n\n")
    }
}

private struct OpenAISubmitRequest: Encodable {
    let model: String
    let reasoning: Reasoning?
    let instructions: String
    let input: OpenAIInput

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
    }
}

private enum OpenAIInput: Encodable {
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

private struct OpenAIInputItem: Encodable {
    let role: String
    let content: [OpenAIInputContent]
}

private enum OpenAIInputContent: Encodable {
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

private struct Reasoning: Encodable {
    let effort: String
}

private struct AnthropicSubmitRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let thinking: AnthropicThinking?
    let outputConfig: AnthropicOutputConfig?
    let messages: [AnthropicMessage]

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case thinking
        case outputConfig = "output_config"
        case messages
    }

    init(prompt: SubmitPrompt) {
        self.model = prompt.model.apiModelID
        self.maxTokens = prompt.model.anthropicMaxTokens
        self.system = prompt.instructions
        if prompt.model.provider == .anthropic,
           let effort = prompt.model.reasoningEffort {
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
    }
}

private struct AnthropicThinking: Encodable {
    let type: String
}

private struct AnthropicOutputConfig: Encodable {
    let effort: String
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: AnthropicMessageContent
}

private enum AnthropicMessageContent: Encodable {
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

private enum AnthropicContentBlock: Encodable {
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

private struct OpenAIResponseBody: Decodable {
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

private struct OutputItem: Decodable {
    let content: [OutputContent]

    private enum CodingKeys: String, CodingKey {
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = (try? container.decode([OutputContent].self, forKey: .content)) ?? []
    }
}

private struct OutputContent: Decodable {
    let type: String
    let text: String?
}

private struct AnthropicResponseBody: Decodable {
    let content: [AnthropicOutputContent]

    var outputText: String {
        content
            .compactMap { content -> String? in
                guard content.type == "text" else { return nil }
                return content.text
            }
            .joined(separator: "\n")
    }
}

private struct AnthropicOutputContent: Decodable {
    let type: String
    let text: String?
}

private struct APIErrorResponse: Decodable {
    let error: APIError
}

private struct APIError: Decodable {
    let message: String
}

private enum MarkdownOutputParser {
    static func parse(_ text: String) -> [OutputBlock] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [OutputBlock] = []
        var paragraphLines: [String] = []
        var bulletItems: [String] = []
        var index = 0

        func flushParagraph() {
            let paragraph = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !paragraph.isEmpty {
                blocks.append(.paragraph(text: paragraph))
            }
            paragraphLines = []
        }

        func flushBullets() {
            if !bulletItems.isEmpty {
                blocks.append(.bulletList(items: bulletItems))
            }
            bulletItems = []
        }

        while index < lines.count {
            let rawLine = lines[index]
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                flushParagraph()
                flushBullets()
                index += 1
                continue
            }

            if let fence = parseFence(lines: lines, start: index) {
                flushParagraph()
                flushBullets()
                blocks.append(.codeBlock(language: fence.language, code: fence.code))
                index = fence.nextIndex
                continue
            }

            if let table = parseTable(lines: lines, start: index) {
                flushParagraph()
                flushBullets()
                blocks.append(.table(head: table.head, rows: table.rows))
                index = table.nextIndex
                continue
            }

            if let heading = parseHeading(line) {
                flushParagraph()
                flushBullets()
                blocks.append(.heading(text: heading))
                index += 1
                continue
            }

            if let bullet = parseBullet(line) {
                flushParagraph()
                bulletItems.append(bullet)
                index += 1
                continue
            }

            flushBullets()
            paragraphLines.append(line)
            index += 1
        }

        flushParagraph()
        flushBullets()

        return blocks
    }

    private static func parseFence(lines: [String], start: Int) -> (language: String?, code: String, nextIndex: Int)? {
        let opener = lines[start].trimmingCharacters(in: .whitespacesAndNewlines)
        guard opener.hasPrefix("```") else { return nil }

        let afterTicks = opener.drop { $0 == "`" }
        let langRaw = afterTicks.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = langRaw.isEmpty ? nil : langRaw

        var codeLines: [String] = []
        var index = start + 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("```"), trimmed.allSatisfy({ $0 == "`" }) {
                return (language, codeLines.joined(separator: "\n"), index + 1)
            }
            codeLines.append(lines[index])
            index += 1
        }

        // Unclosed fence — return what we captured so content isn't dropped.
        return (language, codeLines.joined(separator: "\n"), index)
    }

    private static func parseHeading(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let title = line.drop { $0 == "#" || $0 == " " }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func parseBullet(_ line: String) -> String? {
        let markers = ["- ", "* ", "\u{2022} "]
        guard let marker = markers.first(where: { line.hasPrefix($0) }) else {
            return nil
        }

        let item = String(line.dropFirst(marker.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return item.isEmpty ? nil : item
    }

    private static func parseTable(lines: [String], start: Int) -> (head: [String], rows: [[String]], nextIndex: Int)? {
        guard start + 1 < lines.count else { return nil }

        let headerLine = lines[start].trimmingCharacters(in: .whitespacesAndNewlines)
        let separatorLine = lines[start + 1].trimmingCharacters(in: .whitespacesAndNewlines)

        guard headerLine.contains("|"),
              isTableSeparator(separatorLine) else {
            return nil
        }

        let head = tableCells(from: headerLine)
        guard !head.isEmpty else { return nil }

        var rows: [[String]] = []
        var index = start + 2

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.contains("|"), !line.isEmpty else { break }

            let cells = tableCells(from: line)
            if !cells.isEmpty {
                rows.append(normalizedRow(cells, width: head.count))
            }
            index += 1
        }

        guard !rows.isEmpty else { return nil }
        return (head, rows, index)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard line.contains("|") else { return false }
        let cells = tableCells(from: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.replacingOccurrences(of: ":", with: "")
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }

    private static func tableCells(from line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }

        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func normalizedRow(_ row: [String], width: Int) -> [String] {
        if row.count == width { return row }
        if row.count > width { return Array(row.prefix(width)) }
        return row + Array(repeating: "", count: width - row.count)
    }
}
