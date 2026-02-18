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

    /// Inject a timeout error (throws ProviderError.timeout).
    case timeout(TimeInterval)

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

    /// Inject a corrupt/parse error (simulates invalid response data).
    /// This maps to ProviderError.parseError to test error handling paths.
    case corruptResponse(message: String)

    public var description: String {
        switch self {
        case .error(let error):
            return "error(\(error))"
        case .delay(let duration):
            return "delay(\(duration))"
        case .timeout(let seconds):
            return "timeout(\(seconds)s)"
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

    /// The case name for metrics tracking.
    public var caseName: String {
        switch self {
        case .error: return "error"
        case .delay: return "delay"
        case .timeout: return "timeout"
        case .randomFailure: return "randomFailure"
        case .intermittent: return "intermittent"
        case .latencyJitter: return "latencyJitter"
        case .rateLimited: return "rateLimited"
        case .serverError: return "serverError"
        case .corruptResponse: return "corruptResponse"
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

    /// Priority for rule ordering (higher values = higher priority, evaluated first).
    public let priority: Int

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
    ///   - priority: Rule priority (default: 0, higher = evaluated first)
    ///   - description: Optional description
    public init(
        id: String = UUID().uuidString,
        faultType: FaultType,
        providerId: String? = nil,
        modelId: String? = nil,
        isActive: Bool = true,
        priority: Int = 0,
        description: String? = nil
    ) {
        self.id = id
        self.faultType = faultType
        self.providerId = providerId
        self.modelId = modelId
        self.isActive = isActive
        self.priority = priority
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
/// Note: Uses ProviderError for fail case to ensure Sendable conformance.
public enum FaultInjectionResult: Sendable {
    /// No fault was injected, proceed normally.
    case proceed

    /// A delay was injected, proceed after delay.
    case delayed(Duration)

    /// An error should be thrown (constrained to ProviderError for Sendable safety).
    case fail(ProviderError)
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
    /// Note: Called synchronously via nonisolated to avoid reentrancy issues.
    nonisolated func faultInjectorWillInject(
        fault: FaultType,
        providerId: String?,
        modelId: String?
    )

    /// Called after a fault has been injected.
    /// Note: Called synchronously via nonisolated to avoid reentrancy issues.
    nonisolated func faultInjectorDidInject(
        fault: FaultType,
        result: FaultInjectionResult,
        providerId: String?,
        modelId: String?
    )
}

/// Default empty implementation.
public extension FaultInjectorDelegate {
    nonisolated func faultInjectorWillInject(
        fault: FaultType,
        providerId: String?,
        modelId: String?
    ) {}

    nonisolated func faultInjectorDidInject(
        fault: FaultType,
        result: FaultInjectionResult,
        providerId: String?,
        modelId: String?
    ) {}
}

// MARK: - FaultInjector

/// Actor-based fault injector for testing reliability patterns.
///
/// The fault injector allows you to simulate various failure scenarios
/// to validate that your reliability mechanisms (circuit breaker, retry,
/// failover) work correctly under adverse conditions.
///
/// ## Rule Evaluation
/// Only the first matching rule (by priority order) is applied per evaluation.
/// For chaos testing with multiple effects, use compound rules or multiple
/// sequential evaluations.
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

    /// All registered fault rules (ordered by priority, descending).
    private var rules: [FaultRule] = []

    /// Index for fast lookup by rule ID.
    private var ruleIndex: [String: Int] = [:]

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
    /// Note: If a rule with the same ID exists, it is replaced and its
    /// intermittent state is reset.
    ///
    /// - Parameter rule: The rule to add
    public func addRule(_ rule: FaultRule) {
        // Remove existing rule with same ID if present
        if let existingIndex = ruleIndex[rule.id] {
            rules.remove(at: existingIndex)
            intermittentState.removeValue(forKey: rule.id)
            rebuildIndex()
        }

        // Add rule and sort by priority (descending)
        rules.append(rule)
        rules.sort { $0.priority > $1.priority }
        rebuildIndex()

        // Initialize intermittent state if needed
        if case .intermittent(let failCount, _) = rule.faultType {
            let validatedCount = max(0, failCount)
            intermittentState[rule.id] = validatedCount
        }
    }

    /// Remove a fault rule by ID.
    ///
    /// - Parameter ruleId: The ID of the rule to remove
    /// - Returns: The removed rule, if it existed
    @discardableResult
    public func removeRule(id ruleId: String) -> FaultRule? {
        guard let index = ruleIndex[ruleId] else { return nil }
        let rule = rules.remove(at: index)
        intermittentState.removeValue(forKey: ruleId)
        rebuildIndex()
        return rule
    }

    /// Remove all fault rules.
    public func removeAllRules() {
        rules.removeAll()
        ruleIndex.removeAll()
        intermittentState.removeAll()
    }

    /// Get all active rules.
    public var activeRules: [FaultRule] {
        rules.filter(\.isActive)
    }

    /// Get a specific rule by ID.
    public func rule(id ruleId: String) -> FaultRule? {
        guard let index = ruleIndex[ruleId] else { return nil }
        return rules[index]
    }

    /// Enable or disable a rule by ID.
    ///
    /// - Parameters:
    ///   - ruleId: The ID of the rule
    ///   - enabled: Whether to enable or disable the rule
    public func setRuleEnabled(id ruleId: String, enabled: Bool) {
        guard let index = ruleIndex[ruleId] else { return }
        let oldRule = rules[index]
        let newRule = FaultRule(
            id: oldRule.id,
            faultType: oldRule.faultType,
            providerId: oldRule.providerId,
            modelId: oldRule.modelId,
            isActive: enabled,
            priority: oldRule.priority,
            description: oldRule.description
        )
        rules[index] = newRule
    }

    private func rebuildIndex() {
        ruleIndex.removeAll()
        for (index, rule) in rules.enumerated() {
            ruleIndex[rule.id] = index
        }
    }

    // MARK: - Fault Injection

    /// Evaluate rules and determine what fault (if any) to inject.
    /// Only the first matching rule (by priority) is applied.
    ///
    /// - Parameters:
    ///   - providerId: The provider ID (optional)
    ///   - modelId: The model ID (optional)
    /// - Returns: The fault injection result
    public func evaluate(
        providerId: String? = nil,
        modelId: String? = nil
    ) -> FaultInjectionResult {
        guard isEnabled else { return .proceed }

        totalEvaluations += 1

        // Find the first matching active rule (rules are sorted by priority)
        guard let matchingRule = rules.first(where: { $0.matches(providerId: providerId, modelId: modelId) }) else {
            return .proceed
        }

        // Capture rule info before applying (for atomic operation)
        let faultType = matchingRule.faultType

        // Notify delegate synchronously (nonisolated) to avoid reentrancy
        delegate?.faultInjectorWillInject(
            fault: faultType,
            providerId: providerId,
            modelId: modelId
        )

        let result = applyFault(matchingRule)

        // Update metrics
        if case .proceed = result {} else {
            faultsInjected += 1
            faultsByType[faultType.caseName, default: 0] += 1
        }

        // Notify delegate synchronously (nonisolated) to avoid reentrancy
        delegate?.faultInjectorDidInject(
            fault: faultType,
            result: result,
            providerId: providerId,
            modelId: modelId
        )

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
        let result = evaluate(providerId: providerId, modelId: modelId)

        switch result {
        case .proceed:
            return try await operation()

        case .delayed(let duration):
            // Clamp negative durations to zero for safety
            let safeDuration = max(duration, .zero)
            if safeDuration > .zero {
                try await Task.sleep(for: safeDuration)
            }
            return try await operation()

        case .fail(let error):
            throw error
        }
    }

    // MARK: - Metrics

    /// Get current metrics for the fault injector.
    public var metrics: FaultInjectorMetrics {
        FaultInjectorMetrics(
            totalEvaluations: totalEvaluations,
            faultsInjected: faultsInjected,
            faultsByType: faultsByType,
            activeRules: rules.filter(\.isActive).count
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
        for rule in rules {
            if case .intermittent(let failCount, _) = rule.faultType {
                intermittentState[rule.id] = max(0, failCount)
            }
        }
    }

    // MARK: - Private Methods

    private func applyFault(_ rule: FaultRule) -> FaultInjectionResult {
        switch rule.faultType {
        case .error(let error):
            return .fail(error)

        case .delay(let duration):
            // Clamp to non-negative
            return .delayed(max(duration, .zero))

        case .timeout(let seconds):
            // Clamp to non-negative and throw timeout error immediately
            let validSeconds = max(0, seconds)
            return .fail(ProviderError.timeout(validSeconds))

        case .randomFailure(let probability, let error):
            // Clamp probability to [0, 1]
            let validProbability = max(0, min(1, probability))
            if Double.random(in: 0..<1) < validProbability {
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
            // Validate and swap if needed, clamp to non-negative
            let clampedMin = Swift.max(min, .zero)
            let clampedMax = Swift.max(max, .zero)
            let actualMin = Swift.min(clampedMin, clampedMax)
            let actualMax = Swift.max(clampedMin, clampedMax)

            // Convert to nanoseconds for random selection
            let minNanos = Double(actualMin.components.seconds) * 1_000_000_000 +
                           Double(actualMin.components.attoseconds) / 1_000_000_000
            let maxNanos = Double(actualMax.components.seconds) * 1_000_000_000 +
                           Double(actualMax.components.attoseconds) / 1_000_000_000

            // Handle edge case where min == max
            let randomNanos = minNanos == maxNanos ? minNanos : Double.random(in: minNanos...maxNanos)

            // Convert back to Duration
            let seconds = Int64(randomNanos / 1_000_000_000)
            let remainingNanos = randomNanos.truncatingRemainder(dividingBy: 1_000_000_000)
            let attoseconds = Int64(remainingNanos * 1_000_000_000)
            return .delayed(Duration(secondsComponent: seconds, attosecondsComponent: attoseconds))

        case .rateLimited(let retryAfter):
            let validRetryAfter = max(0, retryAfter)
            return .fail(ProviderError.rateLimited(retryAfter: validRetryAfter))

        case .serverError(let statusCode, let message):
            return .fail(ProviderError.serverError(statusCode: statusCode, message: message))

        case .corruptResponse(let message):
            // Map to parseError to simulate corrupt/invalid response data
            return .fail(ProviderError.parseError(message))
        }
    }
}

// MARK: - Convenience Builders

public extension FaultInjector {
    /// Create a fault injector configured for chaos testing with random failures.
    ///
    /// - Parameters:
    ///   - failureProbability: Probability of random failures (0.0-1.0), clamped to valid range
    /// - Returns: A configured fault injector
    static func chaosTest(
        failureProbability: Double = 0.1
    ) async -> FaultInjector {
        let injector = FaultInjector()

        let validProbability = max(0, min(1, failureProbability))
        await injector.addRule(FaultRule(
            id: "chaos-random-failure",
            faultType: .randomFailure(
                probability: validProbability,
                error: .networkError("Chaos test: simulated network failure")
            ),
            priority: 0,
            description: "Chaos test random failures"
        ))

        return injector
    }

    /// Create a fault injector configured for chaos testing with latency jitter.
    ///
    /// - Parameters:
    ///   - failureProbability: Probability of random failures (0.0-1.0)
    ///   - latencyRange: Range for latency jitter
    /// - Returns: A configured fault injector
    ///
    /// Note: Creates a single combined rule where latency is applied,
    /// then random failure is evaluated.
    static func chaosTest(
        failureProbability: Double = 0.1,
        latencyRange: (min: Duration, max: Duration)
    ) async -> FaultInjector {
        let injector = FaultInjector()

        // Add latency jitter rule
        await injector.addRule(FaultRule(
            id: "chaos-latency-jitter",
            faultType: .latencyJitter(min: latencyRange.min, max: latencyRange.max),
            priority: 10,
            description: "Chaos test latency jitter"
        ))

        // Add random failure rule (evaluated if latency doesn't fail)
        let validProbability = max(0, min(1, failureProbability))
        await injector.addRule(FaultRule(
            id: "chaos-random-failure",
            faultType: .randomFailure(
                probability: validProbability,
                error: .networkError("Chaos test: simulated network failure")
            ),
            priority: 0,
            description: "Chaos test random failures"
        ))

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
            faultType: .rateLimited(retryAfter: max(0, retryAfter)),
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
