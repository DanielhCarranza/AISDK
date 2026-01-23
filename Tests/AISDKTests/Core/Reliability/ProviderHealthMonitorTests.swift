//
//  ProviderHealthMonitorTests.swift
//  AISDK
//
//  Tests for ProviderHealthMonitor.
//

import Foundation
import Testing
import XCTest
@testable import AISDK

// MARK: - HealthMonitorConfiguration Tests

@Suite("HealthMonitorConfiguration Tests")
struct HealthMonitorConfigurationTests {
    @Test("Default configuration has expected values")
    func testDefaultConfiguration() {
        let config = HealthMonitorConfiguration.default

        #expect(config.maxSamples == 1000)
        #expect(config.unhealthyErrorRateThreshold == 0.5)
        #expect(config.degradedLatencyThreshold == .seconds(10))
        #expect(config.minimumRequestsForStatus == 10)
    }

    @Test("Sensitive configuration has lower thresholds")
    func testSensitiveConfiguration() {
        let config = HealthMonitorConfiguration.sensitive

        #expect(config.unhealthyErrorRateThreshold == 0.2)
        #expect(config.degradedLatencyThreshold == .seconds(5))
        #expect(config.minimumRequestsForStatus == 5)
    }

    @Test("Custom configuration clamps values")
    func testCustomConfigurationClamping() {
        let config = HealthMonitorConfiguration(
            maxSamples: 5,  // Below minimum
            unhealthyErrorRateThreshold: 1.5,  // Above max
            minimumRequestsForStatus: 0  // Below minimum
        )

        #expect(config.maxSamples == 10)  // Clamped to minimum
        #expect(config.unhealthyErrorRateThreshold == 1.0)  // Clamped to max
        #expect(config.minimumRequestsForStatus == 1)  // Clamped to minimum
    }

    @Test("Negative error rate threshold is clamped to 0")
    func testNegativeErrorRateThreshold() {
        let config = HealthMonitorConfiguration(unhealthyErrorRateThreshold: -0.5)
        #expect(config.unhealthyErrorRateThreshold == 0.0)
    }
}

// MARK: - HealthStatus Tests

@Suite("HealthStatus Tests")
struct HealthStatusTests {
    @Test("HealthStatus creates with all properties")
    func testHealthStatusCreation() {
        let status = HealthStatus(
            providerId: "openai",
            isHealthy: true,
            latencyP50: .milliseconds(200),
            latencyP99: .milliseconds(800),
            errorRate: 0.05,
            requestCount: 100,
            errorCount: 5
        )

        #expect(status.providerId == "openai")
        #expect(status.isHealthy == true)
        #expect(status.latencyP50 == .milliseconds(200))
        #expect(status.latencyP99 == .milliseconds(800))
        #expect(status.errorRate == 0.05)
        #expect(status.requestCount == 100)
        #expect(status.errorCount == 5)
    }

    @Test("HealthStatus is Equatable")
    func testHealthStatusEquatable() {
        let date = Date()
        let status1 = HealthStatus(
            providerId: "openai",
            isHealthy: true,
            latencyP50: .milliseconds(200),
            latencyP99: .milliseconds(800),
            errorRate: 0.05,
            requestCount: 100,
            errorCount: 5,
            lastUpdated: date
        )
        let status2 = HealthStatus(
            providerId: "openai",
            isHealthy: true,
            latencyP50: .milliseconds(200),
            latencyP99: .milliseconds(800),
            errorRate: 0.05,
            requestCount: 100,
            errorCount: 5,
            lastUpdated: date
        )

        #expect(status1 == status2)
    }
}

// MARK: - ProviderHealthMonitor XCTest Tests

final class ProviderHealthMonitorTests: XCTestCase {
    func test_recordLatency_incrementsRequestCount() async {
        let monitor = ProviderHealthMonitor()

        await monitor.recordLatency(.milliseconds(100), for: "openai")
        await monitor.recordLatency(.milliseconds(150), for: "openai")

        let status = await monitor.healthStatus(for: "openai")
        XCTAssertEqual(status.requestCount, 2)
        XCTAssertEqual(status.errorCount, 0)
    }

