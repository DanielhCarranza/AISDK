//
//  AdaptiveCircuitBreaker.swift
//  AISDK
//
//  Actor-based circuit breaker with adaptive thresholds for provider reliability.
//  Uses monotonic time (ContinuousClock) for reliable timing across system sleep/wake.
//

import Foundation

// MARK: - CircuitBreakerState

/// The current state of a circuit breaker.
public enum CircuitBreakerState: Sendable, Equatable, CustomStringConvertible {
    /// Circuit is closed, requests flow normally.
    /// Failures are counted towards the threshold.
    case closed

    /// Circuit is open, requests are immediately rejected.
    /// The circuit will transition to half-open after the recovery timeout.
    case open(until: ContinuousClock.Instant)

    /// Circuit is half-open, allowing a limited number of probe requests.
    /// Success will close the circuit, failure will re-open it.
    case halfOpen

    public var description: String {
        switch self {
        case .closed:
            return "closed"
        case .open(let until):
            return "open(until: \(until))"
        case .halfOpen:
            return "halfOpen"
        }
    }

    /// Whether the circuit breaker accepts traffic in this state.
    public var acceptsTraffic: Bool {
        switch self {
        case .closed, .halfOpen:
            return true
        case .open:
            return false
        }
    }
}

// MARK: - CircuitBreakerConfiguration

/// Configuration for a circuit breaker instance.
public struct CircuitBreakerConfiguration: Sendable {
    /// Number of consecutive failures before opening the circuit.
    public let failureThreshold: Int

    /// Duration to wait before transitioning from open to half-open.
    public let recoveryTimeout: Duration

    /// Number of successful requests required in half-open state to close the circuit.
    public let successThreshold: Int

    /// Maximum number of probe requests allowed in half-open state.
    public let halfOpenMaxProbes: Int

    /// Sliding window size for failure rate calculation (0 = use consecutive failures only).
    public let slidingWindowSize: Int

    /// Failure rate threshold (0.0-1.0) when using sliding window.
    public let failureRateThreshold: Double

    /// Optional identifier for this configuration (for persistence/logging).
    public let identifier: String?

    /// Creates a circuit breaker configuration.
    ///
    /// - Parameters:
    ///   - failureThreshold: Failures before opening (default: 5)
    ///   - recoveryTimeout: Time before trying again (default: 30 seconds)
    ///   - successThreshold: Successes needed to close from half-open (default: 2)
    ///   - halfOpenMaxProbes: Max probes in half-open (default: 3)
    ///   - slidingWindowSize: Window for failure rate (default: 0, disabled)
    ///   - failureRateThreshold: Rate threshold when using window (default: 0.5)
    ///   - identifier: Optional ID for this config
    public init(
        failureThreshold: Int = 5,
        recoveryTimeout: Duration = .seconds(30),
        successThreshold: Int = 2,
        halfOpenMaxProbes: Int = 3,
        slidingWindowSize: Int = 0,
        failureRateThreshold: Double = 0.5,
        identifier: String? = nil
    ) {
        self.failureThreshold = max(1, failureThreshold)
        self.recoveryTimeout = recoveryTimeout
        self.successThreshold = max(1, successThreshold)
        self.halfOpenMaxProbes = max(1, halfOpenMaxProbes)
        self.slidingWindowSize = max(0, slidingWindowSize)
        self.failureRateThreshold = min(1.0, max(0.0, failureRateThreshold))
        self.identifier = identifier
    }

    /// Default configuration for standard use cases.
    public static let `default` = CircuitBreakerConfiguration()

    /// Aggressive configuration for critical paths (faster failure detection).
    public static let aggressive = CircuitBreakerConfiguration(
        failureThreshold: 3,
        recoveryTimeout: .seconds(15),
        successThreshold: 1,
        halfOpenMaxProbes: 1
    )

    /// Lenient configuration for unstable providers (more tolerance).
    public static let lenient = CircuitBreakerConfiguration(
        failureThreshold: 10,
        recoveryTimeout: .seconds(60),
        successThreshold: 3,
        halfOpenMaxProbes: 5
    )
}

// MARK: - CircuitBreakerError

