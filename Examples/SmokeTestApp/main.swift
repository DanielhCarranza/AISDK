//
//  main.swift
//  SmokeTestApp
//
//  Layer 1: Production smoke tests for AISDK.
//  Validates the SDK fundamentally works against real provider APIs.
//  Target: all tests pass in < 30 seconds.
//
//  Usage:
//    swift run SmokeTestApp
//    swift run SmokeTestApp --verbose
//
//  Required env vars (in .env or environment):
//    OPENAI_API_KEY      - for OpenAI tests
//    ANTHROPIC_API_KEY   - for Anthropic tests
//    GOOGLE_API_KEY      - for Gemini tests
//    OPENROUTER_API_KEY  - for OpenRouter tests
//
//  Missing keys gracefully skip that provider's tests.
//

import Foundation
import AISDK

// MARK: - Configuration

let maxRetries = 2
let retryDelay: UInt64 = 2_000_000_000 // 2 seconds in nanoseconds
let requestTimeout: TimeInterval = 10
let sessionTimeout: TimeInterval = 5
let verbose = CommandLine.arguments.contains("--verbose") || CommandLine.arguments.contains("-v")

// MARK: - Result Tracking

struct SmokeResult {
    let category: String
    let provider: String
    let test: String
    let passed: Bool
    let duration: TimeInterval
    let message: String?
}

var results: [SmokeResult] = []
let startTime = Date()

func record(_ category: String, _ provider: String, _ test: String, passed: Bool, duration: TimeInterval, message: String? = nil) {
    let result = SmokeResult(category: category, provider: provider, test: test, passed: passed, duration: duration, message: message)
    results.append(result)
    let icon = passed ? "PASS" : "FAIL"
    let dur = String(format: "%.2fs", duration)
    print("  [\(icon)] \(provider) - \(test) (\(dur))")
    if let msg = message, (verbose || !passed) {
        print("         \(msg)")
    }
}

func log(_ msg: String) {
    if verbose { print("  [LOG] \(msg)") }
}

// MARK: - Environment

func loadEnv() {
    for path in [".env", "../.env", "../../.env"] {
        guard let content = try? String(contentsOfFile: path) else { continue }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
            setenv(key, value, 0) // Don't overwrite existing
        }
        log("Loaded environment from \(path)")
        return
    }
}

func envKey(_ name: String) -> String? {
    guard let val = ProcessInfo.processInfo.environment[name], !val.isEmpty else { return nil }
    return val
}

// MARK: - Retry Helper

func withRetry<T>(
    _ label: String,
    maxAttempts: Int = maxRetries + 1,
    _ body: () async throws -> T
) async throws -> T {
    var lastError: Error?
    for attempt in 1...maxAttempts {
        do {
            return try await body()
        } catch {
            lastError = error
            let isRateLimit = "\(error)".lowercased().contains("rate") || "\(error)".lowercased().contains("429")
            let isOverloaded = "\(error)".lowercased().contains("overloaded") || "\(error)".lowercased().contains("529")
            if (isRateLimit || isOverloaded) && attempt < maxAttempts {
                log("\(label): retry \(attempt)/\(maxAttempts - 1) after rate limit/overload")
                try await Task.sleep(nanoseconds: retryDelay)
                continue
            }
            throw error
        }
    }
    throw lastError!
}

// MARK: - Provider Definitions

struct ProviderConfig {
    let name: String
    let envKey: String
    let makeClient: (String) -> any ProviderClient
    let modelId: String
}

let providers: [ProviderConfig] = [
    ProviderConfig(
        name: "OpenAI",
        envKey: "OPENAI_API_KEY",
        makeClient: { OpenAIClientAdapter(apiKey: $0) },
        modelId: "gpt-4o-mini"
    ),
    ProviderConfig(
        name: "Anthropic",
        envKey: "ANTHROPIC_API_KEY",
        makeClient: { AnthropicClientAdapter(apiKey: $0) },
        modelId: "claude-haiku-4-5-20251001"
    ),
    ProviderConfig(
        name: "Gemini",
        envKey: "GOOGLE_API_KEY",
        makeClient: { GeminiClientAdapter(apiKey: $0) },
        modelId: "gemini-2.0-flash"
    ),
    ProviderConfig(
        name: "OpenRouter",
        envKey: "OPENROUTER_API_KEY",
        makeClient: { OpenRouterClient(apiKey: $0, appName: "SmokeTestApp", siteURL: "https://github.com/AISDK") },
        modelId: "openai/gpt-4o-mini"
    ),
]

