//
//  ModelRegistryTests.swift
//  AISDKTests
//
//  Tests for ModelRegistry - centralized model management
//

import XCTest
@testable import AISDK

final class ModelRegistryTests: XCTestCase {
    // MARK: - Test Fixtures

    private func makeTestModel(
        name: String,
        provider: LLMProvider = .openai,
        category: LLMUsageCategory = .chat,
        capabilities: LLMCapabilities = [.text, .streaming],
        tier: LLMPerformanceTier? = .medium,
        aliases: [String] = [],
        inputTokenLimit: Int? = 4096
    ) -> LLMModelAdapter {
        LLMModelAdapter(
            name: name,
            description: "Test model \(name)",
            provider: provider,
            category: category,
            capabilities: capabilities,
            tier: tier,
            inputTokenLimit: inputTokenLimit,
            aliases: aliases
        )
    }

    // MARK: - Basic Registration Tests

    func test_register_single_model() async {
        let registry = ModelRegistry()
        let model = makeTestModel(name: "test-model")

        await registry.register(model: model, provider: .openai)

        let retrieved = await registry.model(named: "test-model", from: nil)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "test-model")
    }

    func test_register_model_with_explicit_provider() async {
        let registry = ModelRegistry()
        let model = makeTestModel(name: "gpt-4", provider: .openai)

        await registry.register(model: model, provider: .openai)

        // Should find by canonical ID
        let byCanonical = await registry.model(named: "openai/gpt-4", from: nil)
        XCTAssertNotNil(byCanonical)

        // Should find by bare name
        let byName = await registry.model(named: "gpt-4", from: nil)
        XCTAssertNotNil(byName)

        // Should find by provider-scoped lookup
        let byProvider = await registry.model(named: "gpt-4", from: .openai)
        XCTAssertNotNil(byProvider)
    }

    func test_register_model_with_aliases() async {
        let registry = ModelRegistry()
        let model = makeTestModel(
            name: "gpt-4-turbo",
            aliases: ["gpt-4-turbo-preview", "gpt4t"]
        )

        await registry.register(model: model, provider: .openai)

        // Should find by any alias
        let byAlias1 = await registry.model(named: "gpt-4-turbo-preview", from: nil)
        XCTAssertNotNil(byAlias1)
        XCTAssertEqual(byAlias1?.name, "gpt-4-turbo")

        let byAlias2 = await registry.model(named: "gpt4t", from: nil)
        XCTAssertNotNil(byAlias2)
        XCTAssertEqual(byAlias2?.name, "gpt-4-turbo")
    }

    func test_model_not_found_returns_nil() async {
        let registry = ModelRegistry()

        let result = await registry.model(named: "nonexistent", from: nil)
        XCTAssertNil(result)
    }

    // MARK: - Capability Query Tests

    func test_models_with_capabilities() async {
        let registry = ModelRegistry()

        let textOnly = makeTestModel(name: "text-only", capabilities: [.text])
        let vision = makeTestModel(name: "vision", capabilities: [.text, .vision])
        let tools = makeTestModel(name: "tools", capabilities: [.text, .tools])
        let multimodal = makeTestModel(name: "multimodal", capabilities: [.text, .vision, .audio, .tools])

        await registry.register(model: textOnly, provider: .openai)
        await registry.register(model: vision, provider: .openai)
        await registry.register(model: tools, provider: .openai)
        await registry.register(model: multimodal, provider: .openai)

        // Query for vision capability
        let visionModels = await registry.models(with: .vision)
        XCTAssertEqual(visionModels.count, 2)
        XCTAssertTrue(visionModels.contains { $0.name == "vision" })
        XCTAssertTrue(visionModels.contains { $0.name == "multimodal" })

        // Query for tools capability
        let toolModels = await registry.models(with: .tools)
        XCTAssertEqual(toolModels.count, 2)
        XCTAssertTrue(toolModels.contains { $0.name == "tools" })
        XCTAssertTrue(toolModels.contains { $0.name == "multimodal" })

        // Query for multiple capabilities
        let visionAndTools = await registry.models(with: [.vision, .tools])
        XCTAssertEqual(visionAndTools.count, 1)
        XCTAssertEqual(visionAndTools.first?.name, "multimodal")
    }

    func test_models_with_any_capability() async {
        let registry = ModelRegistry()

        let textOnly = makeTestModel(name: "text-only", capabilities: [.text])
        let vision = makeTestModel(name: "vision", capabilities: [.text, .vision])
        let audio = makeTestModel(name: "audio", capabilities: [.text, .audio])

        await registry.register(model: textOnly, provider: .openai)
        await registry.register(model: vision, provider: .openai)
        await registry.register(model: audio, provider: .openai)

        // Query for any of vision or audio
        let multimodal = await registry.models(withAny: [.vision, .audio])
        XCTAssertEqual(multimodal.count, 2)
        XCTAssertFalse(multimodal.contains { $0.name == "text-only" })
    }

    // MARK: - Category Query Tests

    func test_models_by_category() async {
        let registry = ModelRegistry()

        let chat = makeTestModel(name: "chat-model", category: .chat)
        let embedding = makeTestModel(name: "embed-model", category: .embedding)
        let reasoning = makeTestModel(name: "reason-model", category: .reasoning)

        await registry.register(model: chat, provider: .openai)
        await registry.register(model: embedding, provider: .openai)
        await registry.register(model: reasoning, provider: .openai)

        let chatModels = await registry.models(for: .chat)
        XCTAssertEqual(chatModels.count, 1)
        XCTAssertEqual(chatModels.first?.name, "chat-model")

        let embeddingModels = await registry.models(for: .embedding)
        XCTAssertEqual(embeddingModels.count, 1)
        XCTAssertEqual(embeddingModels.first?.name, "embed-model")
    }

    // MARK: - Tier Query Tests

    func test_models_by_minimum_tier() async {
        let registry = ModelRegistry()

        let small = makeTestModel(name: "small", tier: .small)
        let medium = makeTestModel(name: "medium", tier: .medium)
        let large = makeTestModel(name: "large", tier: .large)
        let flagship = makeTestModel(name: "flagship", tier: .flagship)

        await registry.register(model: small, provider: .openai)
        await registry.register(model: medium, provider: .openai)
        await registry.register(model: large, provider: .openai)
        await registry.register(model: flagship, provider: .openai)

        let largeOrBetter = await registry.models(minimumTier: .large)
        XCTAssertEqual(largeOrBetter.count, 2)
        XCTAssertTrue(largeOrBetter.contains { $0.name == "large" })
        XCTAssertTrue(largeOrBetter.contains { $0.name == "flagship" })
    }

    // MARK: - Context Window Query Tests

    func test_models_by_minimum_context() async {
        let registry = ModelRegistry()

        let small = makeTestModel(name: "small-context", inputTokenLimit: 4096)
        let medium = makeTestModel(name: "medium-context", inputTokenLimit: 32000)
        let large = makeTestModel(name: "large-context", inputTokenLimit: 128000)

        await registry.register(model: small, provider: .openai)
        await registry.register(model: medium, provider: .openai)
        await registry.register(model: large, provider: .openai)

        let longContext = await registry.models(withMinimumContext: 32000)
        XCTAssertEqual(longContext.count, 2)
        XCTAssertFalse(longContext.contains { $0.name == "small-context" })
    }

    // MARK: - Recommendation Tests

    func test_recommended_model_prefers_higher_tier() async {
        let registry = ModelRegistry()

        let medium = makeTestModel(
            name: "medium",
            category: .chat,
            capabilities: [.text, .tools],
            tier: .medium
        )
        let flagship = makeTestModel(
            name: "flagship",
            category: .chat,
            capabilities: [.text, .tools],
            tier: .flagship
        )

        await registry.register(model: medium, provider: .openai)
        await registry.register(model: flagship, provider: .openai)

        let recommended = await registry.recommendedModel(for: .chat, with: [.text, .tools])
        XCTAssertEqual(recommended?.name, "flagship")
    }

    func test_recommended_model_filters_by_category() async {
        let registry = ModelRegistry()

        let chat = makeTestModel(name: "chat", category: .chat, tier: .flagship)
        let embedding = makeTestModel(name: "embed", category: .embedding, tier: .flagship)

        await registry.register(model: chat, provider: .openai)
        await registry.register(model: embedding, provider: .openai)

        let recommended = await registry.recommendedModel(for: .chat, with: .text)
        XCTAssertEqual(recommended?.name, "chat")
    }

    func test_recommended_model_filters_by_capabilities() async {
        let registry = ModelRegistry()

        let noVision = makeTestModel(name: "no-vision", capabilities: [.text], tier: .flagship)
        let vision = makeTestModel(name: "vision", capabilities: [.text, .vision], tier: .large)

        await registry.register(model: noVision, provider: .openai)
        await registry.register(model: vision, provider: .openai)

        let recommended = await registry.recommendedModel(for: .chat, with: [.text, .vision])
        XCTAssertEqual(recommended?.name, "vision")
    }

    // MARK: - Unregister Tests

    func test_unregister_removes_model() async {
        let registry = ModelRegistry()
        let model = makeTestModel(name: "to-remove", aliases: ["remove-alias"])

        await registry.register(model: model, provider: .openai)

        // Verify registered
        let beforeRemove = await registry.model(named: "to-remove", from: nil)
        let beforeRemoveAlias = await registry.model(named: "remove-alias", from: nil)
        XCTAssertNotNil(beforeRemove)
        XCTAssertNotNil(beforeRemoveAlias)

        // Unregister
        await registry.unregister(modelId: "openai/to-remove")

        // Verify removed
        let afterRemove = await registry.model(named: "openai/to-remove", from: nil)
        let afterRemoveAlias = await registry.model(named: "remove-alias", from: nil)
        XCTAssertNil(afterRemove)
        XCTAssertNil(afterRemoveAlias)
    }

    // MARK: - Clear Tests

    func test_clear_removes_all() async {
        let registry = ModelRegistry()

        await registry.register(model: makeTestModel(name: "model1"), provider: .openai)
        await registry.register(model: makeTestModel(name: "model2"), provider: .anthropic)

        let statsBefore = await registry.statistics
        XCTAssertGreaterThan(statsBefore.totalModels, 0)

        await registry.clear()

        let statsAfter = await registry.statistics
        XCTAssertEqual(statsAfter.totalModels, 0)
        XCTAssertEqual(statsAfter.totalAliases, 0)
    }

    // MARK: - Statistics Tests

    func test_statistics() async {
        let registry = ModelRegistry()

        let model1 = makeTestModel(name: "model1", provider: .openai, aliases: ["alias1"])
        let model2 = makeTestModel(name: "model2", provider: .openai)
        let model3 = makeTestModel(name: "model3", provider: .anthropic, aliases: ["alias2", "alias3"])

        await registry.register(model: model1, provider: .openai)
        await registry.register(model: model2, provider: .openai)
        await registry.register(model: model3, provider: .anthropic)

        let stats = await registry.statistics
        XCTAssertEqual(stats.totalModels, 3)
        XCTAssertEqual(stats.totalAliases, 3)
        XCTAssertEqual(stats.modelsByProvider[.openai], 2)
        XCTAssertEqual(stats.modelsByProvider[.anthropic], 1)
    }

    // MARK: - Canonical ID Tests

    func test_canonical_id_for_alias() async {
        let registry = ModelRegistry()
        let model = makeTestModel(name: "real-name", aliases: ["alias"])

        await registry.register(model: model, provider: .openai)

        let canonical = await registry.canonicalId(forAlias: "alias")
        XCTAssertEqual(canonical, "openai/real-name")
    }

    func test_is_model_registered() async {
        let registry = ModelRegistry()
        let model = makeTestModel(name: "registered", aliases: ["reg-alias"])

        await registry.register(model: model, provider: .openai)

        let isRegisteredByName = await registry.isModelRegistered("registered")
        let isRegisteredByCanonical = await registry.isModelRegistered("openai/registered")
        let isRegisteredByAlias = await registry.isModelRegistered("reg-alias")
        let isNotRegistered = await registry.isModelRegistered("not-registered")

        XCTAssertTrue(isRegisteredByName)
        XCTAssertTrue(isRegisteredByCanonical)
        XCTAssertTrue(isRegisteredByAlias)
        XCTAssertFalse(isNotRegistered)
    }

    // MARK: - Multi-Provider Tests

    func test_same_model_name_different_providers() async {
        let registry = ModelRegistry()

        let openaiModel = makeTestModel(name: "gpt-4", provider: .openai)
        let customModel = makeTestModel(name: "gpt-4", provider: .custom)

        await registry.register(model: openaiModel, provider: .openai, canonicalId: "openai/gpt-4")
        await registry.register(model: customModel, provider: .custom, canonicalId: "custom/gpt-4")

        // Lookup by canonical ID should find correct one
        let openai = await registry.model(named: "openai/gpt-4", from: nil)
        XCTAssertNotNil(openai)

        let custom = await registry.model(named: "custom/gpt-4", from: nil)
        XCTAssertNotNil(custom)

        // Provider-scoped lookup
        let openaiScoped = await registry.model(named: "gpt-4", from: .openai)
        XCTAssertNotNil(openaiScoped)

        let customScoped = await registry.model(named: "gpt-4", from: .custom)
        XCTAssertNotNil(customScoped)
    }

    func test_models_from_multiple_providers() async {
        let registry = ModelRegistry()

        await registry.register(model: makeTestModel(name: "openai-1", provider: .openai), provider: .openai)
        await registry.register(model: makeTestModel(name: "openai-2", provider: .openai), provider: .openai)
        await registry.register(model: makeTestModel(name: "anthropic-1", provider: .anthropic), provider: .anthropic)

        let openaiModels = await registry.models(from: [.openai])
        XCTAssertEqual(openaiModels.count, 2)

        let bothProviders = await registry.models(from: [.openai, .anthropic])
        XCTAssertEqual(bothProviders.count, 3)
    }

    // MARK: - Default Models Tests

    func test_register_defaults() async {
        let registry = ModelRegistry()

        await registry.registerDefaults()

        let stats = await registry.statistics
        XCTAssertGreaterThan(stats.totalModels, 0)

        // Check some known default models exist
        let gpt4o = await registry.model(named: "gpt-4o", from: nil)
        let claude = await registry.model(named: "claude-3-5-sonnet-latest", from: nil)
        let gemini = await registry.model(named: "gemini-1.5-pro", from: nil)
        XCTAssertNotNil(gpt4o)
        XCTAssertNotNil(claude)
        XCTAssertNotNil(gemini)
    }

    func test_default_models_have_expected_capabilities() async {
        let gpt4o = DefaultModels.gpt4o
        XCTAssertTrue(gpt4o.hasCapability(.text))
        XCTAssertTrue(gpt4o.hasCapability(.vision))
        XCTAssertTrue(gpt4o.hasCapability(.tools))
        XCTAssertTrue(gpt4o.hasCapability(.streaming))

        let claude = DefaultModels.claude35Sonnet
        XCTAssertTrue(claude.hasCapability(.text))
        XCTAssertTrue(claude.hasCapability(.vision))
        XCTAssertTrue(claude.hasCapability(.computerUse))

        let gemini = DefaultModels.gemini15Pro
        XCTAssertTrue(gemini.hasCapability(.longContext))
        XCTAssertTrue(gemini.hasCapability(.video))
    }

    // MARK: - Batch Registration Tests

    func test_register_all_models() async {
        let registry = ModelRegistry()

        let models: [(LLMModelProtocol, LLMProvider)] = [
            (makeTestModel(name: "batch-1"), .openai),
            (makeTestModel(name: "batch-2"), .openai),
            (makeTestModel(name: "batch-3"), .anthropic)
        ]

        await registry.registerAll(models: models)

        let stats = await registry.statistics
        XCTAssertEqual(stats.totalModels, 3)
    }

    // MARK: - Thread Safety Tests

    func test_concurrent_registration() async {
        let registry = ModelRegistry()

        // Register many models concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let model = self.makeTestModel(name: "concurrent-\(i)")
                    await registry.register(model: model, provider: .openai)
                }
            }
        }

        let stats = await registry.statistics
        XCTAssertEqual(stats.totalModels, 100)
    }

    func test_concurrent_read_write() async {
        let registry = ModelRegistry()

        // Pre-register some models
        for i in 0..<50 {
            await registry.register(model: makeTestModel(name: "pre-\(i)"), provider: .openai)
        }

        // Concurrent reads and writes
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 50..<100 {
                group.addTask {
                    let model = self.makeTestModel(name: "write-\(i)")
                    await registry.register(model: model, provider: .openai)
                }
            }

            // Readers
            for i in 0..<50 {
                group.addTask {
                    _ = await registry.model(named: "pre-\(i)", from: nil)
                    _ = await registry.models(with: .text)
                    _ = await registry.statistics
                }
            }
        }

        let stats = await registry.statistics
        XCTAssertEqual(stats.totalModels, 100)
    }
}
