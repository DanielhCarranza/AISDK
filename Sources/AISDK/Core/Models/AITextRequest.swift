//
//  AITextRequest.swift
//  AISDK
//
//  Request model for text generation operations
//  Based on Vercel AI SDK 6.x patterns
//

import Foundation

/// Request for text generation
public struct AITextRequest: Sendable {
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

    /// Response format specification
    public let responseFormat: ResponseFormat?

    /// Allowed providers for PHI protection (nil allows all)
    public let allowedProviders: Set<String>?

    /// Data sensitivity classification
    public let sensitivity: DataSensitivity

    /// Stream buffer policy for memory control
    public let bufferPolicy: StreamBufferPolicy?

    /// Request metadata for tracing
    public let metadata: [String: String]?

    public init(
        messages: [AIMessage],
        model: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stop: [String]? = nil,
        tools: [ToolSchema]? = nil,
        toolChoice: ToolChoice? = nil,
        responseFormat: ResponseFormat? = nil,
        allowedProviders: Set<String>? = nil,
        sensitivity: DataSensitivity = .standard,
        bufferPolicy: StreamBufferPolicy? = nil,
        metadata: [String: String]? = nil
    ) {
        self.messages = messages
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stop = stop
        self.tools = tools
        self.toolChoice = toolChoice
        self.responseFormat = responseFormat
        self.allowedProviders = allowedProviders
        self.sensitivity = sensitivity
        self.bufferPolicy = bufferPolicy
        self.metadata = metadata
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

/// Stream buffer policy for memory control
public struct StreamBufferPolicy: Sendable, Equatable {
    /// Maximum number of events to buffer
    public let capacity: Int

    /// Action when buffer is full
    public let overflowBehavior: OverflowBehavior

    public enum OverflowBehavior: Sendable, Equatable {
        /// Drop oldest events when full
        case dropOldest
        /// Drop newest events when full
        case dropNewest
        /// Block until space available
        case suspendProducer
    }

    public init(capacity: Int, overflowBehavior: OverflowBehavior = .suspendProducer) {
        self.capacity = capacity
        self.overflowBehavior = overflowBehavior
    }

    /// Default bounded policy with 1000 event capacity
    public static let bounded = StreamBufferPolicy(capacity: 1000)

    /// Unbounded policy (use with caution)
    public static let unbounded = StreamBufferPolicy(capacity: Int.max)
}

// MARK: - AITextRequest Extensions

public extension AITextRequest {
    /// Check if the request can use a specific provider based on sensitivity settings
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
            responseFormat: responseFormat,
            allowedProviders: allowedProviders,
            sensitivity: newSensitivity,
            bufferPolicy: bufferPolicy,
            metadata: metadata
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
            responseFormat: responseFormat,
            allowedProviders: providers,
            sensitivity: sensitivity,
            bufferPolicy: bufferPolicy,
            metadata: metadata
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
            responseFormat: responseFormat,
            allowedProviders: allowedProviders,
            sensitivity: sensitivity,
            bufferPolicy: policy,
            metadata: metadata
        )
    }
}
