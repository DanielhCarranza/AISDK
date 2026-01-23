//
//  AIObjectRequest.swift
//  AISDK
//
//  Request model for structured object generation operations
//  Based on Vercel AI SDK 6.x patterns
//

import Foundation

/// Request for structured object generation
///
/// Note: Marked as `@unchecked Sendable` because it contains `SchemaBuilding`
/// which doesn't have `Sendable` conformance. The schema is an immutable value
/// used only within a single request context.
public struct AIObjectRequest<T: Codable & Sendable>: @unchecked Sendable {
    /// The messages to send to the model
    public let messages: [AIMessage]

    /// The schema for the expected output
    public let schema: SchemaBuilding

    /// The model to use (optional, uses default if nil)
    public let model: String?

    /// Maximum tokens to generate
    public let maxTokens: Int?

    /// Temperature for generation (0-2)
    public let temperature: Double?

    /// Top-p sampling parameter
    public let topP: Double?

    /// Allowed providers for PHI protection (nil allows all)
    public let allowedProviders: Set<String>?

    /// Data sensitivity classification
    public let sensitivity: DataSensitivity

    /// Stream buffer policy for memory control.
    /// Note: Currently metadata-only. Will be plumbed through streaming in Phase 3 (Reliability Layer).
    public let bufferPolicy: StreamBufferPolicy?

    /// Request metadata for tracing
    public let metadata: [String: String]?

    public init(
        messages: [AIMessage],
        schema: SchemaBuilding,
        model: String? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        allowedProviders: Set<String>? = nil,
        sensitivity: DataSensitivity = .standard,
        bufferPolicy: StreamBufferPolicy? = nil,
        metadata: [String: String]? = nil
    ) {
        self.messages = messages
        self.schema = schema
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.allowedProviders = allowedProviders
        self.sensitivity = sensitivity
        self.bufferPolicy = bufferPolicy
        self.metadata = metadata
    }
}

// MARK: - AIObjectRequest Extensions

public extension AIObjectRequest {
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
    func withSensitivity(_ newSensitivity: DataSensitivity) -> AIObjectRequest<T> {
        AIObjectRequest(
            messages: messages,
            schema: schema,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            allowedProviders: allowedProviders,
            sensitivity: newSensitivity,
            bufferPolicy: bufferPolicy,
            metadata: metadata
        )
    }

    /// Create a copy with restricted providers for PHI protection
    func withAllowedProviders(_ providers: Set<String>) -> AIObjectRequest<T> {
        AIObjectRequest(
            messages: messages,
            schema: schema,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            allowedProviders: providers,
            sensitivity: sensitivity,
            bufferPolicy: bufferPolicy,
            metadata: metadata
        )
    }

    /// Create a copy with a custom buffer policy
    func withBufferPolicy(_ policy: StreamBufferPolicy) -> AIObjectRequest<T> {
        AIObjectRequest(
            messages: messages,
            schema: schema,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            allowedProviders: allowedProviders,
            sensitivity: sensitivity,
            bufferPolicy: policy,
            metadata: metadata
        )
    }
}