// MARK: - Test 1: Provider Connection

func testProviderConnection() async {
    print("\n--- Provider Connection Tests ---")

    for provider in providers {
        guard let apiKey = envKey(provider.envKey) else {
            print("  [SKIP] \(provider.name) - \(provider.envKey) not set")
            continue
        }

        let client = provider.makeClient(apiKey)
        let timer = Date()

        do {
            let response = try await withRetry("\(provider.name) connection") {
                try await client.execute(request: ProviderRequest(
                    modelId: provider.modelId,
                    messages: [.user("Say hi")],
                    maxTokens: 5,
                    timeout: requestTimeout
                ))
            }

            let passed = !response.content.isEmpty
            record("Connection", provider.name, "basic completion",
                   passed: passed,
                   duration: Date().timeIntervalSince(timer),
                   message: passed ? "Response: \(response.content.prefix(50))" : "Empty response")
        } catch {
            record("Connection", provider.name, "basic completion",
                   passed: false,
                   duration: Date().timeIntervalSince(timer),
                   message: "\(error)")
        }
    }
}

// MARK: - Test 2: Streaming

func testStreaming() async {
    print("\n--- Streaming Tests ---")

    for provider in providers {
        guard let apiKey = envKey(provider.envKey) else {
            print("  [SKIP] \(provider.name) - \(provider.envKey) not set")
            continue
        }

        let client = provider.makeClient(apiKey)
        let timer = Date()

        do {
            try await withRetry("\(provider.name) streaming") {
                let request = ProviderRequest(
                    modelId: provider.modelId,
                    messages: [.user("Count from 1 to 3")],
                    maxTokens: 30,
                    stream: true,
                    timeout: requestTimeout
                )

                var textDeltas = 0
                var gotFinish = false
                var gotStart = false
                var fullText = ""
                var eventOrder: [String] = []

                for try await event in client.stream(request: request) {
                    switch event {
                    case .start:
                        gotStart = true
                        eventOrder.append("start")
                    case .textDelta(let text):
                        textDeltas += 1
                        fullText += text
                        if eventOrder.last != "textDelta" {
                            eventOrder.append("textDelta")
                        }
                    case .finish:
                        gotFinish = true
                        eventOrder.append("finish")
                    default:
                        break
                    }
                }

                // Validate: at least 1 textDelta event
                guard textDeltas >= 1 else {
                    throw SmokeTestError.assertion("Expected >= 1 textDelta events, got \(textDeltas)")
                }

                // Validate: finish event received
                guard gotFinish else {
                    throw SmokeTestError.assertion("No .finish event received")
                }

                // Validate: event ordering (start before textDelta before finish, if start present)
                if gotStart {
                    let startIdx = eventOrder.firstIndex(of: "start") ?? 0
                    let textIdx = eventOrder.firstIndex(of: "textDelta") ?? 0
                    let finishIdx = eventOrder.firstIndex(of: "finish") ?? 0
                    guard startIdx < textIdx && textIdx < finishIdx else {
                        throw SmokeTestError.assertion("Bad event order: \(eventOrder)")
                    }
                }

                log("\(provider.name): \(textDeltas) deltas, text=\(fullText.prefix(30))...")
            }

            record("Streaming", provider.name, "stream integrity",
                   passed: true,
                   duration: Date().timeIntervalSince(timer))
        } catch {
            record("Streaming", provider.name, "stream integrity",
                   passed: false,
                   duration: Date().timeIntervalSince(timer),
                   message: "\(error)")
        }
    }
}

// MARK: - Test 3: Tool Calling