/// Errors thrown by the circuit breaker.
public enum CircuitBreakerError: Error, LocalizedError, Sendable {
    /// The circuit is open and not accepting requests.
    case circuitOpen(until: ContinuousClock.Instant)

    /// Too many probe requests in half-open state.
    case halfOpenLimitExceeded

    /// The operation was rejected due to circuit breaker policy.
    case rejected(reason: String)

    public var errorDescription: String? {
        switch self {
        case .circuitOpen(let until):
            return "Circuit breaker is open until \(until)"
        case .halfOpenLimitExceeded:
            return "Circuit breaker is half-open and probe limit exceeded"
        case .rejected(let reason):
            return "Request rejected: \(reason)"
        }
    }
}

// MARK: - CircuitBreakerMetrics

/// Metrics collected by the circuit breaker.
public struct CircuitBreakerMetrics: Sendable {
    /// Total number of successful requests.
    public let totalSuccesses: Int

    /// Total number of failed requests.
    public let totalFailures: Int

    /// Number of consecutive failures.
    public let consecutiveFailures: Int

    /// Number of times the circuit has opened.
    public let openCount: Int

    /// Current state of the circuit.
    public let state: CircuitBreakerState

    /// Last state transition time.
    public let lastStateChange: ContinuousClock.Instant?

    /// Failure rate in the sliding window (if enabled).
    public let slidingWindowFailureRate: Double?
}

// MARK: - CircuitBreakerDelegate

/// Delegate protocol for receiving circuit breaker state change notifications.
public protocol CircuitBreakerDelegate: Sendable {
    /// Called when the circuit breaker state changes.
    func circuitBreaker(
        _ breaker: AdaptiveCircuitBreaker,
        didTransitionFrom oldState: CircuitBreakerState,
        to newState: CircuitBreakerState
    ) async

    /// Called when a request is rejected due to circuit breaker policy.
    func circuitBreaker(
        _ breaker: AdaptiveCircuitBreaker,
        didRejectRequest error: CircuitBreakerError
    ) async
}

// Default empty implementation
public extension CircuitBreakerDelegate {
    func circuitBreaker(
        _ breaker: AdaptiveCircuitBreaker,
        didTransitionFrom oldState: CircuitBreakerState,
        to newState: CircuitBreakerState
    ) async {}

    func circuitBreaker(
        _ breaker: AdaptiveCircuitBreaker,
        didRejectRequest error: CircuitBreakerError
    ) async {}
}

// MARK: - AdaptiveCircuitBreaker

