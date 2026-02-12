//
//  CapabilityAwareFailover.swift
//  AISDK
//
//  Failover policy with capability and cost awareness.
//  Ensures failover targets are compatible with request requirements.
//

import Foundation

// MARK: - TokenEstimator

/// Estimates token counts for requests.
///
/// Uses a simple heuristic of ~4 characters per token, which is a common
/// approximation for English text with GPT-style tokenizers.
public struct TokenEstimator: Sendable, Equatable {
    /// Characters per token approximation
    public let charsPerToken: Int

    /// Default estimator using 4 chars per token
    public static let `default` = TokenEstimator(charsPerToken: 4)

    /// Conservative estimator using 3 chars per token (overestimates)
    public static let conservative = TokenEstimator(charsPerToken: 3)

    /// Creates a token estimator.
    ///
    /// - Parameter charsPerToken: Characters per token (default: 4)
    public init(charsPerToken: Int = 4) {
        self.charsPerToken = max(1, charsPerToken)
    }

    /// Estimate token count for a text request.
    ///
    /// - Parameter request: The text request to estimate
    /// - Returns: Estimated token count
    public func estimate(_ request: AITextRequest) -> Int {
        request.messages.reduce(0) { count, message in
            count + estimateMessage(message)
        }
    }

    /// Estimate token count for a single message.
    ///
    /// - Parameter message: The message to estimate
    /// - Returns: Estimated token count
    public func estimateMessage(_ message: AIMessage) -> Int {
        var tokenCount = 0

        // Count text content based on Content enum
        switch message.content {
        case .text(let text):
            tokenCount += (text.count + charsPerToken - 1) / charsPerToken

        case .parts(let parts):
            for part in parts {
                switch part {
                case .text(let text):
                    tokenCount += (text.count + charsPerToken - 1) / charsPerToken
                case .image, .imageURL:
                    // Images typically add ~85-1000 tokens depending on detail
                    tokenCount += 200  // Conservative middle estimate
                case .audio:
                    // Audio tokens vary significantly
                    tokenCount += 100
                case .file:
                    tokenCount += 100
                case .video, .videoURL:
                    // Video tokens vary significantly; use conservative estimate
                    tokenCount += 400
                }
            }
        }

        // Add overhead for message structure (role, etc.)
        tokenCount += 4  // ~4 tokens per message overhead

        // Add tokens for tool calls if present
        if let toolCalls = message.toolCalls {
            for call in toolCalls {
                // Tool name + arguments
                tokenCount += (call.name.count + call.arguments.count + charsPerToken - 1) / charsPerToken
            }
        }

        return tokenCount
    }

    /// Estimate token count for a string.
    ///
    /// - Parameter text: The text to estimate
    /// - Returns: Estimated token count
    public func estimate(_ text: String) -> Int {
        (text.count + charsPerToken - 1) / charsPerToken
    }
}

// MARK: - FailoverPolicy

/// Policy for controlling failover behavior.
///
/// Determines which providers are compatible for failover based on:
/// - Token limit constraints
/// - Cost constraints
/// - Capability requirements
public struct FailoverPolicy: Sendable, Equatable {
    // MARK: - Properties

    /// Maximum acceptable cost multiplier when failing over.
    /// For example, 5.0 means failover target can be up to 5x more expensive.
    public let maxCostMultiplier: Double

    /// Whether the failover target must have matching capabilities.
    public let requireCapabilityMatch: Bool

    /// Token estimator for checking context limits.
    public let tokenEstimator: TokenEstimator

    /// Minimum context window required (0 = no minimum).
    public let minimumContextWindow: Int

    /// Whether to allow failover to models with lower performance tiers.
    public let allowLowerTier: Bool

    /// Required capabilities that must be present in failover target.
    public let requiredCapabilities: LLMCapabilities

    // MARK: - Initialization

