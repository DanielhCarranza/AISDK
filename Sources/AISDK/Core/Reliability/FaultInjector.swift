//
//  FaultInjector.swift
//  AISDK
//
//  Testing utility for injecting faults into provider operations.
//  Enables chaos testing and reliability validation for the AISDK reliability layer.
//

import Foundation

// MARK: - FaultType

/// Types of faults that can be injected for testing.
public enum FaultType: Sendable, Equatable, CustomStringConvertible {
    /// Inject a specific error.
    case error(ProviderError)

    /// Inject a delay before the operation proceeds.
    case delay(Duration)

    /// Inject a timeout (operation never completes within expected time).
    case timeout

    /// Randomly fail with the given probability (0.0-1.0).
    case randomFailure(probability: Double, error: ProviderError)

    /// Inject intermittent failures (fail N times, then succeed).
    case intermittent(failCount: Int, error: ProviderError)

    /// Inject latency jitter (random delay within range).
    case latencyJitter(min: Duration, max: Duration)

    /// Inject a rate limit error with retry-after.
    case rateLimited(retryAfter: TimeInterval)

    /// Inject a server error with specific status code.
    case serverError(statusCode: Int, message: String)

    /// Corrupt the response (for testing parse error handling).
    case corruptResponse

    public var description: String {
        switch self {
        case .error(let error):
            return "error(\(error))"
        case .delay(let duration):
            return "delay(\(duration))"
        case .timeout:
            return "timeout"
        case .randomFailure(let probability, _):
            return "randomFailure(p=\(probability))"
        case .intermittent(let failCount, _):
            return "intermittent(failCount=\(failCount))"
        case .latencyJitter(let min, let max):
            return "latencyJitter(\(min)-\(max))"
        case .rateLimited(let retryAfter):
            return "rateLimited(retryAfter=\(retryAfter))"
        case .serverError(let statusCode, _):
            return "serverError(\(statusCode))"
        case .corruptResponse:
            return "corruptResponse"
        }
    }
}

// MARK: - FaultRule

/// A rule that defines when and what fault to inject.
public struct FaultRule: Sendable {
    /// Unique identifier for this rule.
    public let id: String

    /// The type of fault to inject.
    public let faultType: FaultType

    /// Optional provider ID filter (nil matches all providers).
    public let providerId: String?

    /// Optional model ID filter (nil matches all models).
    public let modelId: String?

    /// Whether this rule is currently active.
    public let isActive: Bool

    /// Optional description of the rule for logging/debugging.
    public let description: String?

    /// Creates a new fault rule.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this rule
    ///   - faultType: The type of fault to inject
    ///   - providerId: Optional provider ID to match
    ///   - modelId: Optional model ID to match
    ///   - isActive: Whether the rule is active (default: true)
    ///   - description: Optional description
    public init(
        id: String = UUID().uuidString,
        faultType: FaultType,
        providerId: String? = nil,
        modelId: String? = nil,
        isActive: Bool = true,
        description: String? = nil
    ) {
        self.id = id
        self.faultType = faultType
        self.providerId = providerId
        self.modelId = modelId
        self.isActive = isActive
        self.description = description
    }

    /// Check if this rule matches the given context.
    public func matches(providerId: String?, modelId: String?) -> Bool {
        guard isActive else { return false }

        // Check provider filter
        if let ruleProviderId = self.providerId {
            guard providerId == ruleProviderId else { return false }
        }

        // Check model filter
        if let ruleModelId = self.modelId {
            guard modelId == ruleModelId else { return false }
        }

        return true
    }
}

// MARK: - FaultInjectionResult

/// The result of applying fault injection.
public enum FaultInjectionResult: Sendable {
    /// No fault was injected, proceed normally.
    case proceed

    /// A delay was injected, proceed after delay.
    case delayed(Duration)

    /// An error should be thrown.
    case fail(Error)

    /// The response should be corrupted (for testing parse error handling).
    case corrupt
}

// MARK: - FaultInjectorMetrics

/// Metrics collected by the fault injector.
public struct FaultInjectorMetrics: Sendable {
    /// Total number of fault evaluations.
    public let totalEvaluations: Int

    /// Number of faults that were injected.
    public let faultsInjected: Int

