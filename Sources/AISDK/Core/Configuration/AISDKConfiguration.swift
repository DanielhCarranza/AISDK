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
    /// Duplicate provider names detected
    case duplicateProvider(provider: String)
    /// Stream buffer capacity is invalid
    case invalidBufferCapacity(capacity: Int)
    /// Timeout value is invalid
    case invalidTimeout(value: TimeInterval, reason: String)
    /// Invalid retry configuration
    case invalidRetryConfiguration(reason: String)
    /// Invalid circuit breaker configuration
    case invalidCircuitBreakerConfiguration(reason: String)
    /// Invalid failover configuration
    case invalidFailoverConfiguration(reason: String)
    /// Invalid max concurrent requests
    case invalidMaxConcurrentRequests(value: Int)
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
        case .duplicateProvider(let provider):
            return "Duplicate provider configuration: \(provider)"
        case .invalidBufferCapacity(let capacity):
            return "Invalid buffer capacity: \(capacity). Must be > 0."
        case .invalidTimeout(let value, let reason):
            return "Invalid timeout \(value)s: \(reason)"
        case .invalidRetryConfiguration(let reason):
            return "Invalid retry configuration: \(reason)"
        case .invalidCircuitBreakerConfiguration(let reason):
            return "Invalid circuit breaker configuration: \(reason)"
        case .invalidFailoverConfiguration(let reason):
            return "Invalid failover configuration: \(reason)"
        case .invalidMaxConcurrentRequests(let value):
            return "Invalid maxConcurrentRequests: \(value). Must be >= 0."
        case .multipleErrors(let errors):
            let descriptions = errors.compactMap { $0.errorDescription }
            return "Multiple configuration errors:\n" + descriptions.joined(separator: "\n")
        }
    }
}

// MARK: - Provider Configuration

/// Configuration for a specific AI provider
public struct AIProviderConfiguration: Sendable, Equatable {
    /// The provider identifier (normalized to lowercase)
    public let provider: String

    /// The original provider identifier as provided
    public let providerId: String

    /// API key for this provider (nil if using environment variable)
    public let apiKey: String?

    /// Environment variable names for API key resolution (checked in order)
    public let apiKeyEnvVars: [String]

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

    /// Whether API key is required for this provider
    public let requiresAPIKey: Bool

    public init(
        provider: String,
        apiKey: String? = nil,
        apiKeyEnvVar: String? = nil,
        apiKeyEnvVars: [String]? = nil,
        baseURL: URL? = nil,
        organizationId: String? = nil,
        projectId: String? = nil,
        defaultModel: String? = nil,
        maxRequestsPerMinute: Int? = nil,
        maxTokensPerMinute: Int? = nil,
        customHeaders: [String: String] = [:],
        isEnabled: Bool = true,
        trustedForPHI: Bool = false,
        requiresAPIKey: Bool = true
    ) {
        self.providerId = provider
        self.provider = provider.lowercased()
        self.apiKey = apiKey

        // Build env var list: explicit vars first, then default
        var envVars: [String] = []
        if let vars = apiKeyEnvVars {
            envVars.append(contentsOf: vars)
        } else if let envVar = apiKeyEnvVar {
            envVars.append(envVar)
        }
        // Add default if not already present
        let defaultVar = Self.defaultEnvVar(for: provider)
        if !envVars.contains(defaultVar) {
            envVars.append(defaultVar)
        }
        self.apiKeyEnvVars = envVars

        self.baseURL = baseURL
        self.organizationId = organizationId
        self.projectId = projectId
        self.defaultModel = defaultModel
        self.maxRequestsPerMinute = maxRequestsPerMinute
        self.maxTokensPerMinute = maxTokensPerMinute
        self.customHeaders = customHeaders
        self.isEnabled = isEnabled
        self.trustedForPHI = trustedForPHI
        self.requiresAPIKey = requiresAPIKey
    }

    /// Default environment variable name for a provider
    private static func defaultEnvVar(for provider: String) -> String {
        "\(provider.uppercased())_API_KEY"
    }

    /// Resolve the API key from explicit value or environment variables
    public func resolveAPIKey() -> String? {
        if let apiKey = apiKey, !apiKey.isEmpty {
            return apiKey
        }
        // Try each env var in order
        for envVar in apiKeyEnvVars {
            if let key = ProcessInfo.processInfo.environment[envVar], !key.isEmpty {
                return key
            }
        }
        return nil
    }

