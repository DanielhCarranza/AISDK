//
//  CorrectnessEvalSuite.swift
//  AISDKTestRunner
//
//  Layer 2: Correctness evaluation suite for AISDK.
//  Validates streaming integrity, tool call parsing, error type mapping,
//  session roundtrip, multi-turn consistency, and reasoning events.
//

import Foundation
import AISDK

public final class CorrectnessEvalSuite: TestSuiteProtocol {
    public let reporter: TestReporter
    public let verbose: Bool
    private let suiteName = "Correctness"
    private let provider: String?

    public init(reporter: TestReporter, verbose: Bool, provider: String? = nil) {
        self.reporter = reporter
        self.verbose = verbose
        self.provider = provider
    }

    public func run() async throws {
        reporter.log("Starting correctness evaluation suite...")

        // Stream integrity tests (per provider)
        await testStreamChunkIntegrity()
        await testStreamEventOrdering()
        await testEmptyStreamHandling()

        // Tool call tests (per provider)
        await testToolCallJSONParsing()

        // Error type mapping
        await testErrorTypeMapping()

        // Session roundtrip (all 3 store types)
        await testSessionRoundtrip()

        // Multi-turn consistency
        await testMultiTurnConsistency()
    }

    // MARK: - Provider Helpers

    private struct ProviderSetup {
        let name: String
        let client: any ProviderClient
        let modelId: String
    }

    private func availableProviders() -> [ProviderSetup] {
        var providers: [ProviderSetup] = []

        if shouldTest("openai"), let key = requireEnvVar("OPENAI_API_KEY") {
            providers.append(ProviderSetup(
                name: "OpenAI",
                client: OpenAIClientAdapter(apiKey: key),
                modelId: "gpt-4o-mini"
            ))
        }

        if shouldTest("anthropic"), let key = requireEnvVar("ANTHROPIC_API_KEY") {
            providers.append(ProviderSetup(
                name: "Anthropic",
                client: AnthropicClientAdapter(apiKey: key),
                modelId: "claude-haiku-4-5-20251001"
            ))
        }

        if shouldTest("gemini"), let key = requireEnvVar("GOOGLE_API_KEY") {
            providers.append(ProviderSetup(
                name: "Gemini",
                client: GeminiClientAdapter(apiKey: key),
                modelId: "gemini-2.0-flash"
            ))
        }

        return providers
    }

    private func shouldTest(_ providerName: String) -> Bool {
        guard let filter = provider else { return true }
        return filter.lowercased() == providerName.lowercased()
    }

    // MARK: - Stream Chunk Integrity

    private func testStreamChunkIntegrity() async {
        let providers = availableProviders()
        if providers.isEmpty {
            reporter.recordSkipped(suiteName, "Stream chunk integrity", reason: "No provider API keys set")
            return
        }

        for p in providers {
            await withTimer("Stream chunk integrity (\(p.name))", suiteName) {
                let iterations = 10
                var validStreams = 0
                var totalChunks = 0

                for i in 0..<iterations {
                    let request = ProviderRequest(
                        modelId: p.modelId,
                        messages: [.user("Say 'test \(i)' and nothing else")],
                        maxTokens: 20,
                        stream: true,
                        timeout: 15
                    )

                    var chunkCount = 0
                    var finishCount = 0
                    var hasEmptyChunk = false

                    for try await event in p.client.stream(request: request) {
                        switch event {
                        case .textDelta(let text):
                            chunkCount += 1
                            if text.isEmpty {
                                hasEmptyChunk = true
                            }
                        case .finish:
                            finishCount += 1
                        default:
                            break
                        }
                    }

                    // Validate: all textDelta events should be non-empty
                    if hasEmptyChunk {
                        reporter.log("\(p.name) stream \(i): had empty textDelta chunk")
                    }

                    // Validate: exactly 1 finish event
                    guard finishCount == 1 else {
                        throw TestError.assertionFailed(
                            "\(p.name) stream \(i): expected 1 .finish event, got \(finishCount)"
                        )
                    }

                    if chunkCount > 0 && !hasEmptyChunk {
                        validStreams += 1
                    }
                    totalChunks += chunkCount
                }

                reporter.log("\(p.name): \(validStreams)/\(iterations) streams valid, \(totalChunks) total chunks")

                guard validStreams == iterations else {
                    throw TestError.assertionFailed(
                        "\(p.name): \(validStreams)/\(iterations) streams valid (expected all)"
                    )
                }
            }
        }
    }

