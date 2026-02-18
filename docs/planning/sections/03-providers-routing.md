# Phase 2: Provider & Routing Layer

**Duration**: 2 weeks
**Tasks**: 8
**Dependencies**: Phase 1

---

## Goal

Implement model-agnostic routing with OpenRouter as primary and LiteLLM as secondary, with capability-aware model selection.

---

## Context Files (Read First)

```
Sources/AISDK/LLMs/OpenAI/OpenAIProvider.swift      # Current OpenAI (661 lines)
Sources/AISDK/LLMs/Anthropic/AnthropicProvider.swift # Current Anthropic (367 lines)
Sources/AISDK/LLMs/Gemini/GeminiProvider.swift       # Current Gemini (344 lines)
Sources/AISDK/LLMs/LLMModelProtocol.swift           # Model capabilities
docs/planning/interview-transcript.md               # OpenRouter = primary
```

---

## Tasks

### Task 2.1: ProviderClient Protocol

**Location**: `Sources/AISDK/Core/Routing/ProviderClient.swift`
**Complexity**: 5/10
**Dependencies**: Phase 1

```swift
/// Standard interface for all providers and routers
public protocol ProviderClient: Actor, Sendable {
    var providerId: String { get }
    var supportedModels: [String] { get }
    var capabilities: LLMCapabilities { get }
    var healthStatus: ProviderHealthStatus { get }

    func generate(request: ProviderRequest) async throws -> ProviderResponse
    func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error>
}

public struct ProviderRequest: Sendable {
    public let messages: [AIMessage]
    public let model: String
    public let parameters: ProviderParameters
    public let traceContext: AITraceContext
}

public struct ProviderResponse: Sendable {
    public let text: String
    public let toolCalls: [AIToolCall]
    public let finishReason: AIFinishReason
    public let usage: AIUsage
}
```

**Test-First**:
```
Tests/AISDKTests/Routing/ProviderClientTests.swift
- test_protocol_conformance
- test_capability_flags_exposed
- test_health_status_queryable
```

---

### Task 2.2: OpenRouterClient (Primary)

**Location**: `Sources/AISDK/Core/Routing/OpenRouterClient.swift`
**Complexity**: 8/10
**Dependencies**: Task 2.1

```swift
/// OpenRouter client - primary routing solution
public actor OpenRouterClient: ProviderClient {
    public let providerId = "openrouter"

    private let apiKey: String
    private let baseURL: URL
    private let defaultModel: String
    private let session: URLSession
    private let sseParser: SSEParser

    public init(
        apiKey: String = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? "",
        baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!,
        defaultModel: String = "openai/gpt-5-mini"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.session = URLSession(configuration: .ephemeral)
        self.sseParser = SSEParser()
    }

    public var supportedModels: [String] {
        // Return cached model list or fetch
    }

    public func generate(request: ProviderRequest) async throws -> ProviderResponse {
        let urlRequest = try buildRequest(request, stream: false)
        let (data, response) = try await session.data(for: urlRequest)
        try validateResponse(response)
        return try decodeResponse(data)
    }

    public func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        SafeAsyncStream.make { [self] continuation in
            let urlRequest = try buildRequest(request, stream: true)
            let (bytes, response) = try await session.bytes(for: urlRequest)
            try validateResponse(response)

            for try await line in bytes.lines {
                if let chunk = sseParser.parse(line: line) {
                    continuation.yield(chunk)
                }
            }
        }
    }

    /// Resolve model aliases (e.g., "gpt-5" -> "openai/gpt-5")
    private func resolveModelAlias(_ model: String) -> String {
        // Handle common aliases
    }
}
```

**Test-First**:
```
Tests/AISDKTests/Routing/OpenRouterClientTests.swift
- test_generate_text_success (mock)
- test_stream_text_events (mock)
- test_model_alias_resolution
- test_auth_header_included
- test_error_response_handling

Tests/AISDKTests/Routing/OpenRouterIntegrationTests.swift
- test_real_api_generate_text (gated)
- test_real_api_stream_text (gated)
```

---

### Task 2.3: LiteLLMClient (Secondary)