    /// Creates a failover policy.
    ///
    /// - Parameters:
    ///   - maxCostMultiplier: Max cost multiplier for failover (default: 5.0)
    ///   - requireCapabilityMatch: Whether capabilities must match (default: true)
    ///   - tokenEstimator: Token estimator to use (default: .default)
    ///   - minimumContextWindow: Minimum required context window (default: 0)
    ///   - allowLowerTier: Allow failover to lower performance tiers (default: true)
    ///   - requiredCapabilities: Required capabilities (default: empty)
    public init(
        maxCostMultiplier: Double = 5.0,
        requireCapabilityMatch: Bool = true,
        tokenEstimator: TokenEstimator = .default,
        minimumContextWindow: Int = 0,
        allowLowerTier: Bool = true,
        requiredCapabilities: LLMCapabilities = []
    ) {
        self.maxCostMultiplier = max(1.0, maxCostMultiplier)
        self.requireCapabilityMatch = requireCapabilityMatch
        self.tokenEstimator = tokenEstimator
        self.minimumContextWindow = max(0, minimumContextWindow)
        self.allowLowerTier = allowLowerTier
        self.requiredCapabilities = requiredCapabilities
    }

    // MARK: - Preset Policies

    /// Default failover policy with reasonable constraints.
    public static let `default` = FailoverPolicy()

    /// Strict failover policy requiring capability match and limiting cost.
    public static let strict = FailoverPolicy(
        maxCostMultiplier: 2.0,
        requireCapabilityMatch: true,
        allowLowerTier: false
    )

    /// Lenient failover policy allowing any compatible provider.
    public static let lenient = FailoverPolicy(
        maxCostMultiplier: 10.0,
        requireCapabilityMatch: false,
        allowLowerTier: true
    )

    /// Cost-conscious policy prioritizing budget over capabilities.
    public static let costConscious = FailoverPolicy(
        maxCostMultiplier: 1.5,
        requireCapabilityMatch: false,
        allowLowerTier: true
    )

    // MARK: - Compatibility Checking

    /// Check if a provider is compatible for failover.
    ///
    /// - Parameters:
    ///   - request: The request to check
    ///   - provider: The potential failover provider
    ///   - modelId: The model to use on the provider
    /// - Returns: True if the provider is compatible
    public func isCompatible(
        request: AITextRequest,
        provider: any ProviderClient,
        modelId: String
    ) async -> Bool {
        // Check provider allowlist (PHI protection)
        if let allowed = request.allowedProviders,
           !allowed.contains(provider.providerId) {
            return false
        }

        // Check capabilities if required
        if requireCapabilityMatch || !requiredCapabilities.isEmpty {
            guard let capabilities = await provider.capabilities(for: modelId) else {
                // If capabilities unknown, allow only if not strictly required
                return !requireCapabilityMatch
            }

            // Check required capabilities
            if !requiredCapabilities.isEmpty {
                guard capabilities.contains(requiredCapabilities) else {
                    return false
                }
            }
        }

        // Check estimated tokens against minimum context window
        if minimumContextWindow > 0 {
            let estimatedTokens = tokenEstimator.estimate(request)
            if estimatedTokens > minimumContextWindow {
                return false
            }
        }

        return true
    }

    /// Check if a provider is compatible with simplified interface.
    ///
    /// This is a convenience method that doesn't check capabilities
    /// (useful when capability info isn't available).
    ///
    /// - Parameters:
    ///   - request: The request to check
    ///   - providerId: The provider ID to check
    /// - Returns: True if the provider is allowed
    public func isProviderAllowed(
        request: AITextRequest,
        providerId: String
    ) -> Bool {
        // Check provider allowlist (PHI protection)
        if let allowed = request.allowedProviders,
           !allowed.contains(providerId) {
            return false
        }
        return true
    }

    // MARK: - Modifier Methods

