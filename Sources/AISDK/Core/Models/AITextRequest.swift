//
//  AITextRequest.swift
//  AISDK
//
//  Request model for text generation operations
//  Based on Vercel AI SDK 6.x patterns
//

import Foundation

/// Request for text generation
///
/// Note: Marked as `@unchecked Sendable` because it contains legacy types
/// (`ToolSchema`, `ToolChoice`, `ResponseFormat`) that don't have `Sendable` conformance.
/// These are immutable value types used only within a single request context.
/// Making these types Sendable is tracked for Phase 2 (Provider & Routing Layer).
public struct AITextRequest: @unchecked Sendable {
    /// The messages to send to the model
    public let messages: [AIMessage]

    /// The model to use (optional, uses default if nil)
    public let model: String?

    /// Maximum tokens to generate
    public let maxTokens: Int?

    /// Temperature for generation (0-2)
    public let temperature: Double?

    /// Top-p sampling parameter
    public let topP: Double?

    /// Stop sequences
    public let stop: [String]?

    /// Tools available for the model to use
    public let tools: [ToolSchema]?

    /// Tool choice behavior
    public let toolChoice: ToolChoice?

    /// Built-in provider tools (web search, code execution, etc.)
    /// These run server-side and don't need local execution.
    public let builtInTools: [BuiltInTool]?

    /// Response format specification
    public let responseFormat: ResponseFormat?

    /// Reasoning/thinking configuration (provider-agnostic)
    public let reasoning: AIReasoningConfig?

    /// Prompt/context caching configuration (provider-agnostic)
    public let caching: AICacheConfig?

    /// Allowed providers for PHI protection (nil allows all)
    public let allowedProviders: Set<String>?

    /// Data sensitivity classification
    public let sensitivity: DataSensitivity

    /// Stream buffer policy for memory control.
    /// Note: Currently metadata-only. Will be plumbed through streaming in Phase 3 (Reliability Layer).
    public let bufferPolicy: StreamBufferPolicy?

    /// Request metadata for tracing
    public let metadata: [String: String]?

    /// Conversation ID for multi-turn conversations
    /// For OpenAI: This maps to `previousResponseId` for server-side context
    public var conversationId: String?

    /// Provider-specific options (type-erased for multi-provider support)
    /// For OpenAI: Use `OpenAIRequestOptions`
    /// Example: `request.providerOptions = OpenAIRequestOptions()`
    public var providerOptions: (any Sendable)?

    public init(
        messages: [AIMessage],
        model: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stop: [String]? = nil,
        tools: [ToolSchema]? = nil,
        toolChoice: ToolChoice? = nil,
        builtInTools: [BuiltInTool]? = nil,
        responseFormat: ResponseFormat? = nil,
        reasoning: AIReasoningConfig? = nil,
        caching: AICacheConfig? = nil,
        allowedProviders: Set<String>? = nil,
        sensitivity: DataSensitivity = .standard,
        bufferPolicy: StreamBufferPolicy? = nil,
        metadata: [String: String]? = nil,
        conversationId: String? = nil,
        providerOptions: (any Sendable)? = nil
    ) {
        self.messages = messages
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stop = stop
        self.tools = tools
        self.toolChoice = toolChoice
        self.builtInTools = builtInTools
        self.responseFormat = responseFormat
        self.reasoning = reasoning
        self.caching = caching
        self.allowedProviders = allowedProviders
        self.sensitivity = sensitivity
        self.bufferPolicy = bufferPolicy
        self.metadata = metadata
        self.conversationId = conversationId
        self.providerOptions = providerOptions
    }
}

// MARK: - Data Sensitivity

/// Data sensitivity classification for PHI protection
public enum DataSensitivity: String, Sendable, Codable, Equatable {
    /// Standard data, can use any provider
    case standard
    /// Sensitive data, requires trusted providers
    case sensitive
    /// PHI data, requires HIPAA-compliant providers
    case phi
}

// MARK: - Stream Buffer Policy

/// Stream buffer policy for memory control.
/// Maps to Swift's AsyncStream/AsyncThrowingStream buffering policies.
///
/// Note: Swift's built-in streams support unbounded, dropOldest, and dropNewest behaviors.
/// Use the `bounded(capacity:dropOldest:)` factory method for validated capacity (> 0).
/// Direct enum case initialization does not validate capacity.
public enum StreamBufferPolicy: Sendable, Equatable {
    /// Unbounded buffer - no limit on events (use with caution for memory)
    case unbounded
    /// Bounded buffer that drops oldest events when full. Use factory for validation.
    case dropOldest(capacity: Int)
    /// Bounded buffer that drops newest events when full. Use factory for validation.
    case dropNewest(capacity: Int)

    /// The effective capacity of the buffer (Int.max for unbounded)
    public var capacity: Int {
        switch self {
        case .unbounded:
            return Int.max
        case .dropOldest(let cap), .dropNewest(let cap):
            return cap
        }
    }

    /// Default bounded policy with 1000 event capacity, dropping oldest on overflow
    public static let bounded = StreamBufferPolicy.dropOldest(capacity: 1000)

    /// Create a bounded policy with validation
    /// - Parameters:
    ///   - capacity: Must be > 0
    ///   - dropOldest: If true, drops oldest events; if false, drops newest
    /// - Returns: A bounded policy, or nil if capacity is invalid
    public static func bounded(capacity: Int, dropOldest: Bool = true) -> StreamBufferPolicy? {
        guard capacity > 0 else { return nil }
        return dropOldest ? .dropOldest(capacity: capacity) : .dropNewest(capacity: capacity)
    }
}

