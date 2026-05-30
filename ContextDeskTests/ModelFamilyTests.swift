import XCTest
@testable import ContextDesk

final class ModelFamilyTests: XCTestCase {

    // MARK: Version ranking

    func testVersionRankingPicksHigherVersion() {
        XCTAssertTrue(
            ModelVersionRank.parse("claude-opus-4-8") > ModelVersionRank.parse("claude-opus-4-7")
        )
        XCTAssertTrue(
            ModelVersionRank.parse("gpt-5.5") > ModelVersionRank.parse("gpt-5.1")
        )
        // Minor-versioned id outranks the bare major.
        XCTAssertTrue(
            ModelVersionRank.parse("gpt-5.5") > ModelVersionRank.parse("gpt-5")
        )
    }

    func testBareAliasPreferredOverDatedSnapshot() {
        // Same version number → the bare alias is the latest (stabler to cache).
        XCTAssertTrue(
            ModelVersionRank.parse("claude-opus-4-8")
                > ModelVersionRank.parse("claude-opus-4-8-20260115")
        )
        XCTAssertTrue(
            ModelVersionRank.parse("gpt-5.5") > ModelVersionRank.parse("gpt-5.5-2025-08-07")
        )
    }

    func testSnapshotParsedOutOfVersionComponents() {
        let rank = ModelVersionRank.parse("claude-haiku-4-5-20251001")
        XCTAssertEqual(rank.components, [4, 5])
        XCTAssertEqual(rank.snapshot, 20_251_001)
    }

    // MARK: Junk filtering

    func testJunkFilterKeepsOnlyCuratedChatModels() {
        let openAIList = [
            "gpt-5.5", "gpt-5.5-2025-08-07", "gpt-4o", "gpt-4.1", "o3",
            "text-embedding-3-large", "whisper-1", "dall-e-3", "gpt-image-1",
            "tts-1", "gpt-4o-realtime-preview", "omni-moderation-latest",
        ]
        let surviving = openAIList.filter {
            ModelFamily.isLikelyChatModel(apiID: $0, provider: .openai)
        }
        XCTAssertEqual(surviving, ["gpt-5.5", "gpt-5.5-2025-08-07"])

        XCTAssertTrue(ModelFamily.isLikelyChatModel(apiID: "claude-opus-4-8", provider: .anthropic))
        XCTAssertFalse(ModelFamily.isLikelyChatModel(apiID: "voyage-embedding", provider: .anthropic))
    }

    // MARK: Auto-versioning resolution

    func testResolveAutoVersionsFamiliesAndDerivesUnknown() {
        let discovered = [
            DiscoveredModel(apiModelID: "claude-opus-4-7", displayName: nil, provider: .anthropic),
            DiscoveredModel(apiModelID: "claude-opus-4-8", displayName: nil, provider: .anthropic),
            DiscoveredModel(apiModelID: "claude-sonnet-4-6", displayName: nil, provider: .anthropic),
            DiscoveredModel(apiModelID: "claude-haiku-4-5-20251001", displayName: nil, provider: .anthropic),
            DiscoveredModel(apiModelID: "claude-neptune-1", displayName: nil, provider: .anthropic),
            DiscoveredModel(apiModelID: "voyage-embedding", displayName: nil, provider: .anthropic),
        ]
        let families = ModelFamily.bundled.filter { $0.provider == .anthropic }
        let (resolved, derived) = FamilyResolver.resolve(discovered, families: families)

        XCTAssertEqual(resolved["claude-opus"]?.apiModelID, "claude-opus-4-8")
        XCTAssertEqual(resolved["claude-opus"]?.displayName, "Claude Opus 4.8")
        XCTAssertEqual(resolved["claude-sonnet"]?.apiModelID, "claude-sonnet-4-6")

        // The unrecognized chat model becomes a derived row; junk does not.
        XCTAssertEqual(derived.map(\.apiModelID), ["claude-neptune-1"])
    }

    func testGPTDisplayNameUsesHyphenSeparator() {
        let gpt = ModelFamily.byID["gpt-5"]!
        XCTAssertEqual(gpt.displayName(forAPIID: "gpt-5.5"), "GPT-5.5")
        let opus = ModelFamily.byID["claude-opus"]!
        XCTAssertEqual(opus.displayName(forAPIID: "claude-opus-4-8"), "Claude Opus 4.8")
    }

    // MARK: Composite id round-trip + back-compat

    func testCompositeIDRoundTrip() {
        let opus = ModelFamily.byID["claude-opus"]!
        let model = opus.aiModel(effort: .high, resolved: nil)
        XCTAssertEqual(model.id, "claude-opus#high")
        XCTAssertEqual(model.reasoningEffort, .high)
        XCTAssertEqual(model.apiModelID, "claude-opus-4-7")

        let resolved = ModelFamily.resolve(id: model.id)
        XCTAssertEqual(resolved?.family.id, "claude-opus")
        XCTAssertEqual(resolved?.effort, .high)
    }

    func testLegacyVariantIDsResolve() {
        let cases: [(String, String, ReasoningEffort?, String)] = [
            ("claude-opus-4-7-high", "claude-opus#high", .high, "claude-opus-4-7"),
            ("claude-opus-4-7-xhigh", "claude-opus#xhigh", .xhigh, "claude-opus-4-7"),
            ("gpt-5.5-medium", "gpt-5#medium", .medium, "gpt-5.5"),
            ("claude-sonnet-4-6", "claude-sonnet", nil, "claude-sonnet-4-6"),
            ("claude-haiku-4-5", "claude-haiku", nil, "claude-haiku-4-5-20251001"),
            ("gemini-2.5-pro", "gemini-pro", nil, "gemini-2.5-pro"),
        ]
        for (input, expectedID, expectedEffort, expectedAPI) in cases {
            let model = AIModel.model(withID: input)
            XCTAssertNotNil(model, "expected \(input) to resolve")
            XCTAssertEqual(model?.id, expectedID, "id for \(input)")
            XCTAssertEqual(model?.reasoningEffort, expectedEffort, "effort for \(input)")
            XCTAssertEqual(model?.apiModelID, expectedAPI, "apiModelID for \(input)")
        }
    }

    func testLegacyRawAliasesResolve() {
        for alias in ["gpt-5.5", "gpt-4.1", "claude-opus-4-7", "claude-sonnet-4-5-20250929"] {
            XCTAssertNotNil(AIModel.model(withID: alias), "expected \(alias) to resolve")
        }
    }

    func testUnknownIDReturnsNil() {
        XCTAssertNil(AIModel.model(withID: "totally-made-up-model"))
    }
}
