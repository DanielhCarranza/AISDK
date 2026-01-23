//
//  AISDKConfiguration.swift
//  AISDK
//
//  Centralized SDK configuration with startup validation
//  Based on Vercel AI SDK 6.x configuration patterns
//

import Foundation

// MARK: - Configuration Errors

/// Errors that can occur during configuration validation
public enum AISDKConfigurationError: Error, LocalizedError, Sendable {
    /// API key is missing for a required provider
    case missingAPIKey(provider: String)
    /// API key format is invalid
    case invalidAPIKey(provider: String, reason: String)
    /// Default model is not available
    case invalidDefaultModel(model: String)
    /// Provider configuration is invalid
    case invalidProviderConfiguration(provider: String, reason: String)
    /// Stream buffer capacity is invalid
    case invalidBufferCapacity(capacity: Int)
    /// Timeout value is invalid
    case invalidTimeout(value: TimeInterval, reason: String)
    /// Multiple validation errors occurred
    case multipleErrors([AISDKConfigurationError])

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Missing API key for provider: \(provider)"
        case .invalidAPIKey(let provider, let reason):
            return "Invalid API key for \(provider): \(reason)"
        case .invalidDefaultModel(let model):
            return "Invalid default model: \(model)"
        case .invalidProviderConfiguration(let provider, let reason):
            return "Invalid configuration for \(provider): \(reason)"
        case .invalidBufferCapacity(let capacity):
            return "Invalid buffer capacity: \(capacity). Must be > 0."
        case .invalidTimeout(let value, let reason):
            return "Invalid timeout \(value)s: \(reason)"
        case .multipleErrors(let errors):
            let descriptions = errors.compactMap { $0.errorDescription }
            return "Multiple configuration errors:\n" + descriptions.joined(separator: "\n")
        }
    }
}

// MARK: - Provider Configuration

/// Configuration for a specific AI provider
public struct AIProviderConfiguration: Sendable, Equatable {
    /// The provider identifier (e.g., "openai", "anthropic", "google")
    public let provider: String

    /// API key for this provider (nil if using environment variable)
    public let apiKey: String?

    /// Environment variable name for API key (default: derived from provider)
    public let apiKeyEnvVar: String

    /// Base URL override (nil uses provider default)
    public let baseURL: URL?

    /// Organization ID (provider-specific)
    public let organizationId: String?

    /// Project ID (provider-specific)
    public let projectId: String?

    /// Default model for this provider
    public let defaultModel: String?

    /// Maximum requests per minute (rate limiting)
    public let maxRequestsPerMinute: Int?

    /// Maximum tokens per minute (rate limiting)
    public let maxTokensPerMinute: Int?

    /// Custom headers to include in all requests
    public let customHeaders: [String: String]

    /// Whether this provider is enabled
    public let isEnabled: Bool

    /// Whether this provider is trusted for PHI data
    public let trustedForPHI: Bool

    public init(
        provider: String,
        apiKey: String? = nil,
        apiKeyEnvVar: String? = nil,
        baseURL: URL? = nil,
        organizationId: String? = nil,
        projectId: String? = nil,
        defaultModel: String? = nil,
        maxRequestsPerMinute: Int? = nil,
        maxTokensPerMinute: Int? = nil,
        customHeaders: [String: String] = [:],
        isEnabled: Bool = true,
        trustedForPHI: Bool = false
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.apiKeyEnvVar = apiKeyEnvVar ?? Self.defaultEnvVar(for: provider)
        self.baseURL = baseURL
        self.organizationId = organizationId
        self.projectId = projectId
        self.defaultModel = defaultModel
        self.maxRequestsPerMinute = maxRequestsPerMinute
        self.maxTokensPerMinute = maxTokensPerMinute
        self.customHeaders = customHeaders
        self.isEnabled = isEnabled
        self.trustedForPHI = trustedForPHI
    }

    /// Default environment variable name for a provider
    private static func defaultEnvVar(for provider: String) -> String {
        "\(provider.uppercased())_API_KEY"
    }

    /// Resolve the API key from explicit value or environment
    public func resolveAPIKey() -> String? {
        if let apiKey = apiKey, !apiKey.isEmpty {
            return apiKey
        }
        return ProcessInfo.processInfo.environment[apiKeyEnvVar]
    }
}

// MARK: - Reliability Configuration