// MARK: - AITextRequest Extensions

public extension AITextRequest {
    /// Check if the request can use a specific provider based on allowedProviders.
    /// Returns true if allowedProviders is nil (no restrictions) or if the provider is in the set.
    ///
    /// Note: This only checks the provider allowlist. Sensitivity validation
    /// (requiring explicit allowlisting for sensitive/PHI data) is handled separately
    /// by the adapter/router layer.
    func canUseProvider(_ provider: String) -> Bool {
        // If allowedProviders is nil, allow all providers
        guard let allowed = allowedProviders else {
            return true
        }
        return allowed.contains(provider)
    }

    /// Create a copy with updated sensitivity
    func withSensitivity(_ newSensitivity: DataSensitivity) -> AITextRequest {
        AITextRequest(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stop: stop,
            tools: tools,
            toolChoice: toolChoice,
            builtInTools: builtInTools,
            responseFormat: responseFormat,
            reasoning: reasoning,
            caching: caching,
            allowedProviders: allowedProviders,
            sensitivity: newSensitivity,
            bufferPolicy: bufferPolicy,
            metadata: metadata,
            conversationId: conversationId,
            providerOptions: providerOptions
        )
    }

    /// Create a copy with restricted providers for PHI protection
    func withAllowedProviders(_ providers: Set<String>) -> AITextRequest {
        AITextRequest(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stop: stop,
            tools: tools,
            toolChoice: toolChoice,
            builtInTools: builtInTools,
            responseFormat: responseFormat,
            reasoning: reasoning,
            caching: caching,
            allowedProviders: providers,
            sensitivity: sensitivity,
            bufferPolicy: bufferPolicy,
            metadata: metadata,
            conversationId: conversationId,
            providerOptions: providerOptions
        )
    }

    /// Create a copy with a custom buffer policy
    func withBufferPolicy(_ policy: StreamBufferPolicy) -> AITextRequest {
        AITextRequest(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stop: stop,
            tools: tools,
            toolChoice: toolChoice,
            builtInTools: builtInTools,
            responseFormat: responseFormat,
            reasoning: reasoning,
            caching: caching,
            allowedProviders: allowedProviders,
            sensitivity: sensitivity,
            bufferPolicy: policy,
            metadata: metadata,
            conversationId: conversationId,
            providerOptions: providerOptions
        )
    }

    /// Create a copy with a conversation ID for multi-turn conversations
    func withConversationId(_ id: String?) -> AITextRequest {
        AITextRequest(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stop: stop,
            tools: tools,
            toolChoice: toolChoice,
            builtInTools: builtInTools,
            responseFormat: responseFormat,
            reasoning: reasoning,
            caching: caching,
            allowedProviders: allowedProviders,
            sensitivity: sensitivity,
            bufferPolicy: bufferPolicy,
            metadata: metadata,
            conversationId: id,
            providerOptions: providerOptions
        )
    }

    /// Create a copy with updated built-in tools
    func withBuiltInTools(_ builtInTools: [BuiltInTool]?) -> AITextRequest {
        AITextRequest(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stop: stop,
            tools: tools,
            toolChoice: toolChoice,
            builtInTools: builtInTools,
            responseFormat: responseFormat,
            reasoning: reasoning,
            allowedProviders: allowedProviders,
            sensitivity: sensitivity,
            bufferPolicy: bufferPolicy,
            metadata: metadata,
            conversationId: conversationId,
            providerOptions: providerOptions
        )
    }

    /// Create a copy with updated reasoning configuration
    func withReasoning(_ reasoning: AIReasoningConfig?) -> AITextRequest {
        AITextRequest(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stop: stop,
            tools: tools,
            toolChoice: toolChoice,
            builtInTools: builtInTools,
            responseFormat: responseFormat,
            reasoning: reasoning,
            caching: caching,
            allowedProviders: allowedProviders,
            sensitivity: sensitivity,
            bufferPolicy: bufferPolicy,
            metadata: metadata,
            conversationId: conversationId,
            providerOptions: providerOptions
        )
    }

    /// Create a copy with updated caching configuration
    func withCaching(_ caching: AICacheConfig?) -> AITextRequest {
        AITextRequest(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stop: stop,
            tools: tools,
            toolChoice: toolChoice,
            responseFormat: responseFormat,
            reasoning: reasoning,
            caching: caching,
            allowedProviders: allowedProviders,
            sensitivity: sensitivity,
            bufferPolicy: bufferPolicy,
            metadata: metadata,
            conversationId: conversationId,
            providerOptions: providerOptions
        )
    }

    /// Create a copy with provider-specific options
    func withProviderOptions(_ options: (any Sendable)?) -> AITextRequest {
        AITextRequest(
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stop: stop,
            tools: tools,
            toolChoice: toolChoice,
            builtInTools: builtInTools,
            responseFormat: responseFormat,
            reasoning: reasoning,
            caching: caching,
            allowedProviders: allowedProviders,
            sensitivity: sensitivity,
            bufferPolicy: bufferPolicy,
            metadata: metadata,
            conversationId: conversationId,
            providerOptions: options
        )
    }
}