**Location**: `Sources/AISDK/Core/Routing/LiteLLMClient.swift`
**Complexity**: 6/10
**Dependencies**: Task 2.1

```swift
/// LiteLLM client - self-hosted routing option
public actor LiteLLMClient: ProviderClient {
    public let providerId = "litellm"

    private let baseURL: URL
    private let apiKey: String?

    public init(
        baseURL: URL = URL(string: ProcessInfo.processInfo.environment["LITELLM_BASE_URL"] ?? "http://localhost:4000")!,
        apiKey: String? = ProcessInfo.processInfo.environment["LITELLM_API_KEY"]
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    // Same interface as OpenRouterClient
}
```

---

### Task 2.4: ModelRegistry

**Location**: `Sources/AISDK/Core/Routing/ModelRegistry.swift`
**Complexity**: 6/10
**Dependencies**: Phase 1

```swift
/// Capability-aware model selection
public actor ModelRegistry {
    public static let shared = ModelRegistry()

    private var models: [String: LLMModel] = [:]

    /// Resolve best model for request
    public func resolve(
        request: AITextRequest,
        preferredProvider: String? = nil,
        requiredCapabilities: LLMCapabilities = [],
        maxCostTier: CostTier? = nil
    ) -> ResolvedModel? {
        models.values
            .filter { $0.capabilities.contains(requiredCapabilities) }
            .filter { maxCostTier == nil || $0.costTier <= maxCostTier! }
            .filter { preferredProvider == nil || $0.provider.rawValue == preferredProvider }
            .sorted { $0.costTier < $1.costTier }
            .first
            .map { ResolvedModel(from: $0) }
    }

    /// Register models from provider
    public func register(models: [LLMModel]) {
        for model in models {
            self.models[model.id] = model
        }
    }
}

public struct ResolvedModel: Sendable {
    public let provider: String
    public let modelId: String
    public let capabilities: LLMCapabilities
    public let costTier: CostTier
    public let latencyTier: LatencyTier
    public let maxContextTokens: Int
}
```

---

### Task 2.5: OpenAIClientAdapter

**Location**: `Sources/AISDK/Core/Adapters/OpenAIClientAdapter.swift`
**Complexity**: 6/10
**Dependencies**: Task 2.1

Wrap existing `OpenAIProvider` to conform to `ProviderClient`.

---

### Task 2.6: AnthropicClientAdapter

**Location**: `Sources/AISDK/Core/Adapters/AnthropicClientAdapter.swift`
**Complexity**: 4/10
**Dependencies**: Task 2.1

Preserve Claude-specific constraints (n=1, temp <= 1.0).

---

### Task 2.7: GeminiClientAdapter

**Location**: `Sources/AISDK/Core/Adapters/GeminiClientAdapter.swift`
**Complexity**: 7/10
**Dependencies**: Task 2.1

Fix return type inconsistency (AsyncCompactMapSequence -> AsyncThrowingStream).

---

### Task 2.8: ProviderContractTests

**Location**: `Tests/AISDKTests/Providers/Contracts/ProviderContractTests.swift`
**Complexity**: 5/10
**Dependencies**: Tasks 2.5-2.7

```swift
/// Contract tests all providers must pass
protocol ProviderContractTestable {
    var provider: any ProviderClient { get }
}

extension ProviderContractTestable {
    func testGenerateText() async throws {
        let request = ProviderRequest.testRequest
        let response = try await provider.generate(request: request)
        XCTAssertFalse(response.text.isEmpty)
    }

    func testStreamEmitsEvents() async throws {
        let request = ProviderRequest.testRequest
        var events: [ProviderChunk] = []
        for try await chunk in provider.stream(request: request) {
            events.append(chunk)
        }
        XCTAssert(events.count > 0)
    }
}
```

---

## Parallel Opportunities

- Tasks 2.2 and 2.3 can run in parallel
- Tasks 2.5, 2.6, 2.7 can run in parallel

---

## Verification

```bash
swift test --filter "Routing"
swift test --filter "Adapters"
swift test --filter "Contracts"
```