    /// Creates a copy with modified max cost multiplier.
    public func withMaxCostMultiplier(_ multiplier: Double) -> FailoverPolicy {
        FailoverPolicy(
            maxCostMultiplier: multiplier,
            requireCapabilityMatch: requireCapabilityMatch,
            tokenEstimator: tokenEstimator,
            minimumContextWindow: minimumContextWindow,
            allowLowerTier: allowLowerTier,
            requiredCapabilities: requiredCapabilities
        )
    }

    /// Creates a copy with modified capability requirement.
    public func withRequireCapabilityMatch(_ required: Bool) -> FailoverPolicy {
        FailoverPolicy(
            maxCostMultiplier: maxCostMultiplier,
            requireCapabilityMatch: required,
            tokenEstimator: tokenEstimator,
            minimumContextWindow: minimumContextWindow,
            allowLowerTier: allowLowerTier,
            requiredCapabilities: requiredCapabilities
        )
    }

    /// Creates a copy with required capabilities.
    public func withRequiredCapabilities(_ capabilities: LLMCapabilities) -> FailoverPolicy {
        FailoverPolicy(
            maxCostMultiplier: maxCostMultiplier,
            requireCapabilityMatch: requireCapabilityMatch,
            tokenEstimator: tokenEstimator,
            minimumContextWindow: minimumContextWindow,
            allowLowerTier: allowLowerTier,
            requiredCapabilities: capabilities
        )
    }

    /// Creates a copy with minimum context window.
    public func withMinimumContextWindow(_ window: Int) -> FailoverPolicy {
        FailoverPolicy(
            maxCostMultiplier: maxCostMultiplier,
            requireCapabilityMatch: requireCapabilityMatch,
            tokenEstimator: tokenEstimator,
            minimumContextWindow: window,
            allowLowerTier: allowLowerTier,
            requiredCapabilities: requiredCapabilities
        )
    }
}

// MARK: - FailoverCompatibilityResult

/// Result of a compatibility check with detailed reasoning.
public struct FailoverCompatibilityResult: Sendable, Equatable {
    /// Whether the provider is compatible.
    public let isCompatible: Bool

    /// Reason for incompatibility (nil if compatible).
    public let reason: IncompatibilityReason?

    /// Creates a compatibility result.
    public init(isCompatible: Bool, reason: IncompatibilityReason? = nil) {
        self.isCompatible = isCompatible
        self.reason = reason
    }

    /// Provider is compatible.
    public static let compatible = FailoverCompatibilityResult(isCompatible: true)

    /// Provider is not in the allowlist.
    public static let notInAllowlist = FailoverCompatibilityResult(
        isCompatible: false,
        reason: .providerNotAllowed
    )

    /// Provider lacks required capabilities.
    public static func missingCapabilities(_ missing: LLMCapabilities) -> FailoverCompatibilityResult {
        FailoverCompatibilityResult(
            isCompatible: false,
            reason: .missingCapabilities(missing)
        )
    }

    /// Provider exceeds cost limit.
    public static func costTooHigh(multiplier: Double) -> FailoverCompatibilityResult {
        FailoverCompatibilityResult(
            isCompatible: false,
            reason: .costExceedsLimit(multiplier)
        )
    }

    /// Provider has insufficient context window.
    public static func contextTooSmall(required: Int, available: Int) -> FailoverCompatibilityResult {
        FailoverCompatibilityResult(
            isCompatible: false,
            reason: .insufficientContext(required: required, available: available)
        )
    }
}

// MARK: - IncompatibilityReason

/// Reason why a provider is incompatible for failover.
public enum IncompatibilityReason: Sendable, Equatable {
    /// Provider is not in the request's allowed providers list.
    case providerNotAllowed

    /// Provider is missing required capabilities.
    case missingCapabilities(LLMCapabilities)

    /// Provider exceeds cost limit.
    case costExceedsLimit(Double)

    /// Provider has insufficient context window.
    case insufficientContext(required: Int, available: Int)

    /// Provider tier is too low.
    case tierTooLow

    /// Unknown capabilities.
    case unknownCapabilities
}
