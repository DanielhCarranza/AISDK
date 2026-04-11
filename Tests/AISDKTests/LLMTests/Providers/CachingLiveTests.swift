//
//  CachingLiveTests.swift
//  AISDKTests
//
//  Real API integration tests for prompt caching.
//  These tests hit the live Anthropic API and require ANTHROPIC_API_KEY.
//  They are skipped automatically when the key is not set.
//
//  To run:
//    ANTHROPIC_API_KEY=sk-... swift test --filter CachingLiveTests
//

import XCTest
@testable import AISDK

final class CachingLiveTests: XCTestCase {

    // Use a cheap model for testing
    private let model = "claude-haiku-4-5-20251001"

    // A long system prompt that exceeds the minimum cacheable token count.
    // Claude Haiku 4.5 requires at least 4,096 tokens for a cache-eligible block
    // (Sonnet requires 1,024; Opus requires 4,096).
    // Each repetition is ~100 tokens, so 50 reps ≈ 5,000 tokens (safe margin).
    private let longSystemPrompt: String = {
        let base = """
        You are a highly knowledgeable assistant specializing in software engineering, \
        distributed systems, API design, and cloud architecture. You provide concise, \
        accurate answers with practical examples. When discussing code, always include \
        language-appropriate examples with proper error handling. Consider edge cases, \
        performance implications, security considerations, and scalability patterns. \
        You are familiar with microservices, event-driven architectures, CQRS, and \
        domain-driven design. You can explain complex technical concepts clearly. \
        You understand database optimization, indexing strategies, query planning, \
        connection pooling, and replication topologies for both SQL and NoSQL systems. \
        You are well-versed in containerization with Docker and orchestration with \
        Kubernetes, including pod scheduling, service meshes, and ingress controllers.
        """
        // Repeat enough to exceed 4,096 tokens with comfortable margin for Haiku 4.5
        return String(repeating: base + "\n\n", count: 50)
    }()