    func test_recordError_incrementsErrorCount() async {
        let monitor = ProviderHealthMonitor()

        await monitor.recordError(for: "openai")
        await monitor.recordError(for: "openai")

        let status = await monitor.healthStatus(for: "openai")
        XCTAssertEqual(status.requestCount, 2)
        XCTAssertEqual(status.errorCount, 2)
        XCTAssertEqual(status.errorRate, 1.0)
    }

    func test_recordSuccess_incrementsRequestCount() async {
        let monitor = ProviderHealthMonitor()

        await monitor.recordSuccess(for: "openai")

        let status = await monitor.healthStatus(for: "openai")
        XCTAssertEqual(status.requestCount, 1)
        XCTAssertEqual(status.errorCount, 0)
    }

    func test_recordResult_handlesSuccessWithLatency() async {
        let monitor = ProviderHealthMonitor()

        await monitor.recordResult(success: true, latency: .milliseconds(100), for: "openai")

        let status = await monitor.healthStatus(for: "openai")
        XCTAssertEqual(status.requestCount, 1)
        XCTAssertTrue(status.latencyP50 > .zero)
    }

    func test_recordResult_handlesFailure() async {
        let monitor = ProviderHealthMonitor()

        await monitor.recordResult(success: false, for: "openai")

        let status = await monitor.healthStatus(for: "openai")
        XCTAssertEqual(status.errorCount, 1)
    }

    func test_healthStatus_calculatesPercentiles() async {
        let monitor = ProviderHealthMonitor()

        // Add latencies with known values
        for i in 1...100 {
            await monitor.recordLatency(.milliseconds(i * 10), for: "openai")
        }

        let status = await monitor.healthStatus(for: "openai")
        XCTAssertEqual(status.requestCount, 100)
        // P50 should be around 500ms (median of 10-1000ms)
        XCTAssertTrue(status.latencyP50 >= .milliseconds(400))
        XCTAssertTrue(status.latencyP50 <= .milliseconds(600))
        // P99 should be near the top
        XCTAssertTrue(status.latencyP99 >= .milliseconds(900))
    }

    func test_healthStatus_healthyWhenLowErrorRate() async {
        let config = HealthMonitorConfiguration(
            unhealthyErrorRateThreshold: 0.5,
            minimumRequestsForStatus: 5
        )
        let monitor = ProviderHealthMonitor(configuration: config)

        // 10% error rate
        for _ in 0..<9 {
            await monitor.recordSuccess(for: "openai")
        }
        await monitor.recordError(for: "openai")

        let status = await monitor.healthStatus(for: "openai")
        XCTAssertTrue(status.isHealthy)
        XCTAssertEqual(status.errorRate, 0.1)
    }

    func test_healthStatus_unhealthyWhenHighErrorRate() async {
        let config = HealthMonitorConfiguration(
            unhealthyErrorRateThreshold: 0.5,
            minimumRequestsForStatus: 5
        )
        let monitor = ProviderHealthMonitor(configuration: config)

        // 60% error rate
        for _ in 0..<4 {
            await monitor.recordSuccess(for: "openai")
        }
        for _ in 0..<6 {
            await monitor.recordError(for: "openai")
        }

        let status = await monitor.healthStatus(for: "openai")
        XCTAssertFalse(status.isHealthy)
        XCTAssertEqual(status.errorRate, 0.6)
    }

    func test_healthStatus_healthyWhenNotEnoughData() async {
        let config = HealthMonitorConfiguration(minimumRequestsForStatus: 10)
        let monitor = ProviderHealthMonitor(configuration: config)

        // Only 5 requests, all errors
        for _ in 0..<5 {
            await monitor.recordError(for: "openai")
        }

        // Should still be healthy because not enough data
        let status = await monitor.healthStatus(for: "openai")
        XCTAssertTrue(status.isHealthy)
    }

    func test_isHealthy_returnsTrueForHealthyProvider() async {
        let monitor = ProviderHealthMonitor()

        for _ in 0..<10 {
            await monitor.recordSuccess(for: "openai")
        }

        let healthy = await monitor.isHealthy("openai")
        XCTAssertTrue(healthy)
    }

