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
        case .invalidStructuredOutput(let underlying):
            return "The AI provider returned output we couldn't parse. Try again, or switch models.\n\nDetail: \(underlying.localizedDescription)"
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

extension AIWritingService {
    static func submitStream(
        input: String,
        context: String = "",
        customInstructions: String = "",
        inputImages: [AttachedImage] = [],
        contextImages: [AttachedImage] = [],
        operation: Operation,
        model: AIModel,
        apiKey: String
    ) -> AsyncThrowingStream<[OutputBlock], Error> {
        AsyncThrowingStream<[OutputBlock], Error> { continuation in
            let task = Task {
                let prompt = SubmitPrompt(
                    model: model,
                    operation: operation,
                    input: input,
                    context: context,
                    customInstructions: customInstructions,
                    inputImages: inputImages,
                    contextImages: contextImages
                )

                let inner: AsyncThrowingStream<[OutputBlock], Error>
                switch model.provider {
                case .openai:
                    inner = OpenAIService.submitStream(prompt: prompt, apiKey: apiKey)
                case .anthropic:
                    inner = AnthropicService.submitStream(prompt: prompt, apiKey: apiKey)
                case .google:
                    continuation.finish(throwing: AIWritingServiceError.unsupportedProvider(model.provider))
                    return
                }

                do {
                    var sawNonEmpty = false
                    for try await snapshot in inner {
                        if !snapshot.isEmpty {
                            sawNonEmpty = true
                        }
                        continuation.yield(snapshot)
                    }
                    if !sawNonEmpty {
                        continuation.finish(throwing: AIWritingServiceError.emptyBlocks)
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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
        guard let arguments = body.functionCallArguments(named: StructuredOutputSchema.toolName) else {
            throw AIWritingServiceError.missingOutput
        }
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIWritingServiceError.missingOutput
        }

        let toolBlocks = webSearchToolBlocks(from: body.output)
        do {
            let structured = try JSONDecoder().decode(StructuredOutput.self, from: Data(trimmed.utf8))
            return toolBlocks + structured.blocks
        } catch {
            throw AIWritingServiceError.invalidStructuredOutput(underlying: error)
        }
    }

    /// Walks the `output` array and produces a paired
    /// `.toolCall` + `.toolResult` block for each `web_search_call`
    /// item the model issued. Order is preserved so the chips render
    /// chronologically before the `emit_output` blocks.
    static func webSearchToolBlocks(from items: [OutputItem]) -> [OutputBlock] {
        var out: [OutputBlock] = []
        for item in items where item.type == "web_search_call" {
            let id = item.id ?? ""
            let argsJSON = item.action.flatMap(encodeJSONValueToString) ?? "{}"
            out.append(.toolCall(id: id, name: "web_search", argumentsJSON: argsJSON))
            let status = item.status ?? "completed"
            out.append(.toolResult(callID: id, content: status, isError: status != "completed"))
        }
        return out
    }

    private static func encodeJSONValueToString(_ value: JSONValue) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension OpenAIService {
    static func submitStream(prompt: SubmitPrompt, apiKey: String) -> AsyncThrowingStream<[OutputBlock], Error> {
        AsyncThrowingStream<[OutputBlock], Error> { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(OpenAISubmitRequest(prompt: prompt, stream: true))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIWritingServiceError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        var buffer = Data()
                        for try await byte in bytes {
                            buffer.append(byte)
                        }
                        let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: buffer)
                        let message = errorResponse?.error.message ?? "OpenAI request failed with status \(httpResponse.statusCode)."
                        throw AIWritingServiceError.apiError(message)
                    }

                    let events = SSEEventStream.events(from: bytes)
                    for try await snapshot in decodeStream(events: events) {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func decodeStream<S: AsyncSequence>(events: S) -> AsyncThrowingStream<[OutputBlock], Error> where S.Element == SSEEvent {
        AsyncThrowingStream<[OutputBlock], Error> { continuation in
            let task = Task {
                let parser = StreamingOutputParser()
                var lastYielded: [OutputBlock] = []
                var eventTypeCounts: [String: Int] = [:]
                // Streaming arguments arrive on `response.function_call_arguments.delta`
                // events keyed by `item_id`. Capture the id of the
                // emit_output function_call item from `output_item.added`
                // so we ignore deltas from any other tool call.
                var emitOutputItemID: String? = nil
                // Web-search-tool activity. We track each `web_search_call`
                // item and emit a `.toolCall` block immediately, then
                // append a paired `.toolResult` once the corresponding
                // `web_search_call.completed` event arrives. The combined
                // `toolBlocks + parser.snapshot` is what gets yielded.
                var toolBlocks: [OutputBlock] = []
                // Map item_id → index of its toolCall in `toolBlocks`,
                // so the matching toolResult lands right after it.
                var webSearchCallIndex: [String: Int] = [:]

                func yield() {
                    let combined = toolBlocks + parser.snapshot
                    if combined != lastYielded {
                        continuation.yield(combined)
                        lastYielded = combined
                    }
                }

                func yieldFinal() -> Bool {
                    do {
                        let final = toolBlocks + (try parser.finish())
                        if final != lastYielded {
                            continuation.yield(final)
                            lastYielded = final
                        }
                        return true
                    } catch {
                        let buf = parser.bufferDebugString
                        print("[OpenAI stream] finish() failed: \(error)")
                        print("[OpenAI stream] event counts: \(eventTypeCounts)")
                        print("[OpenAI stream] emit_output item_id: \(String(describing: emitOutputItemID))")
                        print("[OpenAI stream] buffer (\(buf.count) chars): \(buf.prefix(2000))")
                        continuation.finish(throwing: AIWritingServiceError.invalidStructuredOutput(underlying: error))
                        return false
                    }
                }

                do {
                    for try await event in events {
                        guard let payload = parseJSONObject(event.data) else {
                            eventTypeCounts["<unparsable>", default: 0] += 1
                            continue
                        }
                        let type = payload["type"] as? String ?? "<missing>"
                        eventTypeCounts[type, default: 0] += 1

                        switch type {
                        case "response.output_item.added":
                            guard let item = payload["item"] as? [String: Any] else { continue }
                            let itemType = item["type"] as? String
                            if itemType == "function_call",
                               (item["name"] as? String) == StructuredOutputSchema.toolName,
                               let id = item["id"] as? String {
                                emitOutputItemID = id
                            } else if itemType == "web_search_call",
                                      let id = item["id"] as? String {
                                let argsJSON = encodeAnyJSONToString(item["action"]) ?? "{}"
                                webSearchCallIndex[id] = toolBlocks.count
                                toolBlocks.append(.toolCall(id: id, name: "web_search", argumentsJSON: argsJSON))
                                yield()
                            }
                        case "response.web_search_call.completed":
                            if let id = payload["item_id"] as? String,
                               webSearchCallIndex[id] != nil {
                                toolBlocks.append(.toolResult(callID: id, content: "completed", isError: false))
                                yield()
                            }
                        case "response.web_search_call.failed":
                            if let id = payload["item_id"] as? String,
                               webSearchCallIndex[id] != nil {
                                toolBlocks.append(.toolResult(callID: id, content: "failed", isError: true))
                                yield()
                            }
                        case "response.function_call_arguments.delta":
                            // Only consume deltas for our emit_output item.
                            // If the API ever streams another tool's args
                            // before output_item.added (it shouldn't), we
                            // skip them rather than mixing JSON streams.
                            if let itemID = payload["item_id"] as? String,
                               emitOutputItemID != nil,
                               itemID != emitOutputItemID {
                                continue
                            }
                            guard let delta = payload["delta"] as? String else { continue }
                            parser.feed(delta)
                            yield()
                        case "response.completed":
                            if yieldFinal() {
                                continuation.finish()
                            }
                            return
                        case "response.error", "error":
                            let message = extractErrorMessage(from: payload) ?? "OpenAI streaming error."
                            print("[OpenAI stream] error event: \(message). Payload: \(payload)")
                            continuation.finish(throwing: AIWritingServiceError.apiError(message))
                            return
                        default:
                            continue
                        }
                    }

                    if yieldFinal() {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Encodes an Any value (typically a `[String: Any]` decoded from
    /// SSE event JSON) back to a stable JSON string. Used to surface
    /// the `action` object from a `web_search_call` event in the
    /// streamed `.toolCall.argumentsJSON`.
    private static func encodeAnyJSONToString(_ value: Any?) -> String? {
        guard let value = value,
              JSONSerialization.isValidJSONObject(value) || value is [Any] else {
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
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
        let toolBlocks = serverToolBlocks(from: body.content)
        guard let emitBlock = body.content.first(where: {
            $0.type == "tool_use" && $0.name == StructuredOutputSchema.toolName
        }) else {
            throw AIWritingServiceError.missingOutput
        }
        guard let structured = emitBlock.input else {
            throw AIWritingServiceError.invalidStructuredOutput(
                underlying: DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "tool_use block missing structured input")
                )
            )
        }
        return toolBlocks + structured.blocks
    }

    /// Walks the response content blocks and produces `.toolCall` /
    /// `.toolResult` `OutputBlock`s for every server-tool call (web
    /// search, web fetch). Order is preserved so chips render in the
    /// chronological order Anthropic returned them.
    static func serverToolBlocks(from content: [AnthropicOutputContent]) -> [OutputBlock] {
        var out: [OutputBlock] = []
        for item in content {
            switch item.type {
            case "server_tool_use":
                let id = item.id ?? ""
                let argsJSON = item.serverInput.flatMap(encodeJSONValueToString) ?? "{}"
                out.append(.toolCall(id: id, name: item.name ?? "", argumentsJSON: argsJSON))
            case "web_search_tool_result", "web_fetch_tool_result":
                let id = item.toolUseID ?? ""
                let resultJSON = item.resultContent.flatMap(encodeJSONValueToString) ?? "{}"
                let isError = isToolResultError(item.resultContent)
                out.append(.toolResult(callID: id, content: resultJSON, isError: isError))
            default:
                continue
            }
        }
        return out
    }

    /// Detects an error variant in a `web_*_tool_result.content` field.
    /// Anthropic encodes errors either as `{type: "*_tool_result_error", error_code: ...}`
    /// or as an object containing an `error_code` field.
    private static func isToolResultError(_ value: JSONValue?) -> Bool {
        guard case .object(let dict) = value else { return false }
        if case .string(let t) = dict["type"], t.hasSuffix("_error") { return true }
        if dict["error_code"] != nil { return true }
        return false
    }

    private static func encodeJSONValueToString(_ value: JSONValue) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension AnthropicService {
    static func submitStream(prompt: SubmitPrompt, apiKey: String) -> AsyncThrowingStream<[OutputBlock], Error> {
        AsyncThrowingStream<[OutputBlock], Error> { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(AnthropicSubmitRequest(prompt: prompt, stream: true))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIWritingServiceError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        var buffer = Data()
                        for try await byte in bytes {
                            buffer.append(byte)
                        }
                        let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: buffer)
                        let message = errorResponse?.error.message ?? "Anthropic request failed with status \(httpResponse.statusCode)."
                        throw AIWritingServiceError.apiError(message)
                    }

                    let events = SSEEventStream.events(from: bytes)
                    for try await snapshot in decodeStream(events: events) {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func decodeStream<S: AsyncSequence>(events: S) -> AsyncThrowingStream<[OutputBlock], Error> where S.Element == SSEEvent {
        AsyncThrowingStream<[OutputBlock], Error> { continuation in
            let task = Task {
                let parser = StreamingOutputParser()
                var lastYielded: [OutputBlock] = []
                var toolUseIndex: Int? = nil
                var didFinalize = false
                var finalizeFailed = false
                var eventTypeCounts: [String: Int] = [:]
                var contentBlockTypes: [Int: String] = [:]
                // Server-tool activity (web_search / web_fetch). Each
                // server_tool_use content block streams its `input` via
                // `input_json_delta` events, then the matching
                // web_*_tool_result block arrives whole. We translate
                // both into `.toolCall` / `.toolResult` `OutputBlock`s
                // and prepend them to the parser's snapshot every yield.
                var toolBlocks: [OutputBlock] = []
                // content_block index → position in `toolBlocks` of the
                // .toolCall we appended for that server_tool_use.
                var serverCallSlot: [Int: Int] = [:]
                // content_block index → tool-use id for matching
                // web_*_tool_result blocks back to their call.
                var serverCallID: [Int: String] = [:]
                // content_block index → in-progress argumentsJSON for
                // a server_tool_use (rebuilt as deltas arrive).
                var serverCallArgs: [Int: String] = [:]
                // content_block index → name for a server_tool_use,
                // captured at content_block_start.
                var serverCallName: [Int: String] = [:]

                func yield() {
                    let combined = toolBlocks + parser.snapshot
                    if combined != lastYielded {
                        continuation.yield(combined)
                        lastYielded = combined
                    }
                }

                func finalizeOnce() {
                    guard !didFinalize else { return }
                    didFinalize = true
                    do {
                        let final = toolBlocks + (try parser.finish())
                        if final != lastYielded {
                            continuation.yield(final)
                            lastYielded = final
                        }
                    } catch {
                        finalizeFailed = true
                        let buf = parser.bufferDebugString
                        print("[Anthropic stream] finish() failed: \(error)")
                        print("[Anthropic stream] event counts: \(eventTypeCounts)")
                        print("[Anthropic stream] content_block types by index: \(contentBlockTypes)")
                        print("[Anthropic stream] tool_use index: \(String(describing: toolUseIndex))")
                        print("[Anthropic stream] buffer (\(buf.count) chars): \(buf.prefix(2000))")
                        continuation.finish(throwing: AIWritingServiceError.invalidStructuredOutput(underlying: error))
                    }
                }

                do {
                    for try await event in events {
                        guard let payload = parseJSONObject(event.data) else {
                            eventTypeCounts["<unparsable>", default: 0] += 1
                            continue
                        }
                        let type = payload["type"] as? String ?? "<missing>"
                        eventTypeCounts[type, default: 0] += 1

                        switch type {
                        case "content_block_start":
                            let idx = payload["index"] as? Int
                            if let block = payload["content_block"] as? [String: Any] {
                                let blockType = (block["type"] as? String) ?? "?"
                                let blockName = (block["name"] as? String) ?? ""
                                if let i = idx {
                                    contentBlockTypes[i] = blockType + (blockName.isEmpty ? "" : "(\(blockName))")
                                }
                                if blockType == "tool_use",
                                   blockName == StructuredOutputSchema.toolName,
                                   let i = idx {
                                    toolUseIndex = i
                                } else if blockType == "server_tool_use",
                                          let i = idx,
                                          let id = block["id"] as? String {
                                    serverCallID[i] = id
                                    serverCallName[i] = blockName
                                    serverCallArgs[i] = ""
                                    serverCallSlot[i] = toolBlocks.count
                                    toolBlocks.append(.toolCall(id: id, name: blockName, argumentsJSON: "{}"))
                                    yield()
                                } else if blockType == "web_search_tool_result" || blockType == "web_fetch_tool_result" {
                                    let toolUseID = (block["tool_use_id"] as? String) ?? ""
                                    let resultJSON = encodeAnyJSONToString(block["content"]) ?? "{}"
                                    let isError = isStreamingResultError(block["content"])
                                    toolBlocks.append(.toolResult(callID: toolUseID, content: resultJSON, isError: isError))
                                    yield()
                                }
                            }
                        case "content_block_delta":
                            guard let idx = payload["index"] as? Int,
                                  let delta = payload["delta"] as? [String: Any],
                                  (delta["type"] as? String) == "input_json_delta",
                                  let partial = delta["partial_json"] as? String else {
                                continue
                            }
                            if let target = toolUseIndex, idx == target {
                                parser.feed(partial)
                                yield()
                            } else if let slot = serverCallSlot[idx] {
                                let merged = (serverCallArgs[idx] ?? "") + partial
                                serverCallArgs[idx] = merged
                                if let id = serverCallID[idx] {
                                    let name = serverCallName[idx] ?? ""
                                    let argsJSON = merged.isEmpty ? "{}" : merged
                                    toolBlocks[slot] = .toolCall(id: id, name: name, argumentsJSON: argsJSON)
                                    yield()
                                }
                            }
                        case "content_block_stop":
                            let idx = payload["index"] as? Int
                            if let target = toolUseIndex, idx == target {
                                finalizeOnce()
                                if finalizeFailed { return }
                            }
                        case "message_stop":
                            finalizeOnce()
                            if finalizeFailed { return }
                            continuation.finish()
                            return
                        case "error":
                            let message = extractErrorMessage(from: payload) ?? "Anthropic streaming error."
                            print("[Anthropic stream] error event: \(message). Payload: \(payload)")
                            continuation.finish(throwing: AIWritingServiceError.apiError(message))
                            return
                        default:
                            continue
                        }
                    }

                    finalizeOnce()
                    if finalizeFailed { return }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Inspects a `content_block_start.content_block.content` value (an
    /// array of result objects, or a single result/error object) and
    /// returns true when it represents the `*_tool_result_error`
    /// variant.
    private static func isStreamingResultError(_ value: Any?) -> Bool {
        if let dict = value as? [String: Any] {
            if let t = dict["type"] as? String, t.hasSuffix("_error") { return true }
            if dict["error_code"] != nil { return true }
        }
        return false
    }

    /// Encodes an Any value (typically a `[String: Any]` or array of
    /// the same decoded from SSE event JSON) back to a stable JSON
    /// string. Used for both the input arguments of a server_tool_use
    /// and the content payload of a web_*_tool_result block.
    private static func encodeAnyJSONToString(_ value: Any?) -> String? {
        guard let value = value,
              JSONSerialization.isValidJSONObject(value) || value is [Any] else {
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private func parseJSONObject(_ data: String) -> [String: Any]? {
    guard let bytes = data.data(using: .utf8) else { return nil }
    let obj = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
    return obj as? [String: Any]
}

private func extractErrorMessage(from payload: [String: Any]) -> String? {
    if let err = payload["error"] as? [String: Any], let msg = err["message"] as? String {
        return msg
    }
    if let msg = payload["message"] as? String {
        return msg
    }
    return nil
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
    let tools: [OpenAITool]
    let toolChoice: OpenAIToolChoice
    let stream: Bool?

    private enum CodingKeys: String, CodingKey {
        case model, reasoning, instructions, input, tools, stream
        case toolChoice = "tool_choice"
    }

    init(prompt: SubmitPrompt, stream: Bool = false) {
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
        self.tools = [
            .function(.emitOutput()),
            .hosted(.webSearch),
        ]
        self.toolChoice = OpenAIToolChoice.function(name: StructuredOutputSchema.toolName)
        self.stream = stream ? true : nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encodeIfPresent(reasoning, forKey: .reasoning)
        try c.encode(instructions, forKey: .instructions)
        try c.encode(input, forKey: .input)
        try c.encode(tools, forKey: .tools)
        try c.encode(toolChoice, forKey: .toolChoice)
        try c.encodeIfPresent(stream, forKey: .stream)
    }
}

/// One entry in the Responses API `tools` array. A `.function` is a
/// custom function-call tool the model fills with arguments and we
/// receive in the response (e.g., `emit_output`). A `.hosted` is a
/// provider-executed tool whose registration is just a type tag plus
/// optional knobs (e.g., `web_search`); the model invokes it
/// autonomously and OpenAI runs it server-side.
enum OpenAITool: Encodable {
    case function(OpenAIFunctionTool)
    case hosted(OpenAIHostedTool)

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .function(let f): try c.encode(f)
        case .hosted(let h):   try c.encode(h)
        }
    }
}

struct OpenAIFunctionTool: Encodable {
    let name: String
    let description: String
    let parameters: RawJSON
    let strict: Bool

    private enum CodingKeys: String, CodingKey {
        case type, name, description, parameters, strict
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("function", forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(parameters, forKey: .parameters)
        try c.encode(strict, forKey: .strict)
    }

    static func emitOutput() -> OpenAIFunctionTool {
        OpenAIFunctionTool(
            name: StructuredOutputSchema.toolName,
            description: StructuredOutputSchema.description,
            parameters: RawJSON(StructuredOutputSchema.schemaData),
            strict: true
        )
    }
}

/// Server-executed tool registration. OpenAI runs the tool itself and
/// surfaces activity as `web_search_call` output items + dedicated
/// streaming events. Optional knobs are omitted when nil.
struct OpenAIHostedTool: Encodable {
    let type: String
    let allowedDomains: [String]?
    let blockedDomains: [String]?

    private enum CodingKeys: String, CodingKey {
        case type
        case allowedDomains = "allowed_domains"
        case blockedDomains = "blocked_domains"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(allowedDomains, forKey: .allowedDomains)
        try c.encodeIfPresent(blockedDomains, forKey: .blockedDomains)
    }

    static let webSearch = OpenAIHostedTool(
        type: "web_search",
        allowedDomains: nil,
        blockedDomains: nil
    )
}

/// Forces the Responses API to call a specific function tool. Per
/// OpenAI's docs the hosted `web_search` tool still executes
/// autonomously when this is set, so we keep it pinned to
/// `emit_output` even with hosted tools registered.
enum OpenAIToolChoice: Encodable {
    case function(name: String)

    private enum CodingKeys: String, CodingKey {
        case type, name
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .function(let name):
            try c.encode("function", forKey: .type)
            try c.encode(name, forKey: .name)
        }
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
    case outputText(String)
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
        case .outputText(let value):
            try c.encode("output_text", forKey: .type)
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
    let tools: [AnthropicToolEntry]
    let toolChoice: AnthropicToolChoice
    let stream: Bool?

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case thinking
        case outputConfig = "output_config"
        case messages
        case tools
        case toolChoice = "tool_choice"
        case stream
    }

    init(prompt: SubmitPrompt, stream: Bool = false) {
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
            .custom(
                AnthropicTool(
                    name: StructuredOutputSchema.toolName,
                    description: StructuredOutputSchema.description,
                    inputSchema: RawJSON(StructuredOutputSchema.schemaData)
                )
            ),
            .server(.webSearch),
            .server(.webFetch),
        ]
        self.toolChoice = thinkingEnabled
            ? .auto
            : .tool(name: StructuredOutputSchema.toolName)
        self.stream = stream ? true : nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(maxTokens, forKey: .maxTokens)
        try c.encode(system, forKey: .system)
        try c.encodeIfPresent(thinking, forKey: .thinking)
        try c.encodeIfPresent(outputConfig, forKey: .outputConfig)
        try c.encode(messages, forKey: .messages)
        try c.encode(tools, forKey: .tools)
        try c.encode(toolChoice, forKey: .toolChoice)
        try c.encodeIfPresent(stream, forKey: .stream)
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
    /// A model-issued tool call. `input` is the parsed argument object.
    case toolUse(id: String, name: String, input: RawJSON)
    /// The tool's response, sent back on a `user` role message.
    case toolResult(toolUseID: String, content: String, isError: Bool)

    private enum CodingKeys: String, CodingKey {
        case type, text, source
        case id, name, input
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
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
        case .toolUse(let id, let name, let input):
            try c.encode("tool_use", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name)
            try c.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let content, let isError):
            try c.encode("tool_result", forKey: .type)
            try c.encode(toolUseID, forKey: .toolUseID)
            try c.encode(content, forKey: .content)
            try c.encode(isError, forKey: .isError)
        }
    }
}

/// One entry in the Anthropic Messages API `tools` array. A `.custom`
/// tool is a function-style tool we define (e.g., `emit_output`); a
/// `.server` tool is provider-executed (e.g., `web_search_20260209`).
/// The two have different wire shapes — only `.server` carries a
/// `type` discriminator on the request side.
enum AnthropicToolEntry: Encodable {
    case custom(AnthropicTool)
    case server(AnthropicServerTool)

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .custom(let t): try c.encode(t)
        case .server(let s): try c.encode(s)
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

/// Server-executed tool registration. Anthropic runs the tool itself
/// and surfaces activity as `server_tool_use` content blocks plus
/// dedicated `web_search_tool_result` / `web_fetch_tool_result`
/// blocks.
struct AnthropicServerTool: Encodable {
    let type: String
    let name: String
    let maxUses: Int?

    private enum CodingKeys: String, CodingKey {
        case type, name
        case maxUses = "max_uses"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(maxUses, forKey: .maxUses)
    }

    static let webSearch = AnthropicServerTool(
        type: "web_search_20260209",
        name: "web_search",
        maxUses: 5
    )
    static let webFetch = AnthropicServerTool(
        type: "web_fetch_20260209",
        name: "web_fetch",
        maxUses: 5
    )
}

enum AnthropicToolChoice: Encodable {
    /// Forces the model to call exactly one tool, picked freely.
    /// Pre-prep behavior — kept for completeness; current code
    /// uses `.tool(name:)` instead so the model is pinned to
    /// `emit_output` while still allowing server tools to fire.
    case forceAny
    /// Forces the model to call a specific custom tool by name.
    /// Server tools (web_search/web_fetch) execute autonomously
    /// alongside this — Anthropic's hosted tools don't honour
    /// `tool_choice`.
    case tool(name: String)
    /// Lets the model decide. Required when extended thinking is ON —
    /// Anthropic rejects both `tool` and `any` in that mode. Combined
    /// with an explicit prompt directive, the model still reliably
    /// calls our `emit_output` tool.
    case auto

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .forceAny:
            try c.encode("any", forKey: .type)
            try c.encode(true, forKey: .disableParallelToolUse)
        case .tool(let name):
            try c.encode("tool", forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encode(true, forKey: .disableParallelToolUse)
        case .auto:
            try c.encode("auto", forKey: .type)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case name
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

    /// Concatenated `output_text` content, kept for legacy decoders/tests
    /// that still inspect plain output. Not used by `decodeBlocks` once the
    /// emit_output function call is in play.
    var outputText: String {
        output
            .flatMap(\.content)
            .compactMap { content -> String? in
                guard content.type == "output_text" else { return nil }
                return content.text
            }
            .joined(separator: "\n")
    }

    /// Returns the `arguments` JSON string of the first `function_call`
    /// output item whose `name` matches. Used to extract the structured
    /// output from a forced-function-call response.
    func functionCallArguments(named toolName: String) -> String? {
        output
            .first(where: { $0.type == "function_call" && $0.name == toolName })?
            .arguments
    }
}

struct OutputItem: Decodable {
    /// `"message"` for legacy text output, `"function_call"` for a custom
    /// tool invocation, or `"web_search_call"` for the hosted web tool.
    let type: String?
    let content: [OutputContent]
    /// Stable id of the output item. For `web_search_call` items it's
    /// the `ws_...` id we use as the toolCall callID.
    let id: String?
    /// Set on `function_call` items.
    let name: String?
    let arguments: String?
    let callID: String?
    /// Set on `web_search_call` items.
    let status: String?
    /// The `action` object on a `web_search_call` item — shape depends
    /// on `action.type` (`search`, `open_page`, `find_in_page`).
    /// Captured as a generic JSON value so we can re-encode it for
    /// display in the toolCall chip.
    let action: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case type, content, id, name, arguments, status, action
        case callID = "call_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.content = (try? container.decode([OutputContent].self, forKey: .content)) ?? []
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.arguments = try container.decodeIfPresent(String.self, forKey: .arguments)
        self.callID = try container.decodeIfPresent(String.self, forKey: .callID)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.action = try container.decodeIfPresent(JSONValue.self, forKey: .action)
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
    /// Block type: `text`, `tool_use`, `server_tool_use`,
    /// `web_search_tool_result`, `web_fetch_tool_result`, or other.
    let type: String
    /// Text-block payload.
    let text: String?
    /// `tool_use` / `server_tool_use` fields.
    let id: String?
    let name: String?
    /// `tool_use` (emit_output) parsed as our structured output. `try?`-decoded
    /// so a server tool's differently-shaped `input` doesn't blow up the body.
    let input: StructuredOutput?
    /// Same `input` field captured as raw JSON, used to surface the
    /// arguments of `server_tool_use` blocks (e.g., `{"query": "..."}`).
    let serverInput: JSONValue?
    /// `web_*_tool_result` cross-reference.
    let toolUseID: String?
    /// `web_*_tool_result.content` — either an array of result objects
    /// (search) or a single result/error object (fetch / error).
    let resultContent: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseID = "tool_use_id"
        case resultContent = "content"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(String.self, forKey: .type)
        self.text = try c.decodeIfPresent(String.self, forKey: .text)
        self.id = try c.decodeIfPresent(String.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        // `input` may be either our typed StructuredOutput (for emit_output)
        // or a server-tool's free-form payload. Try the typed shape first;
        // capture the raw JSON regardless so server-tool calls survive.
        self.input = try? c.decodeIfPresent(StructuredOutput.self, forKey: .input)
        self.serverInput = try? c.decodeIfPresent(JSONValue.self, forKey: .input)
        self.toolUseID = try c.decodeIfPresent(String.self, forKey: .toolUseID)
        self.resultContent = try? c.decodeIfPresent(JSONValue.self, forKey: .resultContent)
    }
}

struct APIErrorResponse: Decodable {
    let error: APIError
}

struct APIError: Decodable {
    let message: String
}

// MARK: - Multi-turn chat

/// One turn in an outgoing chat request. The transcript ends in the latest
/// user turn and the model is asked to produce the next assistant turn.
struct ChatTurn {
    let role: MessageRole
    let text: String
    let images: [AttachedImage]

    init(role: MessageRole, text: String, images: [AttachedImage] = []) {
        self.role = role
        self.text = text
        self.images = images
    }
}

/// System prompt + transcript bundle for a chat-style submit. Mirrors the
/// shape of `SubmitPrompt` but carries an arbitrary number of turns.
struct ChatSubmitPrompt {
    let model: AIModel
    let system: String
    let turns: [ChatTurn]

    init(
        model: AIModel,
        operation: Operation,
        customInstructions: String,
        turns: [ChatTurn]
    ) {
        self.model = model
        self.turns = turns

        var sections: [String] = [operation.instructions]
        let trimmedCustom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            sections.append("""
            Custom direction from the user — applies to the whole conversation. Treat it as additional shaping on top of the named operation above:
            \(trimmedCustom)
            """)
        }
        sections.append("""
        You are in a multi-turn chat with the user. Use prior turns as context when answering the latest user message. Stay concise and stay on the user's task.
        """)
        sections.append("""
        Global output rules (apply to every response, override any conflicting guidance above):
        - Always emit your final answer using the structured output schema. Do not reply with prose only — every response must populate the `blocks` array. (Anthropic providers: call the `\(StructuredOutputSchema.toolName)` tool exactly once.)
        - Never use em dashes (—, U+2014) in the output. This applies to all prose, bullets, headings, table cells, and any other generated text.
        - Do not substitute en dashes (–) for em dashes either. Rewrite the sentence using a comma, semicolon, colon, parentheses, or two shorter sentences instead.
        """)
        self.system = sections.joined(separator: "\n\n")
    }
}

extension AIWritingService {
    static func submitChatStream(
        turns: [ChatTurn],
        operation: Operation,
        customInstructions: String = "",
        model: AIModel,
        apiKey: String
    ) -> AsyncThrowingStream<[OutputBlock], Error> {
        AsyncThrowingStream<[OutputBlock], Error> { continuation in
            let task = Task {
                let prompt = ChatSubmitPrompt(
                    model: model,
                    operation: operation,
                    customInstructions: customInstructions,
                    turns: turns
                )

                let inner: AsyncThrowingStream<[OutputBlock], Error>
                switch model.provider {
                case .openai:
                    inner = OpenAIService.submitChatStream(prompt: prompt, apiKey: apiKey)
                case .anthropic:
                    inner = AnthropicService.submitChatStream(prompt: prompt, apiKey: apiKey)
                case .google:
                    continuation.finish(throwing: AIWritingServiceError.unsupportedProvider(model.provider))
                    return
                }

                do {
                    var sawNonEmpty = false
                    for try await snapshot in inner {
                        if !snapshot.isEmpty { sawNonEmpty = true }
                        continuation.yield(snapshot)
                    }
                    if !sawNonEmpty {
                        continuation.finish(throwing: AIWritingServiceError.emptyBlocks)
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension OpenAIService {
    static func submitChatStream(prompt: ChatSubmitPrompt, apiKey: String) -> AsyncThrowingStream<[OutputBlock], Error> {
        AsyncThrowingStream<[OutputBlock], Error> { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(OpenAIChatRequest(prompt: prompt, stream: true))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIWritingServiceError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        var buffer = Data()
                        for try await byte in bytes { buffer.append(byte) }
                        let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: buffer)
                        let message = errorResponse?.error.message ?? "OpenAI request failed with status \(httpResponse.statusCode)."
                        throw AIWritingServiceError.apiError(message)
                    }

                    let events = SSEEventStream.events(from: bytes)
                    for try await snapshot in decodeStream(events: events) {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension AnthropicService {
    static func submitChatStream(prompt: ChatSubmitPrompt, apiKey: String) -> AsyncThrowingStream<[OutputBlock], Error> {
        AsyncThrowingStream<[OutputBlock], Error> { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(AnthropicChatRequest(prompt: prompt, stream: true))

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIWritingServiceError.invalidResponse
                    }
                    guard (200..<300).contains(httpResponse.statusCode) else {
                        var buffer = Data()
                        for try await byte in bytes { buffer.append(byte) }
                        let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: buffer)
                        let message = errorResponse?.error.message ?? "Anthropic request failed with status \(httpResponse.statusCode)."
                        throw AIWritingServiceError.apiError(message)
                    }

                    let events = SSEEventStream.events(from: bytes)
                    for try await snapshot in decodeStream(events: events) {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Multi-turn request bodies

struct OpenAIChatRequest: Encodable {
    let model: String
    let reasoning: Reasoning?
    let instructions: String
    let input: [OpenAIInputItem]
    let tools: [OpenAITool]
    let toolChoice: OpenAIToolChoice
    let stream: Bool?

    private enum CodingKeys: String, CodingKey {
        case model, reasoning, instructions, input, tools, stream
        case toolChoice = "tool_choice"
    }

    init(prompt: ChatSubmitPrompt, stream: Bool = false) {
        self.model = prompt.model.apiModelID
        self.reasoning = prompt.model.reasoningEffort.map { Reasoning(effort: $0.rawValue) }
        self.instructions = prompt.system
        self.input = prompt.turns.compactMap { turn in
            var parts: [OpenAIInputContent] = []
            // Image inputs are only valid on user turns in the Responses API.
            if turn.role == .user {
                for img in turn.images {
                    parts.append(.image(url: img.dataURL))
                }
            }
            let trimmed = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Assistant turns must always include text; user turns may be image-only.
            if !trimmed.isEmpty {
                if turn.role == .assistant {
                    parts.append(.outputText(turn.text))
                } else {
                    parts.append(.text(turn.text))
                }
            } else if turn.role == .assistant {
                return nil
            }
            return OpenAIInputItem(
                role: turn.role == .user ? "user" : "assistant",
                content: parts
            )
        }
        self.tools = [
            .function(.emitOutput()),
            .hosted(.webSearch),
        ]
        self.toolChoice = OpenAIToolChoice.function(name: StructuredOutputSchema.toolName)
        self.stream = stream ? true : nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encodeIfPresent(reasoning, forKey: .reasoning)
        try c.encode(instructions, forKey: .instructions)
        try c.encode(input, forKey: .input)
        try c.encode(tools, forKey: .tools)
        try c.encode(toolChoice, forKey: .toolChoice)
        try c.encodeIfPresent(stream, forKey: .stream)
    }
}

struct AnthropicChatRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let thinking: AnthropicThinking?
    let outputConfig: AnthropicOutputConfig?
    let messages: [AnthropicMessage]
    let tools: [AnthropicToolEntry]
    let toolChoice: AnthropicToolChoice
    let stream: Bool?

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case thinking
        case outputConfig = "output_config"
        case messages
        case tools
        case toolChoice = "tool_choice"
        case stream
    }

    init(prompt: ChatSubmitPrompt, stream: Bool = false) {
        self.model = prompt.model.apiModelID
        self.maxTokens = prompt.model.anthropicChatMaxTokens
        self.system = prompt.system
        let thinkingEnabled = prompt.model.provider == .anthropic && prompt.model.reasoningEffort != nil
        if thinkingEnabled, let effort = prompt.model.reasoningEffort {
            self.thinking = AnthropicThinking(type: "adaptive")
            self.outputConfig = AnthropicOutputConfig(effort: effort.rawValue)
        } else {
            self.thinking = nil
            self.outputConfig = nil
        }
        self.messages = prompt.turns.compactMap { turn in
            let trimmed = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if turn.images.isEmpty {
                guard !trimmed.isEmpty else { return nil }
                return AnthropicMessage(
                    role: turn.role == .user ? "user" : "assistant",
                    content: .text(turn.text)
                )
            }
            var blocks: [AnthropicContentBlock] = []
            for img in turn.images {
                blocks.append(.image(mediaType: img.mimeType, data: img.base64))
            }
            if !trimmed.isEmpty {
                blocks.append(.text(turn.text))
            } else if turn.role == .assistant {
                return nil
            }
            return AnthropicMessage(
                role: turn.role == .user ? "user" : "assistant",
                content: .blocks(blocks)
            )
        }
        self.tools = [
            .custom(
                AnthropicTool(
                    name: StructuredOutputSchema.toolName,
                    description: StructuredOutputSchema.description,
                    inputSchema: RawJSON(StructuredOutputSchema.schemaData)
                )
            ),
            .server(.webSearch),
            .server(.webFetch),
        ]
        self.toolChoice = thinkingEnabled
            ? .auto
            : .tool(name: StructuredOutputSchema.toolName)
        self.stream = stream ? true : nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(maxTokens, forKey: .maxTokens)
        try c.encode(system, forKey: .system)
        try c.encodeIfPresent(thinking, forKey: .thinking)
        try c.encodeIfPresent(outputConfig, forKey: .outputConfig)
        try c.encode(messages, forKey: .messages)
        try c.encode(tools, forKey: .tools)
        try c.encode(toolChoice, forKey: .toolChoice)
        try c.encodeIfPresent(stream, forKey: .stream)
    }
}

private extension AIModel {
    var anthropicChatMaxTokens: Int {
        switch reasoningEffort {
        case .xhigh, .max:
            return 20_000
        case .low, .medium, .high, nil:
            return 4096
        }
    }
}
