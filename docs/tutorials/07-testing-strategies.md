# Testing Strategies

> Comprehensive testing approaches for AI applications

## Overview

Testing AI applications presents unique challenges: non-deterministic outputs, external API dependencies, and complex multi-step workflows. This tutorial covers strategies for reliable testing.

## Mock Language Model

AISDK provides `MockAILanguageModel` for deterministic testing.

### Basic Mocking

```swift
import XCTest
@testable import AISDK

final class AgentTests: XCTestCase {

    func test_agent_returns_text_response() async throws {
        // Create mock with predetermined responses
        let mock = MockAILanguageModel(
            responses: [
                .text("Hello! How can I help you?")
            ]
        )

        let agent = AIAgentActor(model: mock, tools: [])

        let result = try await agent.execute(
            messages: [.user("Hi")]
        )

        XCTAssertEqual(result.text, "Hello! How can I help you?")
    }
}
```

### Testing Tool Calls

```swift
func test_agent_calls_weather_tool() async throws {
    let mock = MockAILanguageModel(
        responses: [
            // First response: tool call
            .toolCall(name: "get_weather", arguments: #"{"city": "Tokyo"}"#),
            // Second response: final answer
            .text("The weather in Tokyo is 72F and sunny.")
        ]
    )

    let weatherTool = MockWeatherTool()
    let agent = AIAgentActor(
        model: mock,
        tools: [weatherTool]
    )

    let result = try await agent.execute(
        messages: [.user("What's the weather in Tokyo?")]
    )

    XCTAssertTrue(weatherTool.wasExecuted)
    XCTAssertEqual(weatherTool.lastCity, "Tokyo")
    XCTAssertTrue(result.text.contains("72F"))
}
```

### Testing Multi-Step Workflows

```swift
func test_agent_multi_step_research() async throws {
    let mock = MockAILanguageModel(
        responses: [
            // Step 1: Search
            .toolCall(name: "web_search", arguments: #"{"query": "Swift history"}"#),
            // Step 2: Wikipedia lookup
            .toolCall(name: "wikipedia", arguments: #"{"topic": "Swift (programming language)"}"#),
            // Step 3: Save note
            .toolCall(name: "save_note", arguments: #"{"title": "Swift Research"}"#),
            // Step 4: Final response
            .text("I've researched Swift and saved a note with my findings.")
        ]
    )

    let agent = AIAgentActor(
        model: mock,
        tools: [searchTool, wikiTool, noteTool]
    )

    let result = try await agent.execute(
        messages: [.user("Research Swift programming language")]
    )

    // Verify all tools were called
    XCTAssertEqual(mock.callCount, 4)
    XCTAssertTrue(result.text.contains("saved a note"))
}
```

### Configurable Delays

Test timeout handling:

```swift
func test_request_timeout() async throws {
    let mock = MockAILanguageModel(
        responses: [.text("Response")],
        delay: .seconds(5)  // Slow response
    )

    let agent = AIAgentActor(
        model: mock,
        tools: [],
        timeout: .seconds(1)  // Short timeout
    )

    do {
        _ = try await agent.execute(messages: [.user("Hi")])
        XCTFail("Should have timed out")
    } catch {
        XCTAssertTrue(error is TimeoutError)
    }
}
```

## Stress Testing

Test concurrent operations and resource handling.

### Concurrent Agent Executions

```swift
func test_100_concurrent_executions() async throws {
    let mock = MockAILanguageModel(
        responses: [.text("Response")]
    )

    var successCount = 0
    var errorCount = 0
    let lock = NSLock()

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<100 {
            group.addTask {
                let agent = AIAgentActor(model: mock, tools: [])
                do {
                    _ = try await agent.execute(messages: [.user("Test")])
                    lock.lock()
                    successCount += 1
                    lock.unlock()
                } catch {
                    lock.lock()
                    errorCount += 1
                    lock.unlock()
                }
            }
        }
    }

    XCTAssertGreaterThan(successCount, 90)
    print("Success: \(successCount), Errors: \(errorCount)")
}
```

### Circuit Breaker Under Load

```swift
func test_circuit_breaker_transitions() async throws {
    let breaker = AdaptiveCircuitBreaker(
        configuration: CircuitBreakerConfiguration(
            failureThreshold: 3,
            recoveryTimeout: .milliseconds(100)
        )
    )

    // Phase 1: Force failures to open circuit
    for _ in 0..<5 {
        await breaker.recordFailure()
    }

    let stateAfterFailures = await breaker.currentState
    if case .open = stateAfterFailures {
        // Expected
    } else {
        XCTFail("Circuit should be open after failures")
    }

    // Phase 2: Wait for recovery timeout
    try await Task.sleep(for: .milliseconds(150))

    let stateAfterWait = await breaker.currentState
    if case .halfOpen = stateAfterWait {
        // Expected
    } else {
        XCTFail("Circuit should be half-open after timeout")
    }

    // Phase 3: Record success to close
    await breaker.recordSuccess()
    await breaker.recordSuccess()

    let finalState = await breaker.currentState
    XCTAssertEqual(finalState, .closed)
}
```

## Memory Leak Detection

Verify proper cleanup of resources.

### Stream Deallocation

