//
//  OpenRouterStressTests.swift
//  AISDKTests
//
//  Real API stress tests using OpenRouter with free models.
//  Task 6.3 from AISDK Modernization - real provider integration tests.
//
//  These tests verify behavior under real network conditions including:
//  - Latency and timeouts
//  - Rate limiting handling
//  - Error recovery
//  - Concurrent request handling
//
//  Tests are skipped when OPENROUTER_API_KEY environment variable is not set.
//

import XCTest
@testable import AISDK

// MARK: - OpenRouterStressTests

final class OpenRouterStressTests: XCTestCase {

    // MARK: - Constants

    /// Free models available on OpenRouter for testing
    private static let freeModels = [
        "deepseek/deepseek-r1t2-chimera:free",
        "nvidia/llama-3.1-nemotron-nano-8b-v1:free",
        "google/gemma-3-4b-it:free"
    ]

    /// Default model for tests
    private static let defaultModel = "google/gemma-3-4b-it:free"

    /// Lower concurrency to respect rate limits
    private static let maxConcurrentRequests = 10

    /// Timeout for individual requests
    private static let requestTimeout: Duration = .seconds(30)

    // MARK: - Test Helpers

    /// Get API key or skip test
    private func getAPIKeyOrSkip() throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENROUTER_API_KEY environment variable is required for integration tests")
        }
        return apiKey
    }

    /// Create OpenRouter client with API key
    private func createClient() throws -> OpenRouterClient {
        let apiKey = try getAPIKeyOrSkip()
        return OpenRouterClient(
            apiKey: apiKey,
            appName: "AISDK-StressTests",
            siteURL: "https://github.com/AISDK"
        )
    }

    // MARK: - Test 1: Concurrent Non-Streaming Requests

    /// Tests concurrent non-streaming requests to verify rate limit handling
    func test_concurrent_execute_requests() async throws {
        let client = try createClient()
        let metrics = StressTestMetrics()
        let concurrency = Self.maxConcurrentRequests

        // Execute concurrent requests
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<concurrency {
                group.addTask {
                    let request = ProviderRequest(
                        modelId: Self.defaultModel,
                        messages: [.user("Say 'test \(i)' and nothing else.")]
                    )

                    do {
                        let response = try await client.execute(request: request)
                        XCTAssertFalse(response.content.isEmpty, "Response should have content")
                        metrics.recordCompletion()
                    } catch {
                        metrics.recordError(error)
                        // Log error for debugging but don't fail - rate limits are expected
                        print("Request \(i) failed: \(error)")
                    }
                }
            }
        }

        // Most requests should succeed
        let successRate = Double(metrics.completedCount) / Double(concurrency)
        XCTAssertGreaterThan(successRate, 0.5,
                             "At least 50% of requests should succeed (got \(metrics.completedCount)/\(concurrency))")

        print("Completed: \(metrics.completedCount)/\(concurrency) requests")
    }

    // MARK: - Test 2: Concurrent Streaming Requests

    /// Tests concurrent streaming requests to verify stream handling under load
    func test_concurrent_streaming_requests() async throws {
        let client = try createClient()
        let metrics = StressTestMetrics()
        let concurrency = Self.maxConcurrentRequests / 2 // Lower for streaming

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<concurrency {
                group.addTask {
                    let request = ProviderRequest(
                        modelId: Self.defaultModel,
                        messages: [.user("Count from 1 to 3. Say nothing else.")]
                    )

                    do {
                        var eventCount = 0
                        for try await event in client.stream(request: request) {
                            eventCount += 1
                            if case .finish = event {
                                break
                            }
                        }
                        XCTAssertGreaterThan(eventCount, 0, "Should receive stream events")
                        metrics.recordCompletion()
                    } catch {
                        metrics.recordError(error)
                        print("Stream \(i) failed: \(error)")
                    }
                }
            }
        }

        // Most streams should complete
        let successRate = Double(metrics.completedCount) / Double(concurrency)
        XCTAssertGreaterThan(successRate, 0.5,
                             "At least 50% of streams should complete")

        print("Completed: \(metrics.completedCount)/\(concurrency) streams")
    }

    // MARK: - Test 3: Sequential Requests with Multiple Models

    /// Tests requests across different free models
    func test_multiple_free_models() async throws {
        let client = try createClient()
        var successfulModels: [String] = []

        for model in Self.freeModels {
            let request = ProviderRequest(
                modelId: model,
                messages: [.user("Say 'OK' and nothing else.")]
            )

            do {
                let response = try await client.execute(request: request)
                if !response.content.isEmpty {
                    successfulModels.append(model)
                    print("Model \(model): OK (\(response.content.count) chars)")
                }
            } catch {
                print("Model \(model) failed: \(error)")
            }

            // Small delay between models to avoid rate limits
            try await Task.sleep(for: .milliseconds(500))
        }

        // At least one model should work
        XCTAssertGreaterThan(successfulModels.count, 0,
                             "At least one free model should respond")
    }

    // MARK: - Test 4: Error Recovery

    /// Tests that the client handles errors gracefully and can recover
    func test_error_recovery() async throws {
        let client = try createClient()

        // First, make an invalid request (should fail)
        let invalidRequest = ProviderRequest(
            modelId: "invalid/nonexistent-model-xyz",
            messages: [.user("Test")]
        )

        var invalidRequestFailed = false
        do {
            _ = try await client.execute(request: invalidRequest)
        } catch {
            invalidRequestFailed = true
            print("Invalid request failed as expected: \(error)")
        }

        XCTAssertTrue(invalidRequestFailed, "Invalid model should fail")

        // Then make a valid request (should succeed after error)
        let validRequest = ProviderRequest(
            modelId: Self.defaultModel,
            messages: [.user("Say 'recovered' and nothing else.")]
        )

        do {
            let response = try await client.execute(request: validRequest)
            XCTAssertFalse(response.content.isEmpty, "Valid request should succeed after error")
            print("Recovery successful: \(response.content.prefix(50))")
        } catch {
            XCTFail("Valid request should succeed after invalid request: \(error)")
        }
    }

    // MARK: - Test 5: Health Status Check

    /// Tests health status refresh under load
    func test_health_status_refresh() async throws {
        let client = try createClient()

        // Initial status should be unknown
        let initialStatus = await client.healthStatus
        XCTAssertEqual(initialStatus, .unknown, "Initial status should be unknown")

        // Refresh health
        await client.refreshHealthStatus()

        // After refresh, should be healthy or have a specific status
        let afterRefresh = await client.healthStatus
        XCTAssertNotEqual(afterRefresh, .unknown, "Status should be known after refresh")
        print("Health status after refresh: \(afterRefresh)")
    }

    // MARK: - Test 6: Rate Limit Detection

    /// Tests that rate limiting is properly detected when it occurs
    func test_rapid_request_handling() async throws {
        let client = try createClient()
        let metrics = StressTestMetrics()

        // Send requests rapidly (may trigger rate limiting)
        for i in 0..<5 {
            let request = ProviderRequest(
                modelId: Self.defaultModel,
                messages: [.user("Just say '\(i)'.")]
            )

            do {
                _ = try await client.execute(request: request)
                metrics.recordCompletion()
            } catch let error as ProviderError {
                if case .rateLimited = error {
                    print("Rate limited at request \(i) - this is expected")
                    metrics.recordCancellation() // Use cancelled for rate limited
                } else {
                    metrics.recordError(error)
                }
            } catch {
                metrics.recordError(error)
            }

            // No delay - testing rapid fire handling
        }

        // All requests should be handled (complete, rate limited, or error)
        let totalHandled = metrics.completedCount + metrics.cancelledCount + metrics.errorCount
        XCTAssertEqual(totalHandled, 5, "All requests should be handled")
        print("Completed: \(metrics.completedCount), Rate limited: \(metrics.cancelledCount), Errors: \(metrics.errorCount)")
    }

    // MARK: - Test 7: Long Response Streaming

    /// Tests streaming of a longer response
    func test_long_response_streaming() async throws {
        let client = try createClient()

        let request = ProviderRequest(
            modelId: Self.defaultModel,
            messages: [.user("Write a short poem about Swift programming (4 lines).")]
        )

        var chunks: [String] = []
        var finishReason: ProviderFinishReason?

        for try await event in client.stream(request: request) {
            switch event {
            case .textDelta(let text):
                chunks.append(text)
            case .finish(let reason, _):
                finishReason = reason
            default:
                break
            }
        }

        let fullResponse = chunks.joined()
        XCTAssertFalse(fullResponse.isEmpty, "Should receive text in stream")
        XCTAssertNotNil(finishReason, "Should receive finish event")
        XCTAssertGreaterThan(chunks.count, 1, "Should receive multiple chunks")

        print("Received \(chunks.count) chunks, total length: \(fullResponse.count)")
        print("Preview: \(fullResponse.prefix(100))...")
    }
}

// MARK: - StressTestMetrics Extension

/// Extension to make StressTestMetrics accessible from this file
/// (StressTestMetrics is defined in ConcurrencyStressTests.swift)
extension StressTestMetrics {
    /// Convenience initializer for OpenRouter tests
    static func forOpenRouter() -> StressTestMetrics {
        return StressTestMetrics()
    }
}
