//
//  ProviderClient.swift
//  AISDK
//
//  Low-level protocol for AI provider client implementations
//  Provides a common interface for routing layer to communicate with providers
//

import Foundation

// MARK: - ProviderClient Protocol

/// Low-level protocol for AI provider HTTP client implementations.
///
/// This protocol abstracts the communication layer between the routing system
/// and individual AI providers (OpenRouter, LiteLLM, OpenAI, Anthropic, etc.).
/// Unlike `LLM` which provides high-level semantics, `ProviderClient`
/// focuses on the raw request/response mechanics.
///
/// ## Design Rationale
/// - Separates transport concerns from model semantics
/// - Enables provider-specific optimizations (batching, caching, retries)
/// - Supports the reliability layer (circuit breaker, failover)
/// - Thread-safe by design (Sendable requirement)
///
/// ## Anticipated Implementors
/// These types will be implemented in subsequent tasks:
/// - `OpenRouterClient`: Primary production router
/// - `LiteLLMClient`: Secondary/fallback router
/// - Provider-specific adapters for direct access
public protocol ProviderClient: Sendable {
    // MARK: - Identity

    /// Unique identifier for this provider client (e.g., "openrouter", "litellm", "openai-direct")
    var providerId: String { get }

    /// Human-readable display name
    var displayName: String { get }

    /// Base URL for the provider's API
    var baseURL: URL { get }

    // MARK: - Health & Status

    /// Current health status of the provider
    var healthStatus: ProviderHealthStatus { get async }

    /// Check if the provider is currently available for requests
    var isAvailable: Bool { get async }

    // MARK: - Request Execution

    /// Execute a text generation request (non-streaming)
    /// - Parameter request: The provider-level request
    /// - Returns: The provider-level response
    /// - Throws: `ProviderError` for transport or provider-specific errors
    func execute(request: ProviderRequest) async throws -> ProviderResponse

    /// Execute a streaming text generation request
    ///
    /// Errors during streaming are communicated by throwing from the stream.
    /// The stream should end with a `.finish` event on successful completion.
    ///
    /// - Parameter request: The provider-level request
    /// - Returns: An async stream of provider events that throws on error
    func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error>

    // MARK: - Model Information

    /// List of model IDs available through this provider
    var availableModels: [String] { get async throws }

    /// Check if a specific model is available
    /// - Parameter modelId: The model identifier to check
    /// - Returns: True if the model is available through this provider
    func isModelAvailable(_ modelId: String) async -> Bool

    /// Get capabilities for a specific model
    /// - Parameter modelId: The model identifier
    /// - Returns: The model's capabilities, or nil if unknown
    func capabilities(for modelId: String) async -> LLMCapabilities?
}

// MARK: - Default Implementations

public extension ProviderClient {
    /// Default implementation checks if model is in available models list
    func isModelAvailable(_ modelId: String) async -> Bool {
        do {
            let models = try await availableModels
            return models.contains(modelId)
        } catch {
            return false
        }
    }

    /// Default implementation returns nil (unknown capabilities)
    func capabilities(for modelId: String) async -> LLMCapabilities? {
        return nil
    }
}

// MARK: - Provider Health Status

/// Health status of a provider client
///
/// Note: `.unknown` does not accept traffic by default. Routing implementations
/// should proactively refresh health status before first use to ensure providers
/// become "known" before receiving traffic.
public enum ProviderHealthStatus: Sendable, Equatable {
    /// Provider is healthy and accepting requests
    case healthy

    /// Provider is experiencing issues but may still work
    case degraded(reason: String)

    /// Provider is unhealthy and should not receive requests
    case unhealthy(reason: String)

    /// Health status is unknown (e.g., never checked)
    case unknown

    /// Whether the provider should receive traffic
    public var acceptsTraffic: Bool {
        switch self {
        case .healthy, .degraded:
            return true
        case .unhealthy, .unknown:
            return false
        }
    }
}

// MARK: - ProviderJSONValue