    func test_healthyProviders_filtersUnhealthy() async {
        let config = HealthMonitorConfiguration(
            unhealthyErrorRateThreshold: 0.3,
            minimumRequestsForStatus: 5
        )
        let monitor = ProviderHealthMonitor(configuration: config)

        // openai is healthy (0% errors)
        for _ in 0..<10 {
            await monitor.recordSuccess(for: "openai")
        }

        // anthropic is unhealthy (50% errors)
        for _ in 0..<5 {
            await monitor.recordSuccess(for: "anthropic")
        }
        for _ in 0..<5 {
            await monitor.recordError(for: "anthropic")
        }

        let healthy = await monitor.healthyProviders(from: ["openai", "anthropic", "google"])
        XCTAssertTrue(healthy.contains("openai"))
        XCTAssertFalse(healthy.contains("anthropic"))
        // google has no data, so it's healthy by default
        XCTAssertTrue(healthy.contains("google"))
    }

    func test_allHealthStatuses_returnsAllTracked() async {
        let monitor = ProviderHealthMonitor()

        await monitor.recordSuccess(for: "openai")
        await monitor.recordSuccess(for: "anthropic")
        await monitor.recordError(for: "google")

        let statuses = await monitor.allHealthStatuses()
        XCTAssertEqual(statuses.count, 3)
        XCTAssertNotNil(statuses["openai"])
        XCTAssertNotNil(statuses["anthropic"])
        XCTAssertNotNil(statuses["google"])
    }

    func test_reset_clearsProviderData() async {
        let monitor = ProviderHealthMonitor()

        await monitor.recordSuccess(for: "openai")
        await monitor.recordError(for: "openai")

        var status = await monitor.healthStatus(for: "openai")
        XCTAssertEqual(status.requestCount, 2)

        await monitor.reset(providerId: "openai")

        status = await monitor.healthStatus(for: "openai")
        XCTAssertEqual(status.requestCount, 0)
    }

    func test_resetAll_clearsAllData() async {
        let monitor = ProviderHealthMonitor()

        await monitor.recordSuccess(for: "openai")
        await monitor.recordSuccess(for: "anthropic")

        var statuses = await monitor.allHealthStatuses()
        XCTAssertEqual(statuses.count, 2)

        await monitor.resetAll()

        statuses = await monitor.allHealthStatuses()
        XCTAssertEqual(statuses.count, 0)
    }

    func test_latencySamples_trimmedWhenOverMax() async {
        let config = HealthMonitorConfiguration(maxSamples: 100)
        let monitor = ProviderHealthMonitor(configuration: config)

        // Add 200 samples
        for i in 0..<200 {
            await monitor.recordLatency(.milliseconds(i), for: "openai")
        }

        let status = await monitor.healthStatus(for: "openai")
        // Should have trimmed to around 50-100 samples
        // (trims to half when over limit)
        XCTAssertEqual(status.requestCount, 200)  // Request count stays
        // Latency samples are internal, but we can verify P50/P99 work
        XCTAssertTrue(status.latencyP50 > .zero)
    }

    func test_unknownProvider_returnsEmptyHealthStatus() async {
        let monitor = ProviderHealthMonitor()

        let status = await monitor.healthStatus(for: "unknown")

        XCTAssertEqual(status.providerId, "unknown")
        XCTAssertEqual(status.requestCount, 0)
        XCTAssertEqual(status.errorCount, 0)
        XCTAssertEqual(status.errorRate, 0.0)
        XCTAssertTrue(status.isHealthy)  // No data = healthy by default
    }
}

// MARK: - Configuration Equatable Tests

@Suite("HealthMonitorConfiguration Equatable Tests")
struct HealthMonitorConfigurationEquatableTests {
    @Test("Same configurations are equal")
    func testSameConfigsEqual() {
        let config1 = HealthMonitorConfiguration.default
        let config2 = HealthMonitorConfiguration.default

        #expect(config1 == config2)
    }

    @Test("Different configurations are not equal")
    func testDifferentConfigsNotEqual() {
        let config1 = HealthMonitorConfiguration.default
        let config2 = HealthMonitorConfiguration.sensitive

        #expect(config1 != config2)
    }
}