/// Configuration for reliability features (circuit breaker, retries, failover)
public struct AIReliabilityConfiguration: Sendable, Equatable {
    /// Default request timeout in seconds
    public let defaultTimeout: TimeInterval

    /// Maximum number of retry attempts
    public let maxRetries: Int

    /// Base delay for exponential backoff (seconds)
    public let retryBaseDelay: TimeInterval

    /// Maximum delay between retries (seconds)
    public let retryMaxDelay: TimeInterval

    /// Whether to enable circuit breaker
    public let circuitBreakerEnabled: Bool

    /// Failure threshold to open circuit
    public let circuitBreakerThreshold: Int

    /// Time to wait before attempting to close circuit (seconds)
    public let circuitBreakerResetTimeout: TimeInterval

    /// Whether to enable automatic failover
    public let failoverEnabled: Bool

    /// Maximum cost multiplier for failover (e.g., 2.0 = allow 2x cost)
    public let failoverMaxCostMultiplier: Double

    public init(
        defaultTimeout: TimeInterval = 60.0,
        maxRetries: Int = 3,
        retryBaseDelay: TimeInterval = 1.0,
        retryMaxDelay: TimeInterval = 30.0,
        circuitBreakerEnabled: Bool = true,
        circuitBreakerThreshold: Int = 5,
        circuitBreakerResetTimeout: TimeInterval = 30.0,
        failoverEnabled: Bool = true,
        failoverMaxCostMultiplier: Double = 2.0
    ) {
        self.defaultTimeout = defaultTimeout
        self.maxRetries = maxRetries
        self.retryBaseDelay = retryBaseDelay
        self.retryMaxDelay = retryMaxDelay
        self.circuitBreakerEnabled = circuitBreakerEnabled
        self.circuitBreakerThreshold = circuitBreakerThreshold
        self.circuitBreakerResetTimeout = circuitBreakerResetTimeout
        self.failoverEnabled = failoverEnabled
        self.failoverMaxCostMultiplier = failoverMaxCostMultiplier
    }

    /// Default reliability configuration
    public static let `default` = AIReliabilityConfiguration()
}

// MARK: - Telemetry Configuration

/// Configuration for telemetry and observability
public struct AITelemetryConfiguration: Sendable, Equatable {
    /// Whether telemetry is enabled
    public let isEnabled: Bool

    /// Whether to include request/response content in telemetry (PHI risk!)
    public let includeContent: Bool

    /// Whether to log request metadata
    public let logRequests: Bool

    /// Whether to log response metadata
    public let logResponses: Bool

    /// Whether to log errors
    public let logErrors: Bool

    /// Whether to emit timing metrics
    public let emitMetrics: Bool

    /// Sampling rate for traces (0.0 to 1.0)
    public let samplingRate: Double

    public init(
        isEnabled: Bool = true,
        includeContent: Bool = false,
        logRequests: Bool = true,
        logResponses: Bool = true,
        logErrors: Bool = true,
        emitMetrics: Bool = true,
        samplingRate: Double = 1.0
    ) {
        self.isEnabled = isEnabled
        self.includeContent = includeContent
        self.logRequests = logRequests
        self.logResponses = logResponses
        self.logErrors = logErrors
        self.emitMetrics = emitMetrics
        self.samplingRate = min(1.0, max(0.0, samplingRate))
    }

    /// Default telemetry configuration (PHI-safe)
    public static let `default` = AITelemetryConfiguration()

    /// Minimal telemetry for production (errors only)
    public static let minimal = AITelemetryConfiguration(
        isEnabled: true,
        includeContent: false,
        logRequests: false,
        logResponses: false,
        logErrors: true,
        emitMetrics: false,
        samplingRate: 0.1
    )

    /// Disabled telemetry
    public static let disabled = AITelemetryConfiguration(isEnabled: false)
}

// MARK: - AISDKConfiguration