/// A Sendable, Codable JSON value type for provider request parameters.
///
/// This replaces `[String: Any]` in contexts where Sendable conformance is required.
public enum ProviderJSONValue: Sendable, Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ProviderJSONValue])
    case object([String: ProviderJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([ProviderJSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: ProviderJSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.typeMismatch(
                ProviderJSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode JSON value")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Provider Request

/// A request to be sent to a provider client
///
/// This is a transport-level request that contains all information needed
/// to make an HTTP request to the provider. It maps from `AITextRequest`
/// but includes provider-specific details.
public struct ProviderRequest: Sendable {
    /// The model to use for generation
    public let modelId: String

    /// Messages in provider-neutral format
    public let messages: [AIMessage]

    /// Maximum tokens to generate
    public let maxTokens: Int?

    /// Temperature for generation (0-2)
    public let temperature: Double?

    /// Top-p sampling parameter
    public let topP: Double?

    /// Stop sequences
    public let stop: [String]?

    /// Whether to stream the response
    public let stream: Bool

    /// Tools available for the model (as Sendable JSON)
    public let tools: [ProviderJSONValue]?

    /// Tool choice behavior
    public let toolChoice: ProviderToolChoice?

    /// Built-in provider tools (passed through for adapter-specific mapping)
    public let builtInTools: [BuiltInTool]?

    /// Response format specification
    public let responseFormat: ProviderResponseFormat?

    /// Reasoning/thinking configuration (provider-agnostic)
    public let reasoning: AIReasoningConfig?

    /// Prompt/context caching configuration (provider-agnostic)
    public let caching: AICacheConfig?

    /// Request timeout in seconds
    public let timeout: TimeInterval

    /// Additional provider-specific parameters (Sendable JSON)
    public let providerOptions: [String: ProviderJSONValue]?

    /// Trace context for observability
    public let traceContext: AITraceContext?

    /// Request metadata for tracing
    public let metadata: [String: String]?

    public init(
        modelId: String,
        messages: [AIMessage],
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stop: [String]? = nil,
        stream: Bool = false,
        tools: [ProviderJSONValue]? = nil,
        toolChoice: ProviderToolChoice? = nil,
        builtInTools: [BuiltInTool]? = nil,
        responseFormat: ProviderResponseFormat? = nil,
        reasoning: AIReasoningConfig? = nil,
        caching: AICacheConfig? = nil,
        timeout: TimeInterval = 120,
        providerOptions: [String: ProviderJSONValue]? = nil,
        traceContext: AITraceContext? = nil,
        metadata: [String: String]? = nil
    ) {
        self.modelId = modelId
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stop = stop
        self.stream = stream
        self.tools = tools
        self.toolChoice = toolChoice
        self.builtInTools = builtInTools
        self.responseFormat = responseFormat
        self.reasoning = reasoning
        self.caching = caching
        self.timeout = timeout
        self.providerOptions = providerOptions
        self.traceContext = traceContext
        self.metadata = metadata
    }
}

// MARK: - Provider Tool Choice

/// Tool choice specification for provider requests
public enum ProviderToolChoice: Sendable, Equatable {
    /// Let the model decide whether to use tools
    case auto

    /// Model must not use any tools
    case none

    /// Model must use a tool
    case required

    /// Model must use the specified tool
    case tool(name: String)
}

// MARK: - Provider Response Format

/// Response format specification for provider requests
public enum ProviderResponseFormat: Sendable, Equatable {
    /// Plain text response
    case text

    /// JSON object response
    case json

    /// JSON object conforming to a schema
    case jsonSchema(name: String, schema: String)
}

// MARK: - Provider Response

/// A response from a provider client
public struct ProviderResponse: Sendable {
    /// Unique identifier for this response
    public let id: String

    /// The model that generated the response
    public let model: String

    /// The provider that handled the request
    public let provider: String

    /// Generated text content
    public let content: String

    /// Tool calls made by the model
    public let toolCalls: [ProviderToolCall]

    /// Token usage information (nil if not provided by provider)
    public let usage: ProviderUsage?

    /// Reason for completion
    public let finishReason: ProviderFinishReason

    /// Response latency in milliseconds
    public let latencyMs: Int?

    /// Additional provider-specific metadata
    public let metadata: [String: String]?

    /// Sources/citations from the response
    public let sources: [AISource]

    public init(
        id: String,
        model: String,
        provider: String,
        content: String,
        toolCalls: [ProviderToolCall] = [],
        usage: ProviderUsage? = nil,
        finishReason: ProviderFinishReason,
        latencyMs: Int? = nil,
        metadata: [String: String]? = nil,
        sources: [AISource] = []
    ) {
        self.id = id
        self.model = model
        self.provider = provider
        self.content = content
        self.toolCalls = toolCalls
        self.usage = usage
        self.finishReason = finishReason
        self.latencyMs = latencyMs
        self.metadata = metadata
        self.sources = sources
    }
}

// MARK: - Provider Tool Call

/// A tool call from a provider response
public struct ProviderToolCall: Sendable, Codable, Equatable {
    /// Unique identifier for the tool call
    public let id: String

    /// Name of the tool to call
    public let name: String

    /// JSON-encoded arguments for the tool
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - Provider Usage

/// Token usage information from a provider
public struct ProviderUsage: Sendable, Equatable {
    /// Number of tokens in the prompt
    public let promptTokens: Int

    /// Number of tokens generated
    public let completionTokens: Int

    /// Total tokens (prompt + completion)
    public var totalTokens: Int {
        promptTokens + completionTokens
    }

    /// Cached tokens (if applicable)
    public let cachedTokens: Int?

    /// Reasoning tokens (for o1/o3 models)
    public let reasoningTokens: Int?

    public init(
        promptTokens: Int,
        completionTokens: Int,
        cachedTokens: Int? = nil,
        reasoningTokens: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cachedTokens = cachedTokens
        self.reasoningTokens = reasoningTokens
    }

    /// Zero usage for initialization
    public static let zero = ProviderUsage(promptTokens: 0, completionTokens: 0)
}

// MARK: - Provider Finish Reason

/// Reason for completion from a provider
///
/// Uses custom Codable implementation to gracefully handle unknown finish reasons
/// from providers, mapping them to `.unknown` instead of throwing.
public enum ProviderFinishReason: String, Sendable, Equatable {
    /// Normal completion (stop token reached)
    case stop

    /// Maximum tokens reached
    case length

    /// Model made tool calls
    case toolCalls = "tool_calls"

    /// Content was filtered
    case contentFilter = "content_filter"

    /// Function call (legacy)
    case functionCall = "function_call"

    /// Unknown or unspecified reason
    case unknown

    /// Initialize from a provider's finish reason string
    /// Always succeeds - unknown values map to `.unknown`
    public init(providerReason: String?) {
        guard let reason = providerReason?.lowercased() else {
            self = .unknown
            return
        }

        switch reason {
        case "stop", "end_turn", "stop_sequence":
            self = .stop
        case "length", "max_tokens":
            self = .length
        case "tool_calls", "tool_use":
            self = .toolCalls
        case "function_call":
            self = .functionCall
        case "content_filter", "safety":
            self = .contentFilter
        default:
            self = .unknown
        }
    }
}

// MARK: - ProviderFinishReason Codable

extension ProviderFinishReason: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self.init(providerReason: rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Provider Stream Event

/// Events emitted during streaming from a provider
///
/// Note: Errors during streaming should be communicated by throwing from the
/// `AsyncThrowingStream`, not via `.error` events. This enum exists for
/// compatibility but stream implementations should prefer throwing.
public enum ProviderStreamEvent: Sendable {
    /// Stream has started
    case start(id: String, model: String)

    /// Partial text content
    case textDelta(String)

    /// Tool call started
    case toolCallStart(id: String, name: String)

    /// Tool call arguments delta
    case toolCallDelta(id: String, argumentsDelta: String)

    /// Tool call finished
    case toolCallFinish(id: String, name: String, arguments: String)

    /// Result from executing a tool
    case toolResult(id: String, result: String, metadata: ToolMetadata?)

    /// Reasoning delta (for o1/o3 models)
    case reasoningDelta(String)

    /// Source/citation information
    case source(AISource)

    /// Web search initiated with query
    case webSearchStarted(query: String)

    /// Web search completed with results
    case webSearchCompleted(AIWebSearchResult)

    /// Usage information
    case usage(ProviderUsage)

    /// Stream finished
    case finish(reason: ProviderFinishReason, usage: ProviderUsage?)
}

// MARK: - Provider Error

/// Errors that can occur during provider communication
public enum ProviderError: Error, Sendable, Equatable, LocalizedError {
    /// Invalid request parameters
    case invalidRequest(String)

    /// Authentication failed
    case authenticationFailed(String)

    /// Rate limit exceeded
    case rateLimited(retryAfter: TimeInterval?)

    /// Model not found or not available
    case modelNotFound(String)

    /// Request timeout
    case timeout(TimeInterval)

    /// Server error from provider
    case serverError(statusCode: Int, message: String)

    /// Network connectivity issue
    case networkError(String)

    /// Response parsing failed
    case parseError(String)

    /// Content was filtered/blocked
    case contentFiltered(String)

    /// Provider-specific error
    case providerSpecific(code: String, message: String)

    /// Unsupported modality for the target provider
    case unsupportedModality(modality: String, provider: String, supportedProviders: [String])

    /// Unknown error
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds)) seconds."
            }
            return "Rate limited."
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .timeout(let duration):
            return "Request timed out after \(Int(duration)) seconds."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .contentFiltered(let message):
            return "Content filtered: \(message)"
        case .providerSpecific(let code, let message):
            return "Provider error [\(code)]: \(message)"
        case .unsupportedModality(let modality, let provider, let supportedProviders):
            let supported = supportedProviders.isEmpty ? "none" : supportedProviders.joined(separator: ", ")
            return "Unsupported modality: '\(modality)' is not supported by \(provider). Providers that support \(modality): \(supported)."
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}

// MARK: - Conversion Extensions

public extension ProviderResponse {
    /// Convert to AITextResult for the unified API layer
    func toAITextResult() -> AITextResult {
        AITextResult(
            text: content,
            toolCalls: toolCalls.map { ToolCallResult(id: $0.id, name: $0.name, arguments: $0.arguments) },
            usage: usage?.toAIUsage() ?? .zero,
            finishReason: finishReason.toAIFinishReason(),
            requestId: id,
            model: model,
            provider: provider,
            sources: sources,
            providerMetadata: metadata
        )
    }
}

public extension ProviderUsage {
    /// Convert to AIUsage for the unified API layer
    func toAIUsage() -> AIUsage {
        AIUsage(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            reasoningTokens: reasoningTokens,
            cachedTokens: cachedTokens
        )
    }
}

public extension ProviderFinishReason {
    /// Convert to AIFinishReason for the unified API layer
    func toAIFinishReason() -> AIFinishReason {
        switch self {
        case .stop:
            return .stop
        case .length:
            return .length
        case .toolCalls, .functionCall:
            return .toolCalls
        case .contentFilter:
            return .contentFilter
        case .unknown:
            return .unknown
        }
    }
}

public extension ProviderStreamEvent {
    /// Convert to AIStreamEvent for the unified API layer
    ///
    /// All ProviderStreamEvents map to an AIStreamEvent.
    func toAIStreamEvent() -> AIStreamEvent {
        switch self {
        case .start(let id, let model):
            return .start(metadata: AIStreamMetadata(requestId: id, model: model))
        case .textDelta(let text):
            return .textDelta(text)
        case .toolCallStart(let id, let name):
            return .toolCallStart(id: id, name: name)
        case .toolCallDelta(let id, let delta):
            return .toolCallDelta(id: id, argumentsDelta: delta)
        case .toolCallFinish(let id, let name, let args):
            return .toolCallFinish(id: id, name: name, arguments: args)
        case .toolResult(let id, let result, let metadata):
            return .toolResult(id: id, result: result, metadata: metadata)
        case .reasoningDelta(let text):
            return .reasoningDelta(text)
        case .source(let source):
            return .source(source)
        case .webSearchStarted(let query):
            return .webSearchStarted(query: query)
        case .webSearchCompleted(let result):
            return .webSearchCompleted(result)
        case .usage(let usage):
            return .usage(usage.toAIUsage())
        case .finish(let reason, let usage):
            return .finish(finishReason: reason.toAIFinishReason(), usage: usage?.toAIUsage() ?? .zero)
        }
    }
}

// MARK: - Request Conversion

public extension AITextRequest {
    /// Convert to ProviderRequest for the transport layer
    ///
    /// Note: Tool schemas are converted to ProviderJSONValue for provider requests.
    ///
    /// - Parameters:
    ///   - modelId: Fallback model ID if request.model is nil
    ///   - stream: Whether to enable streaming
    /// - Throws: `ResponseFormatConversionError` if JSON schema encoding fails
    func toProviderRequest(modelId: String, stream: Bool = false) throws -> ProviderRequest {
        let providerJSONOptions = providerOptions as? [String: ProviderJSONValue]
        return ProviderRequest(
            modelId: model ?? modelId,
            messages: messages,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stop: stop,
            stream: stream,
            tools: try tools?.map { try $0.toProviderJSONValue() },
            toolChoice: toolChoice?.toProviderToolChoice(),
            builtInTools: builtInTools,
            responseFormat: try responseFormat?.toProviderResponseFormat(),
            reasoning: reasoning,
            caching: caching,
            timeout: 120,
            providerOptions: providerJSONOptions,
            traceContext: nil,
            metadata: metadata
        )
    }
}

// MARK: - ToolSchema Conversion

public extension ToolSchema {
    /// Convert ToolSchema to ProviderJSONValue for ProviderClient requests.
    /// - Throws: `ResponseFormatConversionError` if JSON encoding fails
    func toProviderJSONValue() throws -> ProviderJSONValue {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(self)
            return try JSONDecoder().decode(ProviderJSONValue.self, from: data)
        } catch {
            throw ResponseFormatConversionError(message: "Failed to encode tool schema '\(function?.name ?? "unknown")'")
        }
    }
}

public extension ToolChoice {
    /// Convert to ProviderToolChoice
    func toProviderToolChoice() -> ProviderToolChoice {
        switch self {
        case .auto:
            return .auto
        case .none:
            return .none
        case .required:
            return .required
        case .function(let functionChoice):
            return .tool(name: functionChoice.name)
        }
    }
}

/// Error thrown when response format conversion fails
public struct ResponseFormatConversionError: Error, LocalizedError {
    public let message: String

    public var errorDescription: String? {
        "Failed to convert response format: \(message)"
    }
}

public extension ResponseFormat {
    /// Convert to ProviderResponseFormat
    /// - Throws: `ResponseFormatConversionError` if JSON schema encoding fails
    func toProviderResponseFormat() throws -> ProviderResponseFormat {
        switch self {
        case .text:
            return .text
        case .jsonObject:
            return .json
        case .jsonSchema(let name, _, let schemaBuilder, _):
            // Convert schema to JSON string
            let schema = schemaBuilder.build()
            // JSONSchema.rawValue is [String: AnyEncodable], encode it to JSON
            let encoder = JSONEncoder()
            guard let schemaData = try? encoder.encode(schema),
                  let schemaString = String(data: schemaData, encoding: .utf8) else {
                throw ResponseFormatConversionError(message: "Failed to encode JSON schema '\(name)'")
            }
            return .jsonSchema(name: name, schema: schemaString)
        }
    }
}