    /// Breakdown of injected faults by type.
    public let faultsByType: [String: Int]

    /// Number of active rules.
    public let activeRules: Int
}

// MARK: - FaultInjectorDelegate

/// Delegate protocol for receiving fault injection notifications.
public protocol FaultInjectorDelegate: Sendable {
    /// Called when a fault is about to be injected.
    func faultInjector(
        _ injector: FaultInjector,
        willInject fault: FaultType,
        for providerId: String?,
        modelId: String?
    ) async

    /// Called after a fault has been injected.
    func faultInjector(
        _ injector: FaultInjector,
        didInject fault: FaultType,
        result: FaultInjectionResult
    ) async
}

/// Default empty implementation.
public extension FaultInjectorDelegate {
    func faultInjector(
        _ injector: FaultInjector,
        willInject fault: FaultType,
        for providerId: String?,
        modelId: String?
    ) async {}

    func faultInjector(
        _ injector: FaultInjector,
        didInject fault: FaultType,
        result: FaultInjectionResult
    ) async {}
}

// MARK: - FaultInjector

/// Actor-based fault injector for testing reliability patterns.
///
/// The fault injector allows you to simulate various failure scenarios
/// to validate that your reliability mechanisms (circuit breaker, retry,
/// failover) work correctly under adverse conditions.
///
/// ## Usage
/// ```swift
/// let injector = FaultInjector()
///
/// // Add a rule to simulate rate limiting for OpenAI
/// await injector.addRule(FaultRule(
///     faultType: .rateLimited(retryAfter: 30),
///     providerId: "openai"
/// ))
///
/// // Wrap your operation with fault injection
/// let result = try await injector.withFaultInjection(
///     providerId: "openai",
///     modelId: "gpt-4"
/// ) {
///     try await provider.execute(request)
/// }
/// ```
///
/// ## Chaos Testing
/// ```swift
/// // Random failures for chaos testing
/// await injector.addRule(FaultRule(
///     faultType: .randomFailure(probability: 0.3, error: .networkError("Simulated")),
///     description: "30% random network failures"
/// ))
/// ```
public actor FaultInjector {
    // MARK: - Properties

    /// All registered fault rules.
    private var rules: [String: FaultRule] = [:]

    /// Mutable state for intermittent failures (rule ID -> remaining fail count).
    private var intermittentState: [String: Int] = [:]

    /// Optional delegate for notifications.
    public var delegate: (any FaultInjectorDelegate)?

    /// Whether fault injection is globally enabled.
    public var isEnabled: Bool = true

    // Metrics
    private var totalEvaluations: Int = 0
    private var faultsInjected: Int = 0
    private var faultsByType: [String: Int] = [:]

    // MARK: - Initialization

    /// Creates a new fault injector.
    ///
    /// - Parameters:
    ///   - delegate: Optional delegate for fault injection notifications
    ///   - enabled: Whether fault injection is initially enabled (default: true)
    public init(
        delegate: (any FaultInjectorDelegate)? = nil,
        enabled: Bool = true
    ) {
        self.delegate = delegate
        self.isEnabled = enabled
    }

    // MARK: - Rule Management

    /// Add a fault rule to the injector.
    ///
    /// - Parameter rule: The rule to add
    public func addRule(_ rule: FaultRule) {
        rules[rule.id] = rule

        // Initialize intermittent state if needed
        if case .intermittent(let failCount, _) = rule.faultType {
            intermittentState[rule.id] = failCount
        }
    }

    /// Remove a fault rule by ID.
    ///
    /// - Parameter ruleId: The ID of the rule to remove
    /// - Returns: The removed rule, if it existed
    @discardableResult
    public func removeRule(id ruleId: String) -> FaultRule? {
        intermittentState.removeValue(forKey: ruleId)
        return rules.removeValue(forKey: ruleId)
    }

    /// Remove all fault rules.
    public func removeAllRules() {
        rules.removeAll()
        intermittentState.removeAll()
    }

    /// Get all active rules.
    public var activeRules: [FaultRule] {
        rules.values.filter(\.isActive)
    }

    /// Get a specific rule by ID.
    public func rule(id ruleId: String) -> FaultRule? {
        rules[ruleId]
    }

    /// Enable or disable a rule by ID.
    ///
    /// - Parameters:
    ///   - ruleId: The ID of the rule
    ///   - enabled: Whether to enable or disable the rule
    public func setRuleEnabled(id ruleId: String, enabled: Bool) {
        guard var rule = rules[ruleId] else { return }
        rule = FaultRule(
            id: rule.id,
            faultType: rule.faultType,
            providerId: rule.providerId,
            modelId: rule.modelId,
            isActive: enabled,
            description: rule.description
        )
        rules[ruleId] = rule
    }

    // MARK: - Fault Injection

    /// Evaluate rules and determine what fault (if any) to inject.
    ///
    /// - Parameters:
    ///   - providerId: The provider ID (optional)
    ///   - modelId: The model ID (optional)
    /// - Returns: The fault injection result
    public func evaluate(
        providerId: String? = nil,
        modelId: String? = nil
    ) async -> FaultInjectionResult {
        guard isEnabled else { return .proceed }

        totalEvaluations += 1

        // Find the first matching active rule
        guard let matchingRule = rules.values.first(where: { $0.matches(providerId: providerId, modelId: modelId) }) else {
            return .proceed
        }

        // Notify delegate
        await delegate?.faultInjector(self, willInject: matchingRule.faultType, for: providerId, modelId: modelId)

        let result = applyFault(matchingRule)

        // Update metrics
        if case .proceed = result {} else {
            faultsInjected += 1
            let typeName = String(describing: type(of: matchingRule.faultType))
            faultsByType[typeName, default: 0] += 1
        }

        // Notify delegate
        await delegate?.faultInjector(self, didInject: matchingRule.faultType, result: result)

        return result
    }

    /// Execute an operation with fault injection applied.
    ///
    /// - Parameters:
    ///   - providerId: The provider ID (optional)
    ///   - modelId: The model ID (optional)
    ///   - operation: The operation to execute
    /// - Returns: The result of the operation
    /// - Throws: Injected errors or errors from the operation
    public func withFaultInjection<T: Sendable>(
        providerId: String? = nil,
        modelId: String? = nil,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        let result = await evaluate(providerId: providerId, modelId: modelId)

        switch result {
        case .proceed:
            return try await operation()

        case .delayed(let duration):
            try await Task.sleep(for: duration)
            return try await operation()

        case .fail(let error):
            throw error

        case .corrupt:
            // For corrupt, we still execute but the caller should handle the response
            // This is typically used in streaming tests where the stream is corrupted
            return try await operation()
        }
    }

    // MARK: - Metrics

    /// Get current metrics for the fault injector.
    public var metrics: FaultInjectorMetrics {
        FaultInjectorMetrics(
            totalEvaluations: totalEvaluations,
            faultsInjected: faultsInjected,
            faultsByType: faultsByType,
            activeRules: rules.values.filter(\.isActive).count
        )
    }

    /// Reset all metrics.
    public func resetMetrics() {
        totalEvaluations = 0
        faultsInjected = 0
        faultsByType.removeAll()
    }

    /// Reset intermittent failure state for all rules.
    public func resetIntermittentState() {
        for (ruleId, rule) in rules {
            if case .intermittent(let failCount, _) = rule.faultType {
                intermittentState[ruleId] = failCount
            }
        }
    }

    // MARK: - Private Methods

    private func applyFault(_ rule: FaultRule) -> FaultInjectionResult {
        switch rule.faultType {
        case .error(let error):
            return .fail(error)

        case .delay(let duration):
            return .delayed(duration)

        case .timeout:
            // Return a very long delay to simulate timeout
            return .delayed(.seconds(3600))

        case .randomFailure(let probability, let error):
            if Double.random(in: 0..<1) < probability {
                return .fail(error)
            }
            return .proceed

        case .intermittent(_, let error):
            if let remaining = intermittentState[rule.id], remaining > 0 {
                intermittentState[rule.id] = remaining - 1
                return .fail(error)
            }
            return .proceed

        case .latencyJitter(let min, let max):
            let minNanos = Double(min.components.seconds) * 1_000_000_000 +
                           Double(min.components.attoseconds) / 1_000_000_000
            let maxNanos = Double(max.components.seconds) * 1_000_000_000 +
                           Double(max.components.attoseconds) / 1_000_000_000
            let randomNanos = Double.random(in: minNanos...maxNanos)
            let seconds = Int64(randomNanos / 1_000_000_000)
            let attoseconds = Int64((randomNanos.truncatingRemainder(dividingBy: 1_000_000_000)) * 1_000_000_000)
            return .delayed(Duration(secondsComponent: seconds, attosecondsComponent: attoseconds))

        case .rateLimited(let retryAfter):
            return .fail(ProviderError.rateLimited(retryAfter: retryAfter))

        case .serverError(let statusCode, let message):
            return .fail(ProviderError.serverError(statusCode: statusCode, message: message))

        case .corruptResponse:
            return .corrupt
        }
    }
}

