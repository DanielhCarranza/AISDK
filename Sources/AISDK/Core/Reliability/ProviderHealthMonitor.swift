//
//  ProviderHealthMonitor.swift
//  AISDK
//
//  Proactive health monitoring for AI providers.
//  Tracks latency, error rates, and overall health status.
//

import Foundation

// MARK: - HealthStatus

/// Health status information for a provider.
public struct HealthStatus: Sendable, Equatable {
    /// The provider identifier.
    public let providerId: String

    /// Whether the provider is healthy.
    public let isHealthy: Bool

    /// Median latency (50th percentile).
    public let latencyP50: Duration

    /// 99th percentile latency.
    public let latencyP99: Duration

    /// Error rate (0.0 to 1.0).
    public let errorRate: Double

    /// Total request count.
    public let requestCount: Int

    /// Error count.
    public let errorCount: Int

    /// When the health was last updated.
    public let lastUpdated: Date

    /// Creates a health status.
    public init(
        providerId: String,
        isHealthy: Bool,
        latencyP50: Duration,
        latencyP99: Duration,
        errorRate: Double,
        requestCount: Int,
        errorCount: Int,
        lastUpdated: Date = Date()
    ) {
        self.providerId = providerId
        self.isHealthy = isHealthy
        self.latencyP50 = latencyP50
        self.latencyP99 = latencyP99
        self.errorRate = errorRate
        self.requestCount = requestCount
        self.errorCount = errorCount
        self.lastUpdated = lastUpdated
    }
}

// MARK: - HealthMonitorConfiguration

/// Configuration for the health monitor.
public struct HealthMonitorConfiguration: Sendable, Equatable {
    /// Maximum number of latency samples to keep per provider.
    public let maxSamples: Int

    /// Error rate threshold for unhealthy status (0.0 to 1.0).
    public let unhealthyErrorRateThreshold: Double

    /// Latency P99 threshold for degraded status.
    public let degradedLatencyThreshold: Duration

    /// Minimum requests before health status is meaningful.
    public let minimumRequestsForStatus: Int

    /// Default configuration.
    public static let `default` = HealthMonitorConfiguration(
        maxSamples: 1000,
        unhealthyErrorRateThreshold: 0.5,
        degradedLatencyThreshold: .seconds(10),
        minimumRequestsForStatus: 10
    )

    /// Sensitive configuration with lower thresholds.
    public static let sensitive = HealthMonitorConfiguration(
        maxSamples: 500,
        unhealthyErrorRateThreshold: 0.2,
        degradedLatencyThreshold: .seconds(5),
        minimumRequestsForStatus: 5
    )

    /// Creates a configuration.
    public init(
        maxSamples: Int = 1000,
        unhealthyErrorRateThreshold: Double = 0.5,
        degradedLatencyThreshold: Duration = .seconds(10),
        minimumRequestsForStatus: Int = 10
    ) {
        self.maxSamples = max(10, maxSamples)
        self.unhealthyErrorRateThreshold = min(1.0, max(0.0, unhealthyErrorRateThreshold))
        self.degradedLatencyThreshold = degradedLatencyThreshold
        self.minimumRequestsForStatus = max(1, minimumRequestsForStatus)
    }
}

// MARK: - ProviderHealthMonitor

