import Foundation

/// One model discovered from a provider's `/models` endpoint. Codable so the
/// catalog cache can persist derived (unrecognized) rows.
struct DiscoveredModel: Hashable, Codable {
    let apiModelID: String
    let displayName: String?
    let provider: AIProvider
}

/// Fetches the live model list for a provider. Abstracted as a protocol so the
/// catalog can be unit-tested with a stub (no network).
protocol ModelListing {
    func fetch(provider: AIProvider, apiKey: String) async throws -> [DiscoveredModel]
}

struct ModelListingService: ModelListing {
    static let anthropicEndpoint = URL(string: "https://api.anthropic.com/v1/models")!
    static let openAIEndpoint = URL(string: "https://api.openai.com/v1/models")!

    func fetch(provider: AIProvider, apiKey: String) async throws -> [DiscoveredModel] {
        switch provider {
        case .anthropic: return try await fetchAnthropic(apiKey: apiKey)
        case .openai:    return try await fetchOpenAI(apiKey: apiKey)
        case .google:    return []   // Not wired for live requests — baseline only.
        }
    }

    private func fetchAnthropic(apiKey: String) async throws -> [DiscoveredModel] {
        var results: [DiscoveredModel] = []
        var afterID: String?
        var page = 0
        repeat {
            var components = URLComponents(url: Self.anthropicEndpoint, resolvingAgainstBaseURL: false)!
            var query = [URLQueryItem(name: "limit", value: "100")]
            if let afterID { query.append(URLQueryItem(name: "after_id", value: afterID)) }
            components.queryItems = query

            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            AnthropicService.applyDefaultHeaders(to: &request, apiKey: apiKey)

            let (data, http) = try await RetryableHTTP.send(request: request)
            guard (200..<300).contains(http.statusCode) else {
                throw AIWritingServiceError.apiError(
                    message: "Anthropic model list failed (status \(http.statusCode)).",
                    kind: APIErrorKind.classify(httpStatus: http.statusCode, providerErrorType: nil)
                )
            }

            let body = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
            results += body.data.map {
                DiscoveredModel(apiModelID: $0.id, displayName: $0.display_name, provider: .anthropic)
            }
            afterID = (body.has_more ?? false) ? body.last_id : nil
            page += 1
        } while afterID != nil && page < 10
        return results
    }

    private func fetchOpenAI(apiKey: String) async throws -> [DiscoveredModel] {
        var request = URLRequest(url: Self.openAIEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, http) = try await RetryableHTTP.send(request: request)
        guard (200..<300).contains(http.statusCode) else {
            throw AIWritingServiceError.apiError(
                message: "OpenAI model list failed (status \(http.statusCode)).",
                kind: APIErrorKind.classify(httpStatus: http.statusCode, providerErrorType: nil)
            )
        }

        let body = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return body.data.map { DiscoveredModel(apiModelID: $0.id, displayName: nil, provider: .openai) }
    }
}

private struct AnthropicModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
        let display_name: String?
    }
    let data: [Model]
    let has_more: Bool?
    let last_id: String?
}

private struct OpenAIModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

/// Maps a provider's discovered models onto the curated families: filters junk,
/// picks the latest concrete id per family (auto-versioning), and surfaces any
/// chat model that matches a provider lineage but no family as a derived row.
enum FamilyResolver {
    static func resolve(
        _ discovered: [DiscoveredModel],
        families: [ModelFamily]
    ) -> (resolved: [String: ResolvedFamily], derived: [DiscoveredModel]) {
        let chat = discovered.filter {
            ModelFamily.isLikelyChatModel(apiID: $0.apiModelID, provider: $0.provider)
        }

        var resolved: [String: ResolvedFamily] = [:]
        for family in families {
            let candidates = chat.filter { family.matches($0.apiModelID) }
            guard let best = candidates.max(by: {
                family.versionRank(of: $0.apiModelID) < family.versionRank(of: $1.apiModelID)
            }) else { continue }
            resolved[family.id] = ResolvedFamily(
                familyID: family.id,
                apiModelID: best.apiModelID,
                displayName: family.displayName(forAPIID: best.apiModelID)
            )
        }

        let derived = chat.filter { model in
            !families.contains { $0.matches(model.apiModelID) }
        }
        return (resolved, derived)
    }
}