    /// Check if API key is available (explicit or from environment)
    public var hasAPIKey: Bool {
        resolveAPIKey() != nil
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
/// // Or use builder pattern with closure
/// try AISDKConfiguration.configure { builder in
///     builder.defaultModel("gpt-4o")
///     builder.addProvider(.openai(apiKey: "sk-..."))
///     builder.reliability(.default)
/// }
/// ```
public struct AISDKConfiguration: Sendable {
    // MARK: - Properties

    /// Default model to use when not specified in requests
    public let defaultModel: String?

    /// Provider configurations indexed by normalized provider name (lowercase)
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
    ///
    /// When true (default), requests with `.sensitive` or `.phi` data sensitivity
    /// require explicit `allowedProviders` to be set. This prevents accidental
    /// routing of PHI data to untrusted providers.
    ///
    /// Note: This flag is checked by `isProviderAllowedForSensitivity(_:_:)`.
    /// Integration with request routing is handled in the Provider & Routing Layer.
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

        // Build providers dictionary with duplicate detection
        var providerDict: [String: AIProviderConfiguration] = [:]
        var duplicates: [String] = []
        for config in providers {
            let key = config.provider  // Already normalized to lowercase
            if providerDict[key] != nil {
                duplicates.append(config.providerId)
            } else {
                providerDict[key] = config
            }
        }

        // Check for duplicates before assignment
        if !duplicates.isEmpty {
            if duplicates.count == 1 {
                throw AISDKConfigurationError.duplicateProvider(provider: duplicates[0])
            } else {
                throw AISDKConfigurationError.multipleErrors(
                    duplicates.map { .duplicateProvider(provider: $0) }
                )
            }
        }

        self.providers = providerDict
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

        // Validate default model if specified
        if let model = defaultModel, model.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.invalidDefaultModel(model: model))
        }

        // Validate buffer policy
        if case .dropOldest(let capacity) = defaultBufferPolicy, capacity <= 0 {
            errors.append(.invalidBufferCapacity(capacity: capacity))
        }
        if case .dropNewest(let capacity) = defaultBufferPolicy, capacity <= 0 {
            errors.append(.invalidBufferCapacity(capacity: capacity))
        }

        // Validate maxConcurrentRequests
        if maxConcurrentRequests < 0 {
            errors.append(.invalidMaxConcurrentRequests(value: maxConcurrentRequests))
        }

        // Validate reliability settings
        errors.append(contentsOf: validateReliability())

        // Validate each provider configuration
        for (_, providerConfig) in providers {
            errors.append(contentsOf: validateProvider(providerConfig))
        }