/// Central configuration for the AISDK
///
/// AISDKConfiguration provides a centralized, validated configuration for the SDK.
/// It supports fail-fast validation to catch configuration errors at startup
/// rather than at runtime.
///
/// Example:
/// ```swift
/// // Create configuration with validation
/// let config = try AISDKConfiguration(
///     defaultModel: "gpt-4o",
///     providers: [
///         AIProviderConfiguration(provider: "openai", apiKey: "sk-..."),
///         AIProviderConfiguration(provider: "anthropic")  // Uses env var
///     ],
///     validateOnInit: true  // Fail-fast validation
/// )
///
/// // Or use builder pattern
/// let config = try AISDKConfiguration.Builder()
///     .defaultModel("gpt-4o")
///     .addProvider(.openai(apiKey: "sk-..."))
///     .reliability(.default)
///     .build()
/// ```
public struct AISDKConfiguration: Sendable {
    // MARK: - Properties

    /// Default model to use when not specified in requests
    public let defaultModel: String?

    /// Provider configurations indexed by provider name
    public let providers: [String: AIProviderConfiguration]

    /// Default stream buffer policy
    public let defaultBufferPolicy: StreamBufferPolicy

    /// Default data sensitivity level
    public let defaultSensitivity: DataSensitivity

    /// Reliability configuration
    public let reliability: AIReliabilityConfiguration

    /// Telemetry configuration
    public let telemetry: AITelemetryConfiguration

    /// Whether to enforce PHI protection (require explicit allowlist for sensitive data)
    public let enforcePHIProtection: Bool

    /// Maximum concurrent requests (0 = unlimited)
    public let maxConcurrentRequests: Int

    /// Global custom headers to include in all provider requests
    public let globalHeaders: [String: String]

    // MARK: - Initialization

    /// Create a new SDK configuration
    ///
    /// - Parameters:
    ///   - defaultModel: Default model to use when not specified
    ///   - providers: Array of provider configurations
    ///   - defaultBufferPolicy: Default stream buffer policy
    ///   - defaultSensitivity: Default data sensitivity level
    ///   - reliability: Reliability configuration
    ///   - telemetry: Telemetry configuration
    ///   - enforcePHIProtection: Whether to enforce PHI protection
    ///   - maxConcurrentRequests: Maximum concurrent requests (0 = unlimited)
    ///   - globalHeaders: Global custom headers
    ///   - validateOnInit: Whether to validate configuration on initialization
    /// - Throws: AISDKConfigurationError if validation fails
    public init(
        defaultModel: String? = nil,
        providers: [AIProviderConfiguration] = [],
        defaultBufferPolicy: StreamBufferPolicy = .bounded,
        defaultSensitivity: DataSensitivity = .standard,
        reliability: AIReliabilityConfiguration = .default,
        telemetry: AITelemetryConfiguration = .default,
        enforcePHIProtection: Bool = true,
        maxConcurrentRequests: Int = 0,
        globalHeaders: [String: String] = [:],
        validateOnInit: Bool = true
    ) throws {
        self.defaultModel = defaultModel
        self.providers = Dictionary(
            uniqueKeysWithValues: providers.map { ($0.provider, $0) }
        )
        self.defaultBufferPolicy = defaultBufferPolicy
        self.defaultSensitivity = defaultSensitivity
        self.reliability = reliability
        self.telemetry = telemetry
        self.enforcePHIProtection = enforcePHIProtection
        self.maxConcurrentRequests = maxConcurrentRequests
        self.globalHeaders = globalHeaders

        if validateOnInit {
            try validate()
        }
    }

    // MARK: - Validation

    /// Validate the configuration
    ///
    /// This method performs comprehensive validation of the configuration
    /// and throws an error if any issues are found.
    ///
    /// - Throws: AISDKConfigurationError describing validation failures
    public func validate() throws {
        var errors: [AISDKConfigurationError] = []

        // Validate buffer policy
        if case .dropOldest(let capacity) = defaultBufferPolicy, capacity <= 0 {
            errors.append(.invalidBufferCapacity(capacity: capacity))
        }
        if case .dropNewest(let capacity) = defaultBufferPolicy, capacity <= 0 {
            errors.append(.invalidBufferCapacity(capacity: capacity))
        }

        // Validate reliability settings
        if reliability.defaultTimeout <= 0 {
            errors.append(.invalidTimeout(
                value: reliability.defaultTimeout,
                reason: "must be positive"
            ))
        }
        if reliability.retryBaseDelay <= 0 {
            errors.append(.invalidTimeout(
                value: reliability.retryBaseDelay,
                reason: "retry base delay must be positive"
            ))
        }

        // Validate each provider configuration
        for (_, providerConfig) in providers {
            if let error = validateProvider(providerConfig) {
                errors.append(error)
            }
        }

        // Throw errors if any
        if errors.count == 1 {
            throw errors[0]
        } else if errors.count > 1 {
            throw AISDKConfigurationError.multipleErrors(errors)
        }
    }