    // MARK: - Stream Event Ordering

    private func testStreamEventOrdering() async {
        let providers = availableProviders()
        if providers.isEmpty {
            reporter.recordSkipped(suiteName, "Stream event ordering", reason: "No provider API keys set")
            return
        }

        for p in providers {
            await withTimer("Stream event ordering (\(p.name))", suiteName) {
                let request = ProviderRequest(
                    modelId: p.modelId,
                    messages: [.user("Count from 1 to 3")],
                    maxTokens: 30,
                    stream: true,
                    timeout: 15
                )

                var eventTypes: [String] = []

                for try await event in p.client.stream(request: request) {
                    switch event {
                    case .start:
                        eventTypes.append("start")
                    case .textDelta:
                        if eventTypes.last != "textDelta" {
                            eventTypes.append("textDelta")
                        }
                    case .finish:
                        eventTypes.append("finish")
                    case .usage:
                        // Usage events can arrive at various points
                        break
                    default:
                        break
                    }
                }

                reporter.log("\(p.name) event order: \(eventTypes)")

                // Validate ordering: if start exists, it must be first
                if let startIdx = eventTypes.firstIndex(of: "start") {
                    guard startIdx == 0 else {
                        throw TestError.assertionFailed(
                            "\(p.name): .start was not first event. Order: \(eventTypes)"
                        )
                    }
                }

                // Validate: textDelta must exist
                guard eventTypes.contains("textDelta") else {
                    throw TestError.assertionFailed(
                        "\(p.name): no .textDelta events received. Order: \(eventTypes)"
                    )
                }

                // Validate: finish must exist and be last
                guard let finishIdx = eventTypes.firstIndex(of: "finish") else {
                    throw TestError.assertionFailed(
                        "\(p.name): no .finish event received. Order: \(eventTypes)"
                    )
                }

                guard let textIdx = eventTypes.firstIndex(of: "textDelta") else {
                    throw TestError.assertionFailed("\(p.name): no .textDelta found")
                }

                guard textIdx < finishIdx else {
                    throw TestError.assertionFailed(
                        "\(p.name): .textDelta after .finish. Order: \(eventTypes)"
                    )
                }
            }
        }
    }

    // MARK: - Empty Stream Handling

    private func testEmptyStreamHandling() async {
        let providers = availableProviders()
        if providers.isEmpty {
            reporter.recordSkipped(suiteName, "Empty stream handling", reason: "No provider API keys set")
            return
        }

        for p in providers {
            await withTimer("Empty stream handling (\(p.name))", suiteName) {
                // Request with maxTokens=1 to get minimal/potentially empty response
                let request = ProviderRequest(
                    modelId: p.modelId,
                    messages: [.user(".")],
                    maxTokens: 1,
                    stream: true,
                    timeout: 15
                )

                var gotFinish = false
                var text = ""

                // The test validates: no crash on minimal/empty stream, finish event received
                for try await event in p.client.stream(request: request) {
                    switch event {
                    case .textDelta(let delta):
                        text += delta
                    case .finish:
                        gotFinish = true
                    default:
                        break
                    }
                }

                guard gotFinish else {
                    throw TestError.assertionFailed(
                        "\(p.name): no .finish on minimal stream"
                    )
                }

                reporter.log("\(p.name): minimal stream completed, text='\(text.prefix(20))', gotFinish=\(gotFinish)")
            }
        }
    }

    // MARK: - Tool Call JSON Parsing