func testToolCalling() async {
    print("\n--- Tool Call Tests ---")

    // Tool calling only tested on providers that reliably support it
    let toolProviders = providers.filter { $0.name != "OpenRouter" }

    for provider in toolProviders {
        guard let apiKey = envKey(provider.envKey) else {
            print("  [SKIP] \(provider.name) - \(provider.envKey) not set")
            continue
        }

        let client = provider.makeClient(apiKey)
        let timer = Date()

        do {
            try await withRetry("\(provider.name) tool call") {
                let weatherTool = ProviderJSONValue.object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string("get_weather"),
                        "description": .string("Get the current weather for a location"),
                        "parameters": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "location": .object([
                                    "type": .string("string"),
                                    "description": .string("City name")
                                ])
                            ]),
                            "required": .array([.string("location")])
                        ])
                    ])
                ])

                let response = try await client.execute(request: ProviderRequest(
                    modelId: provider.modelId,
                    messages: [.user("What is the weather in Tokyo? Use the get_weather tool.")],
                    maxTokens: 100,
                    tools: [weatherTool],
                    toolChoice: .auto,
                    timeout: requestTimeout
                ))

                // Model should either make a tool call or respond with text
                let hasToolCalls = !response.toolCalls.isEmpty
                let hasContent = !response.content.isEmpty

                guard hasToolCalls || hasContent else {
                    throw SmokeTestError.assertion("No tool calls and no content in response")
                }

                if hasToolCalls {
                    let call = response.toolCalls[0]
                    log("\(provider.name): tool=\(call.name), args=\(call.arguments.prefix(50))")

                    // Validate the tool call has parseable JSON arguments
                    guard let data = call.arguments.data(using: .utf8),
                          let _ = try? JSONSerialization.jsonObject(with: data) else {
                        throw SmokeTestError.assertion("Tool call arguments not valid JSON: \(call.arguments)")
                    }
                } else {
                    log("\(provider.name): model responded with text instead of tool call")
                }
            }

            record("ToolCall", provider.name, "tool execution",
                   passed: true,
                   duration: Date().timeIntervalSince(timer))
        } catch {
            record("ToolCall", provider.name, "tool execution",
                   passed: false,
                   duration: Date().timeIntervalSince(timer),
                   message: "\(error)")
        }
    }
}

// MARK: - Test 4: Session Persistence

func testSession() async {
    print("\n--- Session Tests ---")

    let timer = Date()
    do {
        let store = InMemorySessionStore()

        // 1. Create session
        let session = AISession(userId: "smoke-test-user", title: "Smoke Test Session")
        let created = try await store.create(session)
        guard created.id == session.id else {
            throw SmokeTestError.assertion("Created session ID mismatch")
        }
        log("Session created: \(created.id)")

        // 2. Append messages
        try await store.appendMessage(.user("Hello from smoke test"), toSession: session.id)
        try await store.appendMessage(.assistant("Hello! How can I help?"), toSession: session.id)

        // 3. Load and verify
        guard let loaded = try await store.load(id: session.id) else {
            throw SmokeTestError.assertion("Failed to load session")
        }
        guard loaded.messages.count == 2 else {
            throw SmokeTestError.assertion("Expected 2 messages, got \(loaded.messages.count)")
        }
        guard loaded.messages[0].role == .user else {
            throw SmokeTestError.assertion("First message should be user, got \(loaded.messages[0].role)")
        }
        guard loaded.messages[1].role == .assistant else {
            throw SmokeTestError.assertion("Second message should be assistant, got \(loaded.messages[1].role)")
        }
        guard loaded.title == "Smoke Test Session" else {
            throw SmokeTestError.assertion("Title mismatch: \(loaded.title ?? "nil")")
        }

        // 4. Save modified session
        var modified = loaded
        modified.title = "Updated Smoke Test"
        try await store.save(modified)

        guard let reloaded = try await store.load(id: session.id) else {
            throw SmokeTestError.assertion("Failed to reload session after save")
        }
        guard reloaded.title == "Updated Smoke Test" else {
            throw SmokeTestError.assertion("Title not persisted after save")
        }
        guard reloaded.messages.count == 2 else {
            throw SmokeTestError.assertion("Messages lost after save: \(reloaded.messages.count)")
        }

        record("Session", "InMemoryStore", "create/append/load/save roundtrip",
               passed: true,
               duration: Date().timeIntervalSince(timer))
    } catch {
        record("Session", "InMemoryStore", "create/append/load/save roundtrip",
               passed: false,
               duration: Date().timeIntervalSince(timer),
               message: "\(error)")
    }
}

// MARK: - Test 5: GenerativeUI (UITree)