    private func skipIfNoKey() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !key.isEmpty else {
            throw XCTSkip("ANTHROPIC_API_KEY not set — skipping live caching test")
        }
        return key
    }

    // MARK: - Test: Standard caching produces a successful response

    func testStandardCachingCreatesCache() async throws {
        let apiKey = try skipIfNoKey()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: model,
            messages: [
                AIMessage.system(longSystemPrompt),
                AIMessage.user("What is 2+2? Answer in one word.")
            ],
            maxTokens: 100,
            temperature: 0.0,
            stream: false,
            reasoning: nil,
            caching: AICacheConfig(retention: .standard)
        )

        let response = try await client.execute(request: request)

        XCTAssertFalse(response.content.isEmpty, "Response should have content")
        let usage = try XCTUnwrap(response.usage, "Response should include usage")
        XCTAssertGreaterThan(usage.promptTokens, 0, "Should report prompt tokens")
        XCTAssertGreaterThan(usage.completionTokens, 0, "Should report completion tokens")

        print("  First request usage: prompt=\(usage.promptTokens), completion=\(usage.completionTokens), cached=\(usage.cachedTokens ?? 0)")
    }

    // MARK: - Test: Second identical request reads from cache

    func testCacheHitOnSecondRequest() async throws {
        try LiveTestHelpers.skipIfProviderBroken(.anthropic)
        let apiKey = try skipIfNoKey()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let messages = [
            AIMessage.system(longSystemPrompt),
            AIMessage.user("What is the capital of France? One word only.")
        ]

        let request = ProviderRequest(
            modelId: model,
            messages: messages,
            maxTokens: 50,
            temperature: 0.0,
            stream: false,
            reasoning: nil,
            caching: AICacheConfig(retention: .standard)
        )

        let response1: ProviderResponse
        let response2: ProviderResponse
        do {
            // First request — creates the cache
            response1 = try await client.execute(request: request)
            // Second request — same system prompt should hit cache
            response2 = try await client.execute(request: request)
        } catch {
            try LiveTestHelpers.handle(error, provider: .anthropic)
        }

        XCTAssertFalse(response1.content.isEmpty)
        let usage1 = try XCTUnwrap(response1.usage)
        let cached1 = usage1.cachedTokens ?? 0
        print("  Request 1: prompt=\(usage1.promptTokens), cached=\(cached1)")

        XCTAssertFalse(response2.content.isEmpty)
        let usage2 = try XCTUnwrap(response2.usage)
        let cached2 = usage2.cachedTokens ?? 0
        print("  Request 2: prompt=\(usage2.promptTokens), cached=\(cached2)")

        // On the second call, cache_read_input_tokens should be > 0
        XCTAssertGreaterThan(cached2, 0, "Second request should have cache_read_input_tokens > 0 (cache hit)")
    }

    // MARK: - Test: Request without caching has no cache tokens

    func testNoCachingOmitsCacheControl() async throws {
        let apiKey = try skipIfNoKey()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: model,
            messages: [
                AIMessage.system("You are a helpful assistant."),
                AIMessage.user("Say hello.")
            ],
            maxTokens: 50,
            temperature: 0.0,
            stream: false,
            reasoning: nil,
            caching: nil
        )

        let response = try await client.execute(request: request)
        XCTAssertFalse(response.content.isEmpty)

        let cached = response.usage?.cachedTokens ?? 0
        XCTAssertEqual(cached, 0, "Request without caching should have 0 cached tokens")
        print("  No-cache request: prompt=\(response.usage?.promptTokens ?? 0), cached=\(cached)")
    }

    // MARK: - Test: Streaming with caching works

    func testStreamingWithCaching() async throws {
        let apiKey = try skipIfNoKey()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: model,
            messages: [
                AIMessage.system(longSystemPrompt),
                AIMessage.user("Count from 1 to 3.")
            ],
            maxTokens: 100,
            temperature: 0.0,
            stream: true,
            reasoning: nil,
            caching: AICacheConfig(retention: .standard)
        )

        var textParts: [String] = []
        var gotStart = false
        var gotFinish = false

        for try await event in client.stream(request: request) {
            switch event {
            case .start:
                gotStart = true
            case .textDelta(let text):
                textParts.append(text)
            case .finish:
                gotFinish = true
            default:
                break
            }
        }

        XCTAssertTrue(gotStart, "Stream should have a start event")
        XCTAssertTrue(gotFinish, "Stream should have a finish event")
        let fullText = textParts.joined()
        XCTAssertFalse(fullText.isEmpty, "Stream should produce text")
        print("  Streaming response: \(fullText.prefix(100))...")
    }

    // MARK: - Test: AITextRequest caching flows through to ProviderRequest

    func testAITextRequestCachingPassthrough() throws {
        let textRequest = AITextRequest(
            messages: [.user("test")],
            reasoning: nil,
            caching: .enabled
        )

        let providerRequest = try textRequest.toProviderRequest(modelId: model)
        XCTAssertNotNil(providerRequest.caching, "Caching should be passed through")
        XCTAssertTrue(providerRequest.caching?.enabled ?? false, "Caching should be enabled")
    }

    // MARK: - Test: Raw HTTP verifies cache_control is sent and cache tokens returned

    func testRawHTTPCachingRoundtrip() async throws {
        let apiKey = try skipIfNoKey()

        // Build a raw HTTP request matching what the adapter would build
        let systemText = longSystemPrompt
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var httpRequest = URLRequest(url: url)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        httpRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 50,
            "system": [
                [
                    "type": "text",
                    "text": systemText,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "messages": [
                ["role": "user", "content": "Say hi."]
            ]
        ]

        httpRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // First request — creates the cache
        let (data1, resp1) = try await URLSession.shared.data(for: httpRequest)
        let httpResp1 = resp1 as! HTTPURLResponse
        XCTAssertEqual(httpResp1.statusCode, 200, "First request should succeed")
        let json1 = try JSONSerialization.jsonObject(with: data1) as! [String: Any]
        let usage1 = json1["usage"] as? [String: Any]
        print("  Raw HTTP Request 1 usage: \(usage1 ?? [:])")

        // Second request — should hit cache
        let (data2, resp2) = try await URLSession.shared.data(for: httpRequest)
        let httpResp2 = resp2 as! HTTPURLResponse
        XCTAssertEqual(httpResp2.statusCode, 200, "Second request should succeed")
        let json2 = try JSONSerialization.jsonObject(with: data2) as! [String: Any]
        let usage2 = json2["usage"] as? [String: Any]
        print("  Raw HTTP Request 2 usage: \(usage2 ?? [:])")

        // Verify cache tokens appear.
        // The first request may create the cache or hit an existing one
        // (if other tests in the suite already cached the same prompt).
        let cacheCreation1 = usage1?["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead1 = usage1?["cache_read_input_tokens"] as? Int ?? 0
        let cacheRead2 = usage2?["cache_read_input_tokens"] as? Int ?? 0
        print("  cache_creation_input_tokens (req 1): \(cacheCreation1)")
        print("  cache_read_input_tokens (req 1): \(cacheRead1)")
        print("  cache_read_input_tokens (req 2): \(cacheRead2)")

        // First request should either create or read from cache
        XCTAssertGreaterThan(cacheCreation1 + cacheRead1, 0, "First request should interact with cache (create or read)")
        // Second request should always read from cache
        XCTAssertGreaterThan(cacheRead2, 0, "Second request should read from cache")
    }

    // MARK: - Test: Extended caching configuration

    func testExtendedCachingConfiguration() throws {
        let textRequest = AITextRequest(
            messages: [.user("test")],
            reasoning: nil,
            caching: .extended()
        )

        let providerRequest = try textRequest.toProviderRequest(modelId: model)
        XCTAssertEqual(providerRequest.caching?.retention, .extended)
    }
}