/// Actor for proactive health monitoring of AI providers.
///
/// Tracks latency and error rates to provide health status information
/// for routing and failover decisions.
public actor ProviderHealthMonitor {
    // MARK: - Properties

    /// Configuration for the monitor.
    public let configuration: HealthMonitorConfiguration

    /// Latency samples per provider.
    private var latencies: [String: [Duration]] = [:]

    /// Error counts per provider.
    private var errorCounts: [String: Int] = [:]

    /// Request counts per provider.
    private var requestCounts: [String: Int] = [:]

    /// Last update timestamps.
    private var lastUpdated: [String: Date] = [:]

    // MARK: - Initialization

    /// Creates a health monitor.
    ///
    /// - Parameter configuration: Monitor configuration
    public init(configuration: HealthMonitorConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Recording Methods

    /// Record a successful request with latency.
    ///
    /// - Parameters:
    ///   - duration: The request latency
    ///   - providerId: The provider identifier
    public func recordLatency(_ duration: Duration, for providerId: String) {
        var providerLatencies = latencies[providerId, default: []]
        providerLatencies.append(duration)

        // Keep within max samples limit
        if providerLatencies.count > configuration.maxSamples {
            let removeCount = providerLatencies.count - configuration.maxSamples / 2
            providerLatencies.removeFirst(removeCount)
        }

        latencies[providerId] = providerLatencies
        requestCounts[providerId, default: 0] += 1
        lastUpdated[providerId] = Date()
    }

    /// Record a successful request.
    ///
    /// - Parameter providerId: The provider identifier
    public func recordSuccess(for providerId: String) {
        requestCounts[providerId, default: 0] += 1
        lastUpdated[providerId] = Date()
    }

    /// Record a failed request.
    ///
    /// - Parameter providerId: The provider identifier
    public func recordError(for providerId: String) {
        errorCounts[providerId, default: 0] += 1
        requestCounts[providerId, default: 0] += 1
        lastUpdated[providerId] = Date()
    }

    /// Record a request result with optional latency.
    ///
    /// - Parameters:
    ///   - success: Whether the request succeeded
    ///   - latency: Optional latency for successful requests
    ///   - providerId: The provider identifier
    public func recordResult(success: Bool, latency: Duration? = nil, for providerId: String) {
        if success {
            if let latency = latency {
                recordLatency(latency, for: providerId)
            } else {
                recordSuccess(for: providerId)
            }
        } else {
            recordError(for: providerId)
        }
    }

    // MARK: - Health Status Methods

    /// Get the current health status for a provider.
    ///
    /// - Parameter providerId: The provider identifier
    /// - Returns: The health status
    public func healthStatus(for providerId: String) -> HealthStatus {
        let providerLatencies = latencies[providerId, default: []]
        let errors = errorCounts[providerId, default: 0]
        let total = requestCounts[providerId, default: 0]
        let updated = lastUpdated[providerId] ?? Date.distantPast

        // Calculate percentiles
        let (p50, p99) = calculatePercentiles(providerLatencies)

        // Calculate error rate
        let errorRate = total > 0 ? Double(errors) / Double(total) : 0.0

        // Determine health
        let isHealthy = determineHealth(
            errorRate: errorRate,
            latencyP99: p99,
            requestCount: total
        )

        return HealthStatus(
            providerId: providerId,
            isHealthy: isHealthy,
            latencyP50: p50,
            latencyP99: p99,
            errorRate: errorRate,
            requestCount: total,
            errorCount: errors,
            lastUpdated: updated
        )
    }

    /// Get health status for all tracked providers.
    ///
    /// - Returns: Dictionary of provider IDs to health status
    public func allHealthStatuses() -> [String: HealthStatus] {
        var statuses: [String: HealthStatus] = [:]
        let allProviderIds = Set(latencies.keys)
            .union(errorCounts.keys)
            .union(requestCounts.keys)

        for providerId in allProviderIds {
            statuses[providerId] = healthStatus(for: providerId)
        }

        return statuses
    }

    /// Check if a provider is healthy.
    ///
    /// - Parameter providerId: The provider identifier
    /// - Returns: True if healthy
    public func isHealthy(_ providerId: String) -> Bool {
        healthStatus(for: providerId).isHealthy
    }

    /// Get the list of healthy providers from a given set.
    ///
    /// - Parameter providerIds: Provider IDs to check
    /// - Returns: List of healthy provider IDs
    public func healthyProviders(from providerIds: [String]) -> [String] {
        providerIds.filter { isHealthy($0) }
    }

    // MARK: - Reset Methods

    /// Reset statistics for a specific provider.
    ///
    /// - Parameter providerId: The provider to reset
    public func reset(providerId: String) {
        latencies.removeValue(forKey: providerId)
        errorCounts.removeValue(forKey: providerId)
        requestCounts.removeValue(forKey: providerId)
        lastUpdated.removeValue(forKey: providerId)
    }

    /// Reset all statistics.
    public func resetAll() {
        latencies.removeAll()
        errorCounts.removeAll()
        requestCounts.removeAll()
        lastUpdated.removeAll()
    }

    // MARK: - Private Helpers

    private func calculatePercentiles(_ latencies: [Duration]) -> (p50: Duration, p99: Duration) {
        guard !latencies.isEmpty else {
            return (.zero, .zero)
        }

        let sorted = latencies.sorted()
        let count = sorted.count

        let p50Index = count / 2
        let p99Index = min(count - 1, Int(Double(count) * 0.99))

        return (sorted[p50Index], sorted[p99Index])
    }

    private func determineHealth(
        errorRate: Double,
        latencyP99: Duration,
        requestCount: Int
    ) -> Bool {
        // Not enough data yet, assume healthy
        if requestCount < configuration.minimumRequestsForStatus {
            return true
        }

        // Check error rate threshold
        if errorRate >= configuration.unhealthyErrorRateThreshold {
            return false
        }

        // Note: We don't mark as unhealthy for high latency alone,
        // but this could be used to mark as "degraded" in the future
        return true
    }
}

// MARK: - HealthMonitorDelegate

/// Delegate protocol for health monitor events.
public protocol HealthMonitorDelegate: AnyObject, Sendable {
    /// Called when a provider's health status changes.
    func healthStatusChanged(providerId: String, status: HealthStatus)

    /// Called when a provider becomes unhealthy.
    func providerBecameUnhealthy(providerId: String, reason: String)

    /// Called when a provider recovers to healthy status.
    func providerRecovered(providerId: String)
}

// MARK: - Default Delegate Implementation

public extension HealthMonitorDelegate {
    func healthStatusChanged(providerId: String, status: HealthStatus) {}
    func providerBecameUnhealthy(providerId: String, reason: String) {}
    func providerRecovered(providerId: String) {}
}