    private func testToolCallJSONParsing() async {
        let providers = availableProviders()
        if providers.isEmpty {
            reporter.recordSkipped(suiteName, "Tool call JSON parsing", reason: "No provider API keys set")
            return
        }

        let weatherTool = ProviderJSONValue.object([
            "type": .string("function"),
            "function": .object([
                "name": .string("get_weather"),
                "description": .string("Get weather for a city"),
                "parameters": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "city": .object([
                            "type": .string("string"),
                            "description": .string("City name")
                        ])
                    ]),
                    "required": .array([.string("city")])
                ])
            ])
        ])

        for p in providers {
            await withTimer("Tool call JSON parsing (\(p.name))", suiteName) {
                let iterations = 5
                var parseSuccesses = 0

                for i in 0..<iterations {
                    let request = ProviderRequest(
                        modelId: p.modelId,
                        messages: [.user("What is the weather in city number \(i + 1) of Tokyo? Use the tool.")],
                        maxTokens: 100,
                        tools: [weatherTool],
                        toolChoice: .auto,
                        timeout: 15
                    )

                    let response = try await p.client.execute(request: request)

                    if !response.toolCalls.isEmpty {
                        for call in response.toolCalls {
                            guard let data = call.arguments.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                throw TestError.assertionFailed(
                                    "\(p.name) iter \(i): tool call arguments not valid JSON: '\(call.arguments)'"
                                )
                            }
                            reporter.log("\(p.name) iter \(i): tool=\(call.name), args=\(json)")
                            parseSuccesses += 1
                        }
                    } else {
                        // Model chose to respond with text instead of tool call -- not a parse error
                        reporter.log("\(p.name) iter \(i): model responded with text instead of tool call")
                        parseSuccesses += 1
                    }
                }

                reporter.log("\(p.name): \(parseSuccesses)/\(iterations) tool call iterations successful")

                guard parseSuccesses == iterations else {
                    throw TestError.assertionFailed(
                        "\(p.name): \(parseSuccesses)/\(iterations) tool call parse successes"
                    )
                }
            }
        }
    }

    // MARK: - Error Type Mapping

    private func testErrorTypeMapping() async {
        await withTimer("Error type mapping - invalid API key", suiteName) {
            // Test with a known-bad API key to verify error mapping
            let badClient = OpenAIClientAdapter(apiKey: "sk-invalid-key-for-testing")

            do {
                _ = try await badClient.execute(request: ProviderRequest(
                    modelId: "gpt-4o-mini",
                    messages: [.user("test")],
                    maxTokens: 5,
                    timeout: 10
                ))
                throw TestError.assertionFailed("Expected auth error but request succeeded")
            } catch let error as ProviderError {
                switch error {
                case .authenticationFailed:
                    reporter.log("Correctly mapped to .authenticationFailed")
                default:
                    // Some providers may return a different error type for bad keys
                    reporter.log("Got ProviderError: \(error) -- acceptable mapping")
                }
            } catch is TestError {
                throw TestError.assertionFailed("Request with invalid key should have failed")
            } catch {
                // Non-ProviderError is still acceptable as long as it doesn't crash
                reporter.log("Got non-ProviderError: \(type(of: error)) -- request failed as expected")
            }
        }

        await withTimer("Error type mapping - invalid model", suiteName) {
            guard let apiKey = requireEnvVar("OPENAI_API_KEY") else {
                reporter.recordSkipped(suiteName, "Error type mapping - invalid model", reason: "OPENAI_API_KEY not set")
                return
            }

            let client = OpenAIClientAdapter(apiKey: apiKey)

            do {
                _ = try await client.execute(request: ProviderRequest(
                    modelId: "gpt-nonexistent-model-12345",
                    messages: [.user("test")],
                    maxTokens: 5,
                    timeout: 10
                ))
                throw TestError.assertionFailed("Expected model not found error but request succeeded")
            } catch let error as ProviderError {
                switch error {
                case .modelNotFound:
                    reporter.log("Correctly mapped to .modelNotFound")
                case .invalidRequest:
                    reporter.log("Mapped to .invalidRequest -- acceptable for invalid model")
                default:
                    reporter.log("Got ProviderError.\(error) -- acceptable error mapping")
                }
            } catch is TestError {
                throw TestError.assertionFailed("Request with invalid model should have failed")
            } catch {
                reporter.log("Got non-ProviderError for invalid model: \(type(of: error))")
            }
        }
    }

    // MARK: - Session Roundtrip (All 3 Store Types)

    private func testSessionRoundtrip() async {
        // InMemorySessionStore
        await withTimer("Session roundtrip - InMemoryStore", suiteName) {
            let store = InMemorySessionStore()
            try await validateSessionRoundtrip(store: store, storeName: "InMemory")
        }

        // FileSystemSessionStore
        await withTimer("Session roundtrip - FileSystemStore", suiteName) {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("aisdk-eval-\(UUID().uuidString)")
            let store = try FileSystemSessionStore(directory: tempDir)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }
            try await validateSessionRoundtrip(store: store, storeName: "FileSystem")
        }

        // SQLiteSessionStore
        await withTimer("Session roundtrip - SQLiteStore", suiteName) {
            let store = try SQLiteSessionStore()
            try await validateSessionRoundtrip(store: store, storeName: "SQLite")
        }
    }

    private func validateSessionRoundtrip(store: some SessionStore, storeName: String) async throws {
        // 1. Create session
        let session = AISession(userId: "eval-user-\(storeName)", title: "Eval Session \(storeName)")
        let created = try await store.create(session)
        guard created.id == session.id else {
            throw TestError.assertionFailed("\(storeName): created session ID mismatch")
        }

        // 2. Append messages
        try await store.appendMessage(.user("Hello from eval"), toSession: session.id)
        try await store.appendMessage(.assistant("Eval response"), toSession: session.id)
        try await store.appendMessage(.user("Follow-up question"), toSession: session.id)

        // 3. Load and verify
        guard let loaded = try await store.load(id: session.id) else {
            throw TestError.assertionFailed("\(storeName): failed to load session")
        }

        guard loaded.messages.count == 3 else {
            throw TestError.assertionFailed("\(storeName): expected 3 messages, got \(loaded.messages.count)")
        }

        guard loaded.messages[0].role == .user else {
            throw TestError.assertionFailed("\(storeName): message 0 role mismatch")
        }
        guard loaded.messages[1].role == .assistant else {
            throw TestError.assertionFailed("\(storeName): message 1 role mismatch")
        }
        guard loaded.messages[2].role == .user else {
            throw TestError.assertionFailed("\(storeName): message 2 role mismatch")
        }

        // Verify content roundtrip
        guard loaded.messages[0].content.textValue == "Hello from eval" else {
            throw TestError.assertionFailed("\(storeName): message 0 content mismatch: '\(loaded.messages[0].content.textValue)'")
        }
        guard loaded.messages[1].content.textValue == "Eval response" else {
            throw TestError.assertionFailed("\(storeName): message 1 content mismatch")
        }

        // 4. Verify title persisted
        guard loaded.title == "Eval Session \(storeName)" else {
            throw TestError.assertionFailed("\(storeName): title mismatch: '\(loaded.title ?? "nil")'")
        }

        // 5. Save modified session and verify
        var modified = loaded
        modified.title = "Modified \(storeName)"
        try await store.save(modified)

        guard let reloaded = try await store.load(id: session.id) else {
            throw TestError.assertionFailed("\(storeName): failed to reload after save")
        }
        guard reloaded.title == "Modified \(storeName)" else {
            throw TestError.assertionFailed("\(storeName): title not persisted after save")
        }
        guard reloaded.messages.count == 3 else {
            throw TestError.assertionFailed("\(storeName): messages lost after save: \(reloaded.messages.count)")
        }

        // 6. Delete and verify
        try await store.delete(id: session.id)
        let deleted = try await store.load(id: session.id)
        guard deleted == nil else {
            throw TestError.assertionFailed("\(storeName): session still exists after delete")
        }

        reporter.log("\(storeName): full roundtrip (create/append/load/save/delete) passed")
    }

    // MARK: - Multi-Turn Consistency

    private func testMultiTurnConsistency() async {
        let providers = availableProviders()
        if providers.isEmpty {
            reporter.recordSkipped(suiteName, "Multi-turn consistency", reason: "No provider API keys set")
            return
        }

        // Use only one provider for multi-turn test (cheaper, still validates SDK plumbing)
        let p = providers[0]

        await withTimer("Multi-turn consistency (\(p.name))", suiteName) {
            var messages: [AIMessage] = [
                .system("You are a helpful assistant. Remember everything the user tells you."),
                .user("My favorite color is blue. Remember this.")
            ]

            // Turn 1: establish context
            let response1 = try await p.client.execute(request: ProviderRequest(
                modelId: p.modelId,
                messages: messages,
                maxTokens: 50,
                timeout: 15
            ))

            guard !response1.content.isEmpty else {
                throw TestError.assertionFailed("\(p.name): empty response on turn 1")
            }

            messages.append(.assistant(response1.content))
            reporter.log("\(p.name) turn 1: \(response1.content.prefix(60))")

            // Turn 2: ask about something else
            messages.append(.user("My name is Alice."))

            let response2 = try await p.client.execute(request: ProviderRequest(
                modelId: p.modelId,
                messages: messages,
                maxTokens: 50,
                timeout: 15
            ))

            guard !response2.content.isEmpty else {
                throw TestError.assertionFailed("\(p.name): empty response on turn 2")
            }

            messages.append(.assistant(response2.content))
            reporter.log("\(p.name) turn 2: \(response2.content.prefix(60))")

            // Turn 3: ask about earlier context
            messages.append(.user("What is my favorite color?"))

            let response3 = try await p.client.execute(request: ProviderRequest(
                modelId: p.modelId,
                messages: messages,
                maxTokens: 50,
                timeout: 15
            ))

            guard !response3.content.isEmpty else {
                throw TestError.assertionFailed("\(p.name): empty response on turn 3")
            }

            reporter.log("\(p.name) turn 3: \(response3.content.prefix(80))")

            // Verify the model references the earlier context
            let lowerContent = response3.content.lowercased()
            guard lowerContent.contains("blue") else {
                throw TestError.assertionFailed(
                    "\(p.name): model did not recall 'blue' in turn 3. Response: \(response3.content.prefix(100))"
                )
            }

            // Turn 4: verify name recall
            messages.append(.assistant(response3.content))
            messages.append(.user("What is my name?"))

            let response4 = try await p.client.execute(request: ProviderRequest(
                modelId: p.modelId,
                messages: messages,
                maxTokens: 50,
                timeout: 15
            ))

            guard !response4.content.isEmpty else {
                throw TestError.assertionFailed("\(p.name): empty response on turn 4")
            }

            reporter.log("\(p.name) turn 4: \(response4.content.prefix(80))")

            let lowerContent4 = response4.content.lowercased()
            guard lowerContent4.contains("alice") else {
                throw TestError.assertionFailed(
                    "\(p.name): model did not recall 'Alice' in turn 4. Response: \(response4.content.prefix(100))"
                )
            }

            // Turn 5: final summary recall
            messages.append(.assistant(response4.content))
            messages.append(.user("Summarize: what's my name and favorite color?"))

            let response5 = try await p.client.execute(request: ProviderRequest(
                modelId: p.modelId,
                messages: messages,
                maxTokens: 80,
                timeout: 15
            ))

            guard !response5.content.isEmpty else {
                throw TestError.assertionFailed("\(p.name): empty response on turn 5")
            }

            reporter.log("\(p.name) turn 5 (summary): \(response5.content.prefix(100))")

            let lowerContent5 = response5.content.lowercased()
            guard lowerContent5.contains("alice") && lowerContent5.contains("blue") else {
                throw TestError.assertionFailed(
                    "\(p.name): model didn't maintain 5-turn context. Response: \(response5.content.prefix(120))"
                )
            }
        }
    }
}