/// Actor-based circuit breaker with adaptive failure detection.
///
/// The circuit breaker prevents cascading failures by temporarily stopping
/// requests to a failing provider. It uses three states:
///
/// 1. **Closed**: Normal operation, requests flow through. Failures are counted.
/// 2. **Open**: Provider is failing, requests are immediately rejected.
/// 3. **Half-Open**: Testing if provider has recovered with probe requests.
///
/// ## Usage
/// ```swift
/// let breaker = AdaptiveCircuitBreaker(configuration: .default)
///
/// do {
///     let result = try await breaker.execute {
///         try await provider.makeRequest()
///     }
/// } catch CircuitBreakerError.circuitOpen {
///     // Handle circuit open - use fallback
/// }
/// ```
///
/// ## Monotonic Time
/// Uses `ContinuousClock` for timing to ensure reliability across system
/// sleep/wake cycles and NTP adjustments.
public actor AdaptiveCircuitBreaker {
    // MARK: - Properties

    /// Configuration for this circuit breaker.
    public let configuration: CircuitBreakerConfiguration

    /// Optional delegate for state change notifications.
    public var delegate: (any CircuitBreakerDelegate)?

    /// The clock used for time measurements.
    private let clock: ContinuousClock

    // State tracking
    private var state: CircuitBreakerState = .closed
    private var consecutiveFailures: Int = 0
    private var consecutiveSuccesses: Int = 0
    private var halfOpenProbeCount: Int = 0
    private var lastStateChange: ContinuousClock.Instant?

    // Metrics
    private var totalSuccesses: Int = 0
    private var totalFailures: Int = 0
    private var openCount: Int = 0

    // Sliding window for failure rate calculation
    private var slidingWindow: [Bool] = []

    // MARK: - Initialization

    /// Creates a new adaptive circuit breaker.
    ///
    /// - Parameters:
    ///   - configuration: The circuit breaker configuration.
    ///   - delegate: Optional delegate for state notifications.
    ///   - clock: Clock for time measurements (default: ContinuousClock()).
    public init(
        configuration: CircuitBreakerConfiguration = .default,
        delegate: (any CircuitBreakerDelegate)? = nil,
        clock: ContinuousClock = ContinuousClock()
    ) {
        self.configuration = configuration
        self.delegate = delegate
        self.clock = clock
    }

    // MARK: - Public API

    /// The current state of the circuit breaker.
    public var currentState: CircuitBreakerState {
        get async {
            // Check if we should transition from open to half-open
            await checkAndTransitionState()
            return state
        }
    }

    /// Whether the circuit breaker is currently accepting requests.
    public var isAvailable: Bool {
        get async {
            await checkAndTransitionState()
            return state.acceptsTraffic
        }
    }

    /// Current metrics for this circuit breaker.
    public var metrics: CircuitBreakerMetrics {
        CircuitBreakerMetrics(
            totalSuccesses: totalSuccesses,
            totalFailures: totalFailures,
            consecutiveFailures: consecutiveFailures,
            openCount: openCount,
            state: state,
            lastStateChange: lastStateChange,
            slidingWindowFailureRate: calculateSlidingWindowFailureRate()
        )
    }

    /// Execute an operation through the circuit breaker.
    ///
    /// - Parameter operation: The async operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: `CircuitBreakerError` if the circuit is open, or the operation's error.
    public func execute<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        // Check if we can proceed
        try await checkCanProceed()

        // Execute the operation
        do {
            let result = try await operation()
            await recordSuccess()
            return result
        } catch {
            await recordFailure()
            throw error
        }
    }

    /// Record a successful operation (for external tracking).
    public func recordSuccess() async {
        totalSuccesses += 1
        consecutiveFailures = 0
        consecutiveSuccesses += 1

        // Update sliding window
        if configuration.slidingWindowSize > 0 {
            recordInSlidingWindow(success: true)
        }

        // Handle half-open state
        if case .halfOpen = state {
            if consecutiveSuccesses >= configuration.successThreshold {
                await transitionTo(.closed)
            }
        }
    }

    /// Record a failed operation (for external tracking).
    public func recordFailure() async {
        totalFailures += 1
        consecutiveFailures += 1
        consecutiveSuccesses = 0

        // Update sliding window
        if configuration.slidingWindowSize > 0 {
            recordInSlidingWindow(success: false)
        }

        // Check if we should open the circuit
        switch state {
        case .closed:
            if shouldOpenCircuit() {
                let recoveryTime = clock.now + configuration.recoveryTimeout
                await transitionTo(.open(until: recoveryTime))
            }

        case .halfOpen:
            // Any failure in half-open immediately re-opens
            let recoveryTime = clock.now + configuration.recoveryTimeout
            await transitionTo(.open(until: recoveryTime))

        case .open:
            // Already open, nothing to do
            break
        }
    }

    /// Reset the circuit breaker to closed state.
    public func reset() async {
        let oldState = state
        state = .closed
        consecutiveFailures = 0
        consecutiveSuccesses = 0
        halfOpenProbeCount = 0
        slidingWindow.removeAll()

        if oldState != .closed {
            lastStateChange = clock.now
            await delegate?.circuitBreaker(self, didTransitionFrom: oldState, to: .closed)
        }
    }

    /// Force the circuit to open for the specified duration.
    public func forceOpen(for duration: Duration) async {
        let recoveryTime = clock.now + duration
        await transitionTo(.open(until: recoveryTime))
    }

    // MARK: - Private Methods

    private func checkCanProceed() async throws {
        await checkAndTransitionState()

        switch state {
        case .closed:
            return // Proceed normally

        case .open(let until):
            let error = CircuitBreakerError.circuitOpen(until: until)
            await delegate?.circuitBreaker(self, didRejectRequest: error)
            throw error

        case .halfOpen:
            if halfOpenProbeCount >= configuration.halfOpenMaxProbes {
                let error = CircuitBreakerError.halfOpenLimitExceeded
                await delegate?.circuitBreaker(self, didRejectRequest: error)
                throw error
            }
            halfOpenProbeCount += 1
        }
    }

    private func checkAndTransitionState() async {
        if case .open(let until) = state {
            if clock.now >= until {
                await transitionTo(.halfOpen)
            }
        }
    }

    private func transitionTo(_ newState: CircuitBreakerState) async {
        let oldState = state

        // Skip if same state (accounting for open time differences)
        switch (oldState, newState) {
        case (.closed, .closed), (.halfOpen, .halfOpen):
            return
        case (.open, .open):
            // Update the open time even if already open
            break
        default:
            break
        }

        state = newState
        lastStateChange = clock.now

        // Reset counters on state transition
        switch newState {
        case .closed:
            consecutiveFailures = 0
            consecutiveSuccesses = 0
            halfOpenProbeCount = 0

        case .open:
            openCount += 1
            halfOpenProbeCount = 0

        case .halfOpen:
            consecutiveSuccesses = 0
            halfOpenProbeCount = 0
        }

        await delegate?.circuitBreaker(self, didTransitionFrom: oldState, to: newState)
    }

    private func shouldOpenCircuit() -> Bool {
        // Check consecutive failures
        if consecutiveFailures >= configuration.failureThreshold {
            return true
        }

        // Check sliding window failure rate
        if configuration.slidingWindowSize > 0,
           let failureRate = calculateSlidingWindowFailureRate(),
           slidingWindow.count >= configuration.slidingWindowSize {
            return failureRate >= configuration.failureRateThreshold
        }

        return false
    }

    private func recordInSlidingWindow(success: Bool) {
        slidingWindow.append(success)
        if slidingWindow.count > configuration.slidingWindowSize {
            slidingWindow.removeFirst()
        }
    }

    private func calculateSlidingWindowFailureRate() -> Double? {
        guard configuration.slidingWindowSize > 0, !slidingWindow.isEmpty else {
            return nil
        }
        let failures = slidingWindow.filter { !$0 }.count
        return Double(failures) / Double(slidingWindow.count)
    }
}