// MARK: - Convenience Builders

public extension FaultInjector {
    /// Create a fault injector configured for chaos testing.
    ///
    /// - Parameters:
    ///   - failureProbability: Probability of random failures (0.0-1.0)
    ///   - latencyRange: Optional range for latency jitter
    /// - Returns: A configured fault injector
    static func chaosTest(
        failureProbability: Double = 0.1,
        latencyRange: (min: Duration, max: Duration)? = nil
    ) async -> FaultInjector {
        let injector = FaultInjector()

        // Add random failure rule
        await injector.addRule(FaultRule(
            id: "chaos-random-failure",
            faultType: .randomFailure(
                probability: failureProbability,
                error: .networkError("Chaos test: simulated network failure")
            ),
            description: "Chaos test random failures"
        ))

        // Add latency jitter if specified
        if let range = latencyRange {
            await injector.addRule(FaultRule(
                id: "chaos-latency-jitter",
                faultType: .latencyJitter(min: range.min, max: range.max),
                description: "Chaos test latency jitter"
            ))
        }

        return injector
    }

    /// Create a fault injector that simulates a provider being down.
    ///
    /// - Parameter providerId: The provider to simulate as down
    /// - Returns: A configured fault injector
    static func providerDown(
        _ providerId: String
    ) async -> FaultInjector {
        let injector = FaultInjector()

        await injector.addRule(FaultRule(
            id: "provider-down-\(providerId)",
            faultType: .serverError(statusCode: 503, message: "Service Unavailable"),
            providerId: providerId,
            description: "Simulate \(providerId) being down"
        ))

        return injector
    }