        // Throw errors if any
        if errors.count == 1 {
            throw errors[0]
        } else if errors.count > 1 {
            throw AISDKConfigurationError.multipleErrors(errors)
        }
    }

    /// Validate reliability configuration
    private func validateReliability() -> [AISDKConfigurationError] {
        var errors: [AISDKConfigurationError] = []

        // Timeout validation
        if reliability.defaultTimeout <= 0 {
            errors.append(.invalidTimeout(
                value: reliability.defaultTimeout,
                reason: "must be positive"
            ))
        }

        // Retry validation
        if reliability.maxRetries < 0 {
            errors.append(.invalidRetryConfiguration(reason: "maxRetries must be >= 0"))
        }
        if reliability.retryBaseDelay <= 0 {
            errors.append(.invalidRetryConfiguration(reason: "retryBaseDelay must be positive"))
        }
        if reliability.retryMaxDelay <= 0 {
            errors.append(.invalidRetryConfiguration(reason: "retryMaxDelay must be positive"))
        }
        if reliability.retryMaxDelay < reliability.retryBaseDelay {
            errors.append(.invalidRetryConfiguration(
                reason: "retryMaxDelay must be >= retryBaseDelay"
            ))
        }

        // Circuit breaker validation
        if reliability.circuitBreakerEnabled {
            if reliability.circuitBreakerThreshold <= 0 {
                errors.append(.invalidCircuitBreakerConfiguration(
                    reason: "threshold must be positive"
                ))
            }
            if reliability.circuitBreakerResetTimeout <= 0 {
                errors.append(.invalidCircuitBreakerConfiguration(
                    reason: "resetTimeout must be positive"
                ))
            }
        }

        // Failover validation
        if reliability.failoverEnabled {
            if reliability.failoverMaxCostMultiplier <= 0 {
                errors.append(.invalidFailoverConfiguration(
                    reason: "maxCostMultiplier must be positive"
                ))
            }
        }

        return errors
    }

    /// Validate a single provider configuration
    private func validateProvider(_ config: AIProviderConfiguration) -> [AISDKConfigurationError] {
        var errors: [AISDKConfigurationError] = []

        // Check for missing API key on enabled providers that require it
        if config.isEnabled && config.requiresAPIKey && !config.hasAPIKey {
            errors.append(.missingAPIKey(provider: config.providerId))
        }

        // Check API key format based on provider
        if let apiKey = config.resolveAPIKey() {
            switch config.provider {
            case "openai":
                if !apiKey.hasPrefix("sk-") {
                    errors.append(.invalidAPIKey(
                        provider: config.providerId,
                        reason: "OpenAI API keys should start with 'sk-'"
                    ))
                }
            case "anthropic":
                if !apiKey.hasPrefix("sk-ant-") {
                    errors.append(.invalidAPIKey(
                        provider: config.providerId,
                        reason: "Anthropic API keys should start with 'sk-ant-'"
                    ))
                }
            default:
                // No specific format validation for other providers
                break
            }
        }

        // Validate default model if specified
        if let model = config.defaultModel, model.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.invalidProviderConfiguration(
                provider: config.providerId,
                reason: "defaultModel cannot be empty"
            ))
        }

        return errors
    }

    // MARK: - Provider Access

    /// Get configuration for a specific provider
    public func provider(_ name: String) -> AIProviderConfiguration? {
        providers[name.lowercased()]
    }

    /// Get all enabled providers
    public var enabledProviders: [AIProviderConfiguration] {
        providers.values.filter { $0.isEnabled }
    }

    /// Get providers trusted for PHI data
    public var phiTrustedProviders: [AIProviderConfiguration] {
        providers.values.filter { $0.trustedForPHI }
    }

    /// Get names of providers trusted for PHI data
    public var phiTrustedProviderNames: Set<String> {
        Set(phiTrustedProviders.map { $0.provider })
    }

    /// Check if a provider is configured
    public func hasProvider(_ name: String) -> Bool {
        provider(name) != nil
    }

    /// Check if a provider is allowed for a given data sensitivity level
    ///
    /// This method enforces PHI protection rules based on `enforcePHIProtection`
    /// and the provider's `trustedForPHI` setting.
    ///
    /// - Parameters:
    ///   - providerName: The provider to check
    ///   - sensitivity: The data sensitivity level
    /// - Returns: true if the provider can handle data at the given sensitivity
    public func isProviderAllowedForSensitivity(
        _ providerName: String,
        _ sensitivity: DataSensitivity
    ) -> Bool {
        guard let config = provider(providerName) else {
            return false  // Unknown provider
        }

        switch sensitivity {
        case .standard:
            return config.isEnabled
        case .sensitive, .phi:
            if !enforcePHIProtection {
                return config.isEnabled  // PHI enforcement disabled
            }
            return config.isEnabled && config.trustedForPHI
        }
    }

    // MARK: - Shared Instance

    /// Lock for thread-safe access to shared instance
    private static let lock = NSLock()

    /// The shared SDK configuration (thread-safe)
    ///
    /// This must be set before using the SDK. Use `configure(_:)` to set.
    /// Access is thread-safe via internal locking.
    private static var _shared: AISDKConfiguration?

    /// Get the shared SDK configuration
    public static var shared: AISDKConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return _shared
    }

    /// Configure the shared SDK instance (thread-safe)
    ///
    /// - Parameter configuration: The configuration to use
    /// - Throws: AISDKConfigurationError if validation fails or already configured
    public static func configure(_ configuration: AISDKConfiguration) throws {
        try configuration.validate()
        lock.lock()
        defer { lock.unlock() }
        _shared = configuration
    }

    /// Configure the shared SDK instance with a builder (thread-safe)
    ///
    /// - Parameter builder: A closure that configures the builder
    /// - Throws: AISDKConfigurationError if validation fails
    public static func configure(_ builder: (inout Builder) -> Void) throws {
        var b = Builder()
        builder(&b)
        let config = try b.build()
        lock.lock()
        defer { lock.unlock() }
        _shared = config
    }

    /// Reset the shared configuration
    ///
    /// - Warning: This is intended for testing only. Do not call in production code.
    @available(*, deprecated, message: "For testing only")
    public static func _resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        _shared = nil
    }
}

// MARK: - Builder

extension AISDKConfiguration {
    /// Builder for AISDKConfiguration
    ///
    /// Provides a fluent API for constructing configuration.
    /// Use with the `configure(_:)` closure-based API.
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
        public mutating func defaultModel(_ model: String) {
            self.defaultModel = model
        }

        /// Add a provider configuration
        public mutating func addProvider(_ provider: AIProviderConfiguration) {
            self.providers.append(provider)
        }

        /// Set the default buffer policy
        public mutating func defaultBufferPolicy(_ policy: StreamBufferPolicy) {
            self.defaultBufferPolicy = policy
        }

        /// Set the default sensitivity level
        public mutating func defaultSensitivity(_ sensitivity: DataSensitivity) {
            self.defaultSensitivity = sensitivity
        }

        /// Set the reliability configuration
        public mutating func reliability(_ config: AIReliabilityConfiguration) {
            self.reliability = config
        }

        /// Set the telemetry configuration
        public mutating func telemetry(_ config: AITelemetryConfiguration) {
            self.telemetry = config
        }

        /// Set whether to enforce PHI protection
        public mutating func enforcePHIProtection(_ enforce: Bool) {
            self.enforcePHIProtection = enforce
        }

        /// Set the maximum concurrent requests
        public mutating func maxConcurrentRequests(_ max: Int) {
            self.maxConcurrentRequests = max
        }

        /// Add a global header
        public mutating func addGlobalHeader(name: String, value: String) {
            self.globalHeaders[name] = value
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
            apiKeyEnvVars: ["OPENAI_API_KEY"],
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
            apiKeyEnvVars: ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY"],
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
            apiKeyEnvVars: ["GOOGLE_API_KEY", "GEMINI_API_KEY"],
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
            apiKeyEnvVars: ["OPENROUTER_API_KEY"],
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