// MARK: - Provider-Specific Circuit Breakers

/// A registry of circuit breakers for different providers.
public actor CircuitBreakerRegistry {
    private var breakers: [String: AdaptiveCircuitBreaker] = [:]
    private let defaultConfiguration: CircuitBreakerConfiguration

    /// Creates a new circuit breaker registry.
    ///
    /// - Parameter defaultConfiguration: Default configuration for new breakers.
    public init(defaultConfiguration: CircuitBreakerConfiguration = .default) {
        self.defaultConfiguration = defaultConfiguration
    }

    /// Get or create a circuit breaker for a provider.
    ///
    /// - Parameters:
    ///   - providerId: The provider identifier.
    ///   - configuration: Optional custom configuration (uses default if nil).
    /// - Returns: The circuit breaker for the provider.
    public func breaker(
        for providerId: String,
        configuration: CircuitBreakerConfiguration? = nil
    ) -> AdaptiveCircuitBreaker {
        if let existing = breakers[providerId] {
            return existing
        }

        let config = configuration ?? defaultConfiguration
        let breaker = AdaptiveCircuitBreaker(configuration: config)
        breakers[providerId] = breaker
        return breaker
    }

    /// Remove a circuit breaker for a provider.
    public func removeBreaker(for providerId: String) {
        breakers.removeValue(forKey: providerId)
    }

    /// Reset all circuit breakers.
    public func resetAll() async {
        for breaker in breakers.values {
            await breaker.reset()
        }
    }

    /// Get metrics for all registered circuit breakers.
    public func allMetrics() async -> [String: CircuitBreakerMetrics] {
        var result: [String: CircuitBreakerMetrics] = [:]
        for (id, breaker) in breakers {
            result[id] = await breaker.metrics
        }
        return result
    }
}