```swift
func test_streams_deallocate_after_completion() async throws {
    var weakRefs: [WeakRef<TestModel>] = []

    for _ in 0..<100 {
        let model = TestModel()
        weakRefs.append(WeakRef(model))

        // Consume stream
        Task {
            for try await _ in model.streamText(request: request) { }
        }
    }

    // Wait for cleanup
    try await Task.sleep(for: .milliseconds(100))

    // Count surviving references
    let aliveCount = weakRefs.filter { $0.value != nil }.count

    // Most should be deallocated
    XCTAssertLessThanOrEqual(aliveCount, 10)
}

// Helper class for weak reference tracking
private class WeakRef<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
```

### Agent Deallocation

```swift
func test_agents_deallocate_after_execution() async throws {
    var weakRefs: [WeakRef<AnyObject>] = []

    for _ in 0..<100 {
        let model = MockAILanguageModel(responses: [.text("Hi")])
        let agent = AIAgentActor(model: model, tools: [])

        weakRefs.append(WeakRef(agent as AnyObject))

        Task {
            _ = try? await agent.execute(messages: [.user("Test")])
        }
    }

    try await Task.sleep(for: .milliseconds(200))

    let deallocatedCount = weakRefs.filter { $0.value == nil }.count
    XCTAssertGreaterThan(deallocatedCount, 50)
}
```

## Integration Testing

Test with real providers (when API keys available).

```swift
final class OpenRouterIntegrationTests: XCTestCase {

    private func skipIfNoAPIKey() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] else {
            throw XCTSkip("OPENROUTER_API_KEY not set")
        }
        return key
    }

    func test_real_api_response() async throws {
        let apiKey = try skipIfNoAPIKey()
        let client = OpenRouterClient(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "google/gemma-3-4b-it:free",  // Free model
            messages: [.user("Say 'test' and nothing else")]
        )

        let response = try await client.execute(request: request)
        XCTAssertFalse(response.content.isEmpty)
    }

    func test_real_streaming() async throws {
        let apiKey = try skipIfNoAPIKey()
        let client = OpenRouterClient(apiKey: apiKey)

        var chunks: [String] = []

        for try await event in client.stream(request: request) {
            if case .textDelta(let text) = event {
                chunks.append(text)
            }
        }

        XCTAssertGreaterThan(chunks.count, 0)
    }
}
```

## Testing Generative UI

```swift
func test_ui_tree_parsing() throws {
    let json = """
    {
      "root": "main",
      "elements": {
        "main": {
          "type": "Stack",
          "props": { "direction": "vertical" },
          "children": ["title"]
        },
        "title": {
          "type": "Text",
          "props": { "content": "Hello" }
        }
      }
    }
    """

    let tree = try UITree.parse(
        from: json,
        validatingWith: UICatalog.core8
    )

    XCTAssertEqual(tree.rootKey, "main")
    XCTAssertEqual(tree.nodeCount, 2)
    XCTAssertEqual(tree.rootNode.type, "Stack")
}

func test_ui_validation_rejects_invalid_component() {
    let json = """
    {
      "root": "main",
      "elements": {
        "main": {
          "type": "InvalidComponent",
          "props": {}
        }
      }
    }
    """

    XCTAssertThrowsError(
        try UITree.parse(from: json, validatingWith: UICatalog.core8)
    ) { error in
        guard case UITreeError.unknownComponentType = error else {
            XCTFail("Wrong error type: \(error)")
            return
        }
    }
}
```

## Test Utilities

### StressTestMetrics

```swift
final class StressTestMetrics: @unchecked Sendable {
    private var _completed = 0
    private var _cancelled = 0
    private var _errors: [Error] = []
    private let lock = NSLock()

    var completedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _completed
    }

    func recordCompletion() {
        lock.lock()
        _completed += 1
        lock.unlock()
    }

    func recordCancellation() {
        lock.lock()
        _cancelled += 1
        lock.unlock()
    }

    func recordError(_ error: Error) {
        lock.lock()
        _errors.append(error)
        lock.unlock()
    }
}
```

### Test Helpers

```swift
extension XCTestCase {
    /// Wait for async condition with timeout
    func waitFor(
        timeout: Duration = .seconds(5),
        condition: @escaping () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTFail("Condition not met within timeout")
    }
}
```

## Best Practices

1. **Mock external APIs** - Use MockAILanguageModel for unit tests
2. **Test edge cases** - Empty responses, errors, timeouts
3. **Run stress tests** - Verify concurrent behavior
4. **Check for leaks** - Monitor object lifecycle
5. **Separate integration tests** - Skip when API keys unavailable
6. **Use deterministic seeds** - For any randomness in tests
7. **Test failure paths** - Ensure graceful error handling

## Running Tests

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter ConcurrencyStressTests

# Run with verbose output
swift test -v

# Run integration tests (requires API key)
OPENROUTER_API_KEY=xxx swift test --filter IntegrationTests
```

## Summary

| Test Type | Purpose | Tools |
|-----------|---------|-------|
| Unit | Single component | MockAILanguageModel |
| Stress | Concurrency | withTaskGroup, StressTestMetrics |
| Memory | Leak detection | WeakRef, autoreleasepool |
| Integration | Real APIs | XCTSkip for optional |
| UI | Generative UI | UITree.parse, UICatalog |