    /// Validate a single provider configuration
    private func validateProvider(_ config: AIProviderConfiguration) -> AISDKConfigurationError? {
        // Check API key format based on provider
        if let apiKey = config.resolveAPIKey() {
            switch config.provider.lowercased() {
            case "openai":
                if !apiKey.hasPrefix("sk-") {
                    return .invalidAPIKey(
                        provider: config.provider,
                        reason: "OpenAI API keys should start with 'sk-'"
                    )
                }
            case "anthropic":
                if !apiKey.hasPrefix("sk-ant-") {
                    return .invalidAPIKey(
                        provider: config.provider,
                        reason: "Anthropic API keys should start with 'sk-ant-'"
                    )
                }
            default:
                // No specific format validation for other providers
                break
            }
        }

        return nil
    }

    // MARK: - Provider Access

    /// Get configuration for a specific provider
    public func provider(_ name: String) -> AIProviderConfiguration? {
        providers[name.lowercased()] ?? providers[name]
    }

    /// Get all enabled providers
    public var enabledProviders: [AIProviderConfiguration] {
        providers.values.filter { $0.isEnabled }
    }

    /// Get providers trusted for PHI data
    public var phiTrustedProviders: [AIProviderConfiguration] {
        providers.values.filter { $0.trustedForPHI }
    }

    /// Check if a provider is configured
    public func hasProvider(_ name: String) -> Bool {
        provider(name) != nil
    }

    // MARK: - Shared Instance

    /// The shared SDK configuration
    ///
    /// This must be set before using the SDK. Use `configure(_:)` to set.
    public private(set) static var shared: AISDKConfiguration?

    /// Configure the shared SDK instance
    ///
    /// - Parameter configuration: The configuration to use
    /// - Throws: AISDKConfigurationError if validation fails
    public static func configure(_ configuration: AISDKConfiguration) throws {
        try configuration.validate()
        shared = configuration
    }

    /// Configure the shared SDK instance with a builder
    ///
    /// - Parameter builder: A closure that configures the builder
    /// - Throws: AISDKConfigurationError if validation fails
    public static func configure(_ builder: (inout Builder) -> Void) throws {
        var b = Builder()
        builder(&b)
        let config = try b.build()
        shared = config
    }

    /// Reset the shared configuration (primarily for testing)
    public static func reset() {
        shared = nil
    }
}

// MARK: - Builder

extension AISDKConfiguration {
    /// Builder for AISDKConfiguration
    ///
    /// Provides a fluent API for constructing configuration.
    public struct Builder {
        private var defaultModel: String?
        private var providers: [AIProviderConfiguration] = []
        private var defaultBufferPolicy: StreamBufferPolicy = .bounded
        private var defaultSensitivity: DataSensitivity = .standard
        private var reliability: AIReliabilityConfiguration = .default
        private var telemetry: AITelemetryConfiguration = .default
        private var enforcePHIProtection: Bool = true
        private var maxConcurrentRequests: Int = 0
        private var globalHeaders: [String: String] = [:]

        public init() {}

        /// Set the default model
        @discardableResult
        public mutating func defaultModel(_ model: String) -> Builder {
            self.defaultModel = model
            return self
        }

        /// Add a provider configuration
        @discardableResult
        public mutating func addProvider(_ provider: AIProviderConfiguration) -> Builder {
            self.providers.append(provider)
            return self
        }

        /// Set the default buffer policy
        @discardableResult
        public mutating func defaultBufferPolicy(_ policy: StreamBufferPolicy) -> Builder {
            self.defaultBufferPolicy = policy
            return self
        }

        /// Set the default sensitivity level
        @discardableResult
        public mutating func defaultSensitivity(_ sensitivity: DataSensitivity) -> Builder {
            self.defaultSensitivity = sensitivity
            return self
        }

        /// Set the reliability configuration
        @discardableResult
        public mutating func reliability(_ config: AIReliabilityConfiguration) -> Builder {
            self.reliability = config
            return self
        }

