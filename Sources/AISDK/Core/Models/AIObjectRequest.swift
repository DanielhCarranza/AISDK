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
/// which doesn't have `Sendable` conformance. The schema is expected to be
/// an immutable value type (like `SchemaBuilder`) used only within a single
/// request context. Custom implementations of `SchemaBuilding` must ensure
/// thread-safety if sharing state across concurrent requests.
public struct AIObjectRequest<T: Codable & Sendable>: @unchecked Sendable {
    /// The messages to send to the model
    public let messages: [AIMessage]

    /// The schema for the expected output
    public let schema: any SchemaBuilding

    /// Custom schema name for API compliance.
    /// If nil, defaults to a sanitized version of the type name.
    /// OpenAI requires names matching `[A-Za-z0-9_-]+` with max 64 chars.
    public let schemaName: String?

    /// Whether to enable strict mode for JSON schema validation.
    /// When true (default), the provider enforces exact schema compliance.
    public let strict: Bool

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
        schema: any SchemaBuilding,
        schemaName: String? = nil,
        strict: Bool = true,
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
        self.schemaName = schemaName
        self.strict = strict
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.allowedProviders = allowedProviders
        self.sensitivity = sensitivity
        self.bufferPolicy = bufferPolicy
        self.metadata = metadata
    }

    /// Compute a sanitized schema name for API compliance.
    /// OpenAI requires names matching `[A-Za-z0-9_-]+` with max 64 chars.
    public var effectiveSchemaName: String {
        if let name = schemaName {
            return sanitizeSchemaName(name)
        }
        // Use type name, removing module prefix and generic syntax
        let typeName = String(describing: T.self)
        return sanitizeSchemaName(typeName)
    }

    /// Sanitize a name to match OpenAI's schema name requirements
    private func sanitizeSchemaName(_ name: String) -> String {
        // Remove module prefix (everything before last dot)
        var sanitized = name.components(separatedBy: ".").last ?? name
        // Replace invalid characters with underscores
        sanitized = sanitized.replacingOccurrences(of: "<", with: "_")
        sanitized = sanitized.replacingOccurrences(of: ">", with: "_")
        sanitized = sanitized.replacingOccurrences(of: " ", with: "_")
        // Keep only valid chars: A-Za-z0-9_-
        sanitized = sanitized.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        // Truncate to 64 chars
        if sanitized.count > 64 {
            sanitized = String(sanitized.prefix(64))
        }
        // Ensure not empty
        if sanitized.isEmpty {
            sanitized = "Object"
        }
        return sanitized
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
            schemaName: schemaName,
            strict: strict,
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
            schemaName: schemaName,
            strict: strict,
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
            schemaName: schemaName,
            strict: strict,
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
