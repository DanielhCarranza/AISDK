# Phase 6: Testing Infrastructure

**Duration**: 1 week
**Tasks**: 4
**Dependencies**: All previous phases

---

## Goal

Implement comprehensive testing with integration tests, stress tests, and memory leak detection.

---

## Context Files (Read First)

```
Tests/AISDKTests/AgentIntegrationTests.swift   # Current integration tests
Tests/AISDKTests/ToolTests.swift               # Current tool tests
Tests/AISDKTests/Mocks/MockLLMProvider.swift   # Current mock approach
docs/planning/external-review-feedback.md      # Missing test types
```

---

## Tasks

### Task 6.1: Integration Test Suite

**Location**: `Tests/AISDKTests/Integration/`
**Complexity**: 6/10
**Dependencies**: All phases

```swift
// IntegrationTestBase.swift
class IntegrationTestBase: XCTestCase {
    var openRouterClient: OpenRouterClient?
    var liteLLMClient: LiteLLMClient?

    override func setUp() {
        super.setUp()

        // Only initialize if API key present
        if let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
           !apiKey.isEmpty {
            openRouterClient = OpenRouterClient(apiKey: apiKey)
        }

        if let baseURL = ProcessInfo.processInfo.environment["LITELLM_BASE_URL"] {
            liteLLMClient = LiteLLMClient(baseURL: URL(string: baseURL)!)
        }
    }

    func skipIfNoAPIKey() throws {
        try XCTSkipIf(openRouterClient == nil, "OPENROUTER_API_KEY not set")
    }
}

// OpenRouterIntegrationTests.swift
final class OpenRouterIntegrationTests: IntegrationTestBase {
    func test_generateText_realAPI() async throws {
        try skipIfNoAPIKey()

        let request = AITextRequest(
            messages: [.user("Say 'hello' and nothing else")],
            model: "openai/gpt-4o-mini"
        )

        let result = try await openRouterClient!.generateText(request: request)

        XCTAssertTrue(result.text.lowercased().contains("hello"))
        XCTAssertEqual(result.finishReason, .stop)
        XCTAssertGreaterThan(result.usage.totalTokens, 0)
    }

    func test_streamText_realAPI() async throws {
        try skipIfNoAPIKey()

        let request = AITextRequest(
            messages: [.user("Count from 1 to 5")],
            model: "openai/gpt-4o-mini"
        )

        var events: [AIStreamEvent] = []
        for try await event in openRouterClient!.streamText(request: request) {
            events.append(event)
        }

        let textEvents = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }

        XCTAssertFalse(textEvents.isEmpty)
        XCTAssert(events.contains { if case .finish = $0 { return true }; return false })
    }

    func test_toolCalling_realAPI() async throws {
        try skipIfNoAPIKey()

        struct WeatherTool: AITool {
            static let name = "get_weather"
            static let description = "Get weather for a location"

            struct Arguments: Codable, Sendable {
                let location: String
            }

            static func execute(arguments: Arguments) async throws -> AIToolResult<EmptyMetadata> {
                AIToolResult(content: "Sunny, 72F in \(arguments.location)")
            }
        }

        let request = AITextRequest(
            messages: [.user("What's the weather in Tokyo?")],
            tools: [WeatherTool.self],
            model: "openai/gpt-4o-mini"
        )

        let result = try await openRouterClient!.generateText(request: request)

        XCTAssertFalse(result.toolCalls.isEmpty)
        XCTAssertEqual(result.toolCalls.first?.name, "get_weather")
    }
}

// FailoverIntegrationTests.swift
final class FailoverIntegrationTests: IntegrationTestBase {
    func test_failoverChain_firstProviderFails() async throws {
        try skipIfNoAPIKey()

        // Create chain with fault injector
        let faultInjector = FaultInjector()
        await faultInjector.inject(.error(.rateLimit(provider: "test", retryAfter: nil)), for: "openrouter")

        let executor = FailoverExecutor(
            chain: [openRouterClient!, liteLLMClient!].compactMap { $0 },
            faultInjector: faultInjector
        )

        let request = AITextRequest(messages: [.user("Hello")])

        let result = try await executor.execute(request: request) { provider, req in
            try await provider.generateText(request: req)
        }

        // Should have failed over to second provider
        XCTAssertEqual(result.attempts, 2)
    }
}
```