        /// Set the telemetry configuration
        @discardableResult
        public mutating func telemetry(_ config: AITelemetryConfiguration) -> Builder {
            self.telemetry = config
            return self
        }

        /// Set whether to enforce PHI protection
        @discardableResult
        public mutating func enforcePHIProtection(_ enforce: Bool) -> Builder {
            self.enforcePHIProtection = enforce
            return self
        }

        /// Set the maximum concurrent requests
        @discardableResult
        public mutating func maxConcurrentRequests(_ max: Int) -> Builder {
            self.maxConcurrentRequests = max
            return self
        }

        /// Add a global header
        @discardableResult
        public mutating func addGlobalHeader(name: String, value: String) -> Builder {
            self.globalHeaders[name] = value
            return self
        }

        /// Build the configuration
        ///
        /// - Returns: The built configuration
        /// - Throws: AISDKConfigurationError if validation fails
        public func build() throws -> AISDKConfiguration {
            try AISDKConfiguration(
                defaultModel: defaultModel,
                providers: providers,
                defaultBufferPolicy: defaultBufferPolicy,
                defaultSensitivity: defaultSensitivity,
                reliability: reliability,
                telemetry: telemetry,
                enforcePHIProtection: enforcePHIProtection,
                maxConcurrentRequests: maxConcurrentRequests,
                globalHeaders: globalHeaders,
                validateOnInit: true
            )
        }
    }
}

// MARK: - Provider Configuration Presets

extension AIProviderConfiguration {
    /// Create an OpenAI provider configuration
    public static func openai(
        apiKey: String? = nil,
        organizationId: String? = nil,
        projectId: String? = nil,
        defaultModel: String = "gpt-4o",
        trustedForPHI: Bool = false
    ) -> AIProviderConfiguration {
        AIProviderConfiguration(
            provider: "openai",
            apiKey: apiKey,
            apiKeyEnvVar: "OPENAI_API_KEY",
            organizationId: organizationId,
            projectId: projectId,
            defaultModel: defaultModel,
            trustedForPHI: trustedForPHI
        )
    }

    /// Create an Anthropic provider configuration
    public static func anthropic(
        apiKey: String? = nil,
        defaultModel: String = "claude-3-5-sonnet-20241022",
        trustedForPHI: Bool = false
    ) -> AIProviderConfiguration {
        AIProviderConfiguration(
            provider: "anthropic",
            apiKey: apiKey,
            apiKeyEnvVar: "ANTHROPIC_API_KEY",
            defaultModel: defaultModel,
            trustedForPHI: trustedForPHI
        )
    }

    /// Create a Google (Gemini) provider configuration
    public static func google(
        apiKey: String? = nil,
        defaultModel: String = "gemini-1.5-pro",
        trustedForPHI: Bool = false
    ) -> AIProviderConfiguration {
        AIProviderConfiguration(
            provider: "google",
            apiKey: apiKey,
            apiKeyEnvVar: "GOOGLE_API_KEY",
            defaultModel: defaultModel,
            trustedForPHI: trustedForPHI
        )
    }

    /// Create an OpenRouter provider configuration
    public static func openRouter(
        apiKey: String? = nil,
        defaultModel: String = "openai/gpt-4o",
        trustedForPHI: Bool = false
    ) -> AIProviderConfiguration {
        AIProviderConfiguration(
            provider: "openrouter",
            apiKey: apiKey,
            apiKeyEnvVar: "OPENROUTER_API_KEY",
            baseURL: URL(string: "https://openrouter.ai/api/v1"),
            defaultModel: defaultModel,
            trustedForPHI: trustedForPHI
        )
    }
}

// MARK: - Equatable

extension AISDKConfiguration: Equatable {
    public static func == (lhs: AISDKConfiguration, rhs: AISDKConfiguration) -> Bool {
        lhs.defaultModel == rhs.defaultModel &&
        lhs.providers == rhs.providers &&
        lhs.defaultBufferPolicy == rhs.defaultBufferPolicy &&
        lhs.defaultSensitivity == rhs.defaultSensitivity &&
        lhs.reliability == rhs.reliability &&
        lhs.telemetry == rhs.telemetry &&
        lhs.enforcePHIProtection == rhs.enforcePHIProtection &&
        lhs.maxConcurrentRequests == rhs.maxConcurrentRequests &&
        lhs.globalHeaders == rhs.globalHeaders
    }
}