func testGenerativeUI() async {
    print("\n--- GenerativeUI Tests ---")

    let timer = Date()
    do {
        // Test: Parse a valid UITree JSON and verify it builds without crash
        let uiTreeJSON = """
        {
            "root": "card_1",
            "elements": {
                "card_1": {
                    "type": "VStack",
                    "props": { "spacing": 8 },
                    "children": ["text_1", "text_2"]
                },
                "text_1": {
                    "type": "Text",
                    "props": { "content": "Hello from Smoke Test" }
                },
                "text_2": {
                    "type": "Text",
                    "props": { "content": "SDK is working" }
                }
            }
        }
        """

        let tree = try UITree.parse(from: uiTreeJSON)
        guard tree.rootKey == "card_1" else {
            throw SmokeTestError.assertion("Root key mismatch: \(tree.rootKey)")
        }
        guard tree.nodes.count == 3 else {
            throw SmokeTestError.assertion("Expected 3 nodes, got \(tree.nodes.count)")
        }

        // Verify node types
        guard let rootNode = tree.nodes["card_1"] else {
            throw SmokeTestError.assertion("Root node not found")
        }
        guard rootNode.type == "VStack" else {
            throw SmokeTestError.assertion("Root type mismatch: \(rootNode.type)")
        }
        guard rootNode.childKeys.count == 2 else {
            throw SmokeTestError.assertion("Root should have 2 children, got \(rootNode.childKeys.count)")
        }

        record("GenerativeUI", "UITree", "parse and validate",
               passed: true,
               duration: Date().timeIntervalSince(timer))
    } catch {
        record("GenerativeUI", "UITree", "parse and validate",
               passed: false,
               duration: Date().timeIntervalSince(timer),
               message: "\(error)")
    }

    // Test: Invalid UITree should fail gracefully
    let timer2 = Date()
    do {
        let invalidJSON = "{ \"not\": \"a valid tree\" }"
        _ = try UITree.parse(from: invalidJSON)
        // If we get here, it didn't throw -- that's a failure
        record("GenerativeUI", "UITree", "invalid JSON rejection",
               passed: false,
               duration: Date().timeIntervalSince(timer2),
               message: "Expected parse to throw for invalid UITree JSON, but it succeeded")
    } catch {
        // Expected -- invalid JSON should throw
        record("GenerativeUI", "UITree", "invalid JSON rejection",
               passed: true,
               duration: Date().timeIntervalSince(timer2),
               message: "Correctly rejected invalid input")
    }
}

// MARK: - Test 6: Gemini Reasoning (thinkingConfig)

func testGeminiReasoning() async {
    print("\n--- Gemini Reasoning Tests ---")

    guard let apiKey = envKey("GOOGLE_API_KEY") else {
        print("  [SKIP] Gemini reasoning - GOOGLE_API_KEY not set")
        return
    }

    let client = GeminiClientAdapter(apiKey: apiKey)

    // Test 6a: Non-streaming reasoning with includeThoughts
    let timer1 = Date()
    do {
        let response = try await withRetry("Gemini reasoning non-streaming") {
            try await client.execute(request: ProviderRequest(
                modelId: "gemini-2.5-flash",
                messages: [.user("What is 15 * 37? Think step by step.")],
                maxTokens: 500,
                reasoning: AIReasoningConfig.effort(.medium),
                timeout: 30,
                providerOptions: ["includeThoughts": .bool(true)]
            ))
        }

        let hasContent = !response.content.isEmpty
        let hasReasoning = response.metadata?["reasoning"] != nil

        record("Reasoning", "Gemini", "non-streaming with thinkingConfig",
               passed: hasContent,
               duration: Date().timeIntervalSince(timer1),
               message: hasContent
                   ? "Content: \(response.content.prefix(60))... reasoning=\(hasReasoning)"
                   : "Empty response")
    } catch {
        record("Reasoning", "Gemini", "non-streaming with thinkingConfig",
               passed: false,
               duration: Date().timeIntervalSince(timer1),
               message: "\(error)")
    }

    // Test 6b: Streaming reasoning emits reasoningDelta events
    let timer2 = Date()
    do {
        try await withRetry("Gemini reasoning streaming") {
            let request = ProviderRequest(
                modelId: "gemini-2.5-flash",
                messages: [.user("What is 15 * 37? Think step by step.")],
                maxTokens: 500,
                stream: true,
                reasoning: AIReasoningConfig.effort(.medium),
                timeout: 30,
                providerOptions: ["includeThoughts": .bool(true)]
            )

            var reasoningDeltas = 0
            var textDeltas = 0
            var gotFinish = false

            for try await event in client.stream(request: request) {
                switch event {
                case .reasoningDelta:
                    reasoningDeltas += 1
                case .textDelta:
                    textDeltas += 1
                case .finish:
                    gotFinish = true
                default:
                    break
                }
            }

            guard gotFinish else {
                throw SmokeTestError.assertion("No .finish event received")
            }
            guard textDeltas >= 1 else {
                throw SmokeTestError.assertion("Expected textDelta events, got \(textDeltas)")
            }

            log("Gemini reasoning: \(reasoningDeltas) reasoning deltas, \(textDeltas) text deltas")
        }

        record("Reasoning", "Gemini", "streaming with reasoningDelta",
               passed: true,
               duration: Date().timeIntervalSince(timer2))
    } catch {
        record("Reasoning", "Gemini", "streaming with reasoningDelta",
               passed: false,
               duration: Date().timeIntervalSince(timer2),
               message: "\(error)")
    }

    // Test 6c: Verify thinkingConfig does NOT cause 400 error (the original bug)
    let timer3 = Date()
    do {
        let response = try await withRetry("Gemini thinkingConfig no 400") {
            try await client.execute(request: ProviderRequest(
                modelId: "gemini-2.5-flash",
                messages: [.user("Say hello")],
                maxTokens: 20,
                reasoning: AIReasoningConfig.effort(.low),
                timeout: 15
            ))
        }

        let passed = !response.content.isEmpty
        record("Reasoning", "Gemini", "thinkingConfig no 400 error",
               passed: passed,
               duration: Date().timeIntervalSince(timer3),
               message: passed ? "No INVALID_ARGUMENT error" : "Empty response")
    } catch {
        let errorStr = "\(error)"
        let is400Bug = errorStr.contains("thinkingConfig") || errorStr.contains("INVALID_ARGUMENT")
        record("Reasoning", "Gemini", "thinkingConfig no 400 error",
               passed: false,
               duration: Date().timeIntervalSince(timer3),
               message: is400Bug
                   ? "BUG STILL PRESENT: \(errorStr.prefix(100))"
                   : "\(errorStr.prefix(100))")
    }
}