---

### Task 6.2: UI Snapshot Tests

**Location**: `Tests/AISDKTests/GenerativeUI/SnapshotTests.swift`
**Complexity**: 5/10
**Dependencies**: Phase 5

```swift
import XCTest
import SwiftUI
@testable import AISDK

final class GenerativeUISnapshotTests: XCTestCase {
    func test_textComponent_snapshot() {
        let element = UIElement(
            key: "text1",
            type: "Text",
            props: ["content": AnyCodable("Hello World")],
            children: nil,
            visible: nil
        )

        let view = GenerativeText(element: element)

        // Use a snapshot testing library like SnapshotTesting
        // assertSnapshot(matching: view, as: .image)
    }

    func test_buttonComponent_snapshot() {
        let element = UIElement(
            key: "btn1",
            type: "Button",
            props: [
                "title": AnyCodable("Submit"),
                "action": AnyCodable("submit_form")
            ],
            children: nil,
            visible: nil
        )

        let view = GenerativeButton(element: element) { _ in }

        // assertSnapshot(matching: view, as: .image)
    }

    func test_cardWithChildren_snapshot() {
        let tree = UITree(
            root: "card1",
            elements: [
                "card1": UIElement(
                    key: "card1",
                    type: "Card",
                    props: ["title": AnyCodable("Patient Info")],
                    children: ["text1", "btn1"],
                    visible: nil
                ),
                "text1": UIElement(
                    key: "text1",
                    type: "Text",
                    props: ["content": AnyCodable("John Doe")],
                    children: nil,
                    visible: nil
                ),
                "btn1": UIElement(
                    key: "btn1",
                    type: "Button",
                    props: ["title": AnyCodable("View Details")],
                    children: nil,
                    visible: nil
                )
            ]
        )

        // Snapshot full tree rendering
    }
}
```

---

### Task 6.3: ConcurrencyStressTests (NEW)

**Location**: `Tests/AISDKTests/Stress/ConcurrencyStressTests.swift`
**Complexity**: 5/10
**Dependencies**: Phases 1-4

```swift
import XCTest
@testable import AISDK

final class ConcurrencyStressTests: XCTestCase {
    func test_100_concurrent_agent_executions() async throws {
        let mock = MockAILanguageModel.withResponse("Test response")
        let agent = AIAgent(model: mock, tools: [])

        // Launch 100 concurrent executions
        try await withThrowingTaskGroup(of: AIAgentResult.self) { group in
            for i in 0..<100 {
                group.addTask {
                    try await agent.execute(messages: [.user("Request \(i)")])
                }
            }

            var results: [AIAgentResult] = []
            for try await result in group {
                results.append(result)
            }

            XCTAssertEqual(results.count, 100)
        }
    }

    func test_rapid_circuit_breaker_state_changes() async throws {
        let breaker = AdaptiveCircuitBreaker()

        // Rapidly toggle state
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 {
                group.addTask {
                    if Bool.random() {
                        await breaker.recordSuccess()
                    } else {
                        await breaker.recordFailure(error: .network(statusCode: 500, message: "Test"))
                    }
                }
            }

            for try await _ in group {}
        }

        // Should not crash, state should be consistent
        let allowed = await breaker.shouldAllow()
        XCTAssertNotNil(allowed)  // Just verify it returns without crash
    }

    func test_stream_cancellation_during_tool_execution() async throws {
        // Create tool that takes a while
        struct SlowTool: AITool {
            static let name = "slow"
            static let description = "Takes time"

            struct Arguments: Codable, Sendable {}

            static func execute(arguments: Arguments) async throws -> AIToolResult<EmptyMetadata> {
                try await Task.sleep(for: .seconds(10))
                return AIToolResult(content: "Done")
            }
        }

        let mock = MockAILanguageModel.withToolCall("slow", arguments: "{}")
        let agent = AIAgent(model: mock, tools: [SlowTool.self])

        let task = Task {
            let stream = agent.executeStream(messages: [.user("Run slow tool")])
            for try await _ in stream {}
        }

        // Cancel after 100ms
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        // Should cancel gracefully
        let result = await task.result
        XCTAssertThrowsError(try result.get())
    }

    func test_provider_failover_under_load() async throws {
        let faultInjector = FaultInjector()
        let mock1 = MockAILanguageModel(providerId: "provider1")
        let mock2 = MockAILanguageModel(providerId: "provider2")

        // Inject intermittent failures
        for i in 0..<50 {
            if i % 3 == 0 {
                await faultInjector.inject(
                    .error(.timeout(operation: "test", duration: 1)),
                    for: "provider1"
                )
            }
        }

        let executor = FailoverExecutor(
            chain: [mock1, mock2],
            faultInjector: faultInjector
        )

        // Run 100 requests concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    let request = AITextRequest(messages: [.user("Test")])
                    _ = try await executor.execute(request: request) { provider, req in
                        try await provider.generateText(request: req)
                    }
                }
            }

            for try await _ in group {}
        }
    }
}
```