    /// Create a fault injector that simulates rate limiting.
    ///
    /// - Parameters:
    ///   - providerId: Optional provider to rate limit (nil for all)
    ///   - retryAfter: Seconds to wait before retry
    /// - Returns: A configured fault injector
    static func rateLimited(
        providerId: String? = nil,
        retryAfter: TimeInterval = 30
    ) async -> FaultInjector {
        let injector = FaultInjector()

        await injector.addRule(FaultRule(
            id: "rate-limited",
            faultType: .rateLimited(retryAfter: retryAfter),
            providerId: providerId,
            description: "Simulate rate limiting"
        ))

        return injector
    }
}

// MARK: - Testing Integration

public extension FaultInjector {
    /// Assert that at least one fault was injected.
    ///
    /// - Throws: An error if no faults were injected
    func assertFaultsInjected() throws {
        guard faultsInjected > 0 else {
            throw FaultInjectorError.noFaultsInjected
        }
    }

    /// Assert that a specific number of faults were injected.
    ///
    /// - Parameter count: Expected number of faults
    /// - Throws: An error if the count doesn't match
    func assertFaultCount(_ count: Int) throws {
        guard faultsInjected == count else {
            throw FaultInjectorError.unexpectedFaultCount(expected: count, actual: faultsInjected)
        }
    }
}

// MARK: - FaultInjectorError

/// Errors thrown by FaultInjector assertions.
public enum FaultInjectorError: Error, LocalizedError, Sendable {
    case noFaultsInjected
    case unexpectedFaultCount(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .noFaultsInjected:
            return "Expected at least one fault to be injected, but none were"
        case .unexpectedFaultCount(let expected, let actual):
            return "Expected \(expected) faults to be injected, but \(actual) were"
        }
    }
}
