//
//  AICacheConfig.swift
//  AISDK
//
//  Unified prompt/context caching configuration for AITextRequest
//

import Foundation

/// Provider-agnostic caching configuration.
///
/// Controls how providers handle prompt and context caching:
/// - **OpenAI**: No-op (caching is fully automatic on prefix matches >= 1024 tokens)
/// - **Anthropic**: Adds `cache_control` blocks to system prompt and tool definitions
/// - **Gemini**: No-op for implicit caching; explicit caching uses `cachedContentId`
public struct AICacheConfig: Sendable, Equatable, Codable {
    /// Enable automatic caching of system instructions and tools.
    /// - OpenAI: No-op (caching is automatic for all requests)
    /// - Anthropic: Adds cache_control to system prompt and last tool definition
    /// - Gemini: No-op (implicit caching is automatic)
    public let enabled: Bool

    /// Reference to a pre-created cache resource (Gemini explicit caching).
    /// Format: "cachedContents/{id}" or full resource name.
    public let cachedContentId: String?

    /// Cache retention preference.
    public let retention: CacheRetention?

    /// Cache retention level.
    public enum CacheRetention: String, Sendable, Codable, Equatable {
        /// Default provider cache lifetime (OpenAI ~5-10min, Anthropic 5min, Gemini 1hr)
        case standard
        /// Extended cache lifetime (OpenAI: not applicable, Anthropic 1hr, Gemini: custom TTL)
        case extended
    }

    public init(
        enabled: Bool = true,
        cachedContentId: String? = nil,
        retention: CacheRetention? = nil
    ) {
        self.enabled = enabled
        self.cachedContentId = cachedContentId
        self.retention = retention
    }
}

public extension AICacheConfig {
    /// Simple enable with default retention.
    static var enabled: AICacheConfig {
        AICacheConfig()
    }

    /// Enable with extended retention.
    static func extended() -> AICacheConfig {
        AICacheConfig(retention: .extended)
    }

    /// Reference a pre-created Gemini cached content resource.
    static func withCachedContent(_ id: String) -> AICacheConfig {
        AICacheConfig(cachedContentId: id)
    }
}