---

### Task 6.4: MemoryLeakTests (NEW)

**Location**: `Tests/AISDKTests/Memory/StreamMemoryTests.swift`
**Complexity**: 4/10
**Dependencies**: Phase 1

```swift
import XCTest
@testable import AISDK

final class StreamMemoryTests: XCTestCase {
    func test_stream_deallocation_after_completion() async throws {
        weak var weakStream: AnyObject?

        autoreleasepool {
            let mock = MockAILanguageModel.withResponse("Test")
            let stream = mock.streamText(request: AITextRequest(messages: [.user("Hi")]))

            weakStream = stream as AnyObject

            // Consume stream
            for try await _ in stream {}
        }

        // Stream should be deallocated
        XCTAssertNil(weakStream)
    }

    func test_stream_deallocation_after_error() async throws {
        weak var weakStream: AnyObject?

        autoreleasepool {
            let mock = MockAILanguageModel.failing(with: .network(statusCode: 500, message: "Test"))
            let stream = mock.streamText(request: AITextRequest(messages: [.user("Hi")]))

            weakStream = stream as AnyObject

            do {
                for try await _ in stream {}
            } catch {
                // Expected
            }
        }

        XCTAssertNil(weakStream)
    }

    func test_stream_deallocation_after_cancellation() async throws {
        weak var weakStream: AnyObject?

        autoreleasepool {
            let mock = MockAILanguageModel.withSlowResponse(delay: .seconds(10))
            let stream = mock.streamText(request: AITextRequest(messages: [.user("Hi")]))

            weakStream = stream as AnyObject

            let task = Task {
                for try await _ in stream {}
            }

            try await Task.sleep(for: .milliseconds(100))
            task.cancel()
            _ = await task.result
        }

        // Allow cleanup
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(weakStream)
    }

    func test_no_retain_cycles_in_step_callbacks() async throws {
        weak var weakAgent: AIAgent?

        autoreleasepool {
            let mock = MockAILanguageModel.withResponse("Test")
            let agent = AIAgent(model: mock, stopCondition: .stepCount(1))

            weakAgent = agent

            // Use callback that doesn't capture agent
            let stream = agent.executeStream(
                messages: [.user("Hi")],
                onStepFinish: { _ in .continue }
            )

            for try await _ in stream {}
        }

        // Agent should be deallocated
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(weakAgent)
    }

    func test_viewModel_releases_stream_on_deinit() async throws {
        weak var weakViewModel: GenerativeUIViewModel?

        autoreleasepool {
            let events: [AIStreamEvent] = [
                .textDelta("{\"root\":\"a\",\"elements\":{}}"),
                .finish(finishReason: .stop, usage: .zero)
            ]
            let stream = simulateStream(events: events)
            let viewModel = GenerativeUIViewModel(stream: stream)

            weakViewModel = viewModel

            await viewModel.startProcessing()
        }

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(weakViewModel)
    }
}
```

---

## CI Configuration

```yaml
# .github/workflows/tests.yml
name: Tests

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Run Unit Tests
        run: swift test --filter "^(?!.*Integration).*$"

  integration-tests:
    runs-on: macos-14
    env:
      OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
    steps:
      - uses: actions/checkout@v4
      - name: Run Integration Tests
        run: swift test --filter "Integration"

  stress-tests:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Run Stress Tests
        run: swift test --filter "Stress"

  memory-tests:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Run Memory Tests
        run: swift test --filter "Memory"
```

---

## Verification

```bash
# All tests
swift test

# By category
swift test --filter "Unit"
swift test --filter "Integration"
swift test --filter "Stress"
swift test --filter "Memory"
```