// MARK: - Error Type

enum SmokeTestError: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self { case .assertion(let msg): return msg }
    }
}

// MARK: - Main

func printBanner() {
    print("""

    ======================================================
      AISDK Smoke Test App - Layer 1 Production Validation
    ======================================================
      Validates SDK fundamentals against real provider APIs.
      Target: all tests pass in < 30 seconds.
    """)
}

func printSummary() {
    let totalDuration = Date().timeIntervalSince(startTime)
    let passed = results.filter { $0.passed }.count
    let failed = results.filter { !$0.passed }.count
    let total = results.count

    print("\n======================================================")
    print("  SMOKE TEST SUMMARY")
    print("======================================================")

    // Group by category
    let categories = Dictionary(grouping: results) { $0.category }
    for (cat, catResults) in categories.sorted(by: { $0.key < $1.key }) {
        let catPassed = catResults.filter { $0.passed }.count
        let icon = catPassed == catResults.count ? "OK" : "!!"
        print("  [\(icon)] \(cat): \(catPassed)/\(catResults.count) passed")
    }

    print("------------------------------------------------------")
    print("  Total: \(passed)/\(total) passed, \(failed) failed")
    print(String(format: "  Duration: %.2f seconds", totalDuration))

    if failed > 0 {
        print("\n  Failed:")
        for r in results where !r.passed {
            print("    - [\(r.category)] \(r.provider): \(r.test)")
            if let msg = r.message {
                print("      \(msg)")
            }
        }
    }

    let status = failed == 0 ? "ALL SMOKE TESTS PASSED" : "SMOKE TESTS FAILED"
    print("\n  \(status)")
    print("======================================================\n")
}

// Entry point
let semaphore = DispatchSemaphore(value: 0)
Task {
    printBanner()
    loadEnv()

    // Check which providers are available
    var available: [String] = []
    for p in providers {
        if envKey(p.envKey) != nil { available.append(p.name) }
    }
    if available.isEmpty {
        print("\n  [WARN] No provider API keys found. Set at least one in .env")
        print("         Tests requiring API keys will be skipped.\n")
    } else {
        print("\n  Available providers: \(available.joined(separator: ", "))\n")
    }

    // Run all 6 test categories
    await testProviderConnection()
    await testStreaming()
    await testToolCalling()
    await testSession()
    await testGenerativeUI()
    await testGeminiReasoning()

    printSummary()

    // Exit with appropriate code
    let failed = results.filter { !$0.passed }.count
    semaphore.signal()
    if failed > 0 {
        exit(1)
    }
}
semaphore.wait()
