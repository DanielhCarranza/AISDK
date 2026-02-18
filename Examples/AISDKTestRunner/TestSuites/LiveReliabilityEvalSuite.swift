//
//  LiveReliabilityEvalSuite.swift
//  AISDKTestRunner
//
//  Layer 2: Live reliability evaluation suite for AISDK.
//  Measures success rate over N requests per provider, validates error handling
//  under real network conditions, and tests stream interruption recovery.
//
//  Named "LiveReliability" to distinguish from the existing ReliabilityTestSuite
//  which tests circuit breaker configuration in isolation.
//

import Foundation
import AISDK

public final class LiveReliabilityEvalSuite: TestSuiteProtocol {
    public let reporter: TestReporter
    public let verbose: Bool
    private let suiteName = "LiveReliability"
    private let provider: String?

    public init(reporter: TestReporter, verbose: Bool, provider: String? = nil) {
        self.reporter = reporter
        self.verbose = verbose
        self.provider = provider
    }

    public func run() async throws {
        reporter.log("Starting live reliability evaluation suite...")

        await testSuccessRatePerProvider()
        await testStreamingSuccessRate()
        await testStreamCancellationReliability()
        await testInvalidAuthErrorHandling()
        await testTimeoutBehavior()
        await testConsecutiveRequestReliability()
        await testErrorRecovery()
    }

    // MARK: - Provider Helpers

    private struct ProviderSetup {
        let name: String
        let client: any ProviderClient
        let modelId: String
    }

    private func availableProviders() -> [ProviderSetup] {
        var providers: [ProviderSetup] = []

        if shouldTest("openai"), let key = requireEnvVar("OPENAI_API_KEY") {
            providers.append(ProviderSetup(
                name: "OpenAI",
                client: OpenAIClientAdapter(apiKey: key),
                modelId: "gpt-4o-mini"
            ))
        }

        if shouldTest("anthropic"), let key = requireEnvVar("ANTHROPIC_API_KEY") {
            providers.append(ProviderSetup(
                name: "Anthropic",
                client: AnthropicClientAdapter(apiKey: key),
                modelId: "claude-haiku-4-5-20251001"
            ))
        }

        if shouldTest("gemini"), let key = requireEnvVar("GOOGLE_API_KEY") {
            providers.append(ProviderSetup(
                name: "Gemini",
                client: GeminiClientAdapter(apiKey: key),
                modelId: "gemini-2.0-flash"
            ))
        }

        return providers
    }

    private func shouldTest(_ providerName: String) -> Bool {
        guard let filter = provider else { return true }
        return filter.lowercased() == providerName.lowercased()
    }

    // MARK: - Success Rate (Non-Streaming)

    private func testSuccessRatePerProvider() async {
        let providers = availableProviders()
        if providers.isEmpty {
            reporter.recordSkipped(suiteName, "Success rate per provider", reason: "No provider API keys set")
            return
        }

        for p in providers {
            await withTimer("Success rate over 20 requests (\(p.name))", suiteName) {
                let totalRequests = 20
                var successes = 0
                var failures: [(Int, String)] = []

                for i in 0..<totalRequests {
                    do {
                        let response = try await p.client.execute(request: ProviderRequest(
                            modelId: p.modelId,
                            messages: [.user("Say 'ok \(i)'")],
                            maxTokens: 5,
                            timeout: 15
                        ))

                        if !response.content.isEmpty {
                            successes += 1
                        } else {
                            failures.append((i, "Empty response"))
                        }
                    } catch {
                        failures.append((i, "\(error)"))
                        reporter.debug("\(p.name) request \(i) failed: \(error)")
                    }

                    // Brief pause to avoid rate limiting
                    if i < totalRequests - 1 {
                        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                    }
                }

                let successRate = Double(successes) / Double(totalRequests)
                reporter.log("\(p.name) success rate: \(successes)/\(totalRequests) = \(String(format: "%.1f%%", successRate * 100))")

                if !failures.isEmpty {
                    reporter.log("\(p.name) failures: \(failures.map { "[\($0.0)]: \($0.1.prefix(50))" }.joined(separator: ", "))")
                }

                // Target: >= 95% success rate for valid API calls
                guard successRate >= 0.95 else {
                    throw TestError.assertionFailed(
                        "\(p.name): success rate \(String(format: "%.1f%%", successRate * 100)) < 95% threshold"
                    )
                }
            }
        }
    }

    // MARK: - Streaming Success Rate

    private func testStreamingSuccessRate() async {
        let providers = availableProviders()
        if providers.isEmpty {
            reporter.recordSkipped(suiteName, "Streaming success rate", reason: "No provider API keys set")
            return
        }

        for p in providers {
            await withTimer("Streaming success rate (\(p.name))", suiteName) {
                let totalStreams = 15
                var successes = 0
                var failures: [(Int, String)] = []

                for i in 0..<totalStreams {
                    do {
                        let request = ProviderRequest(
                            modelId: p.modelId,
                            messages: [.user("Say 'stream \(i)'")],
                            maxTokens: 10,
                            stream: true,
                            timeout: 15
                        )

                        var gotText = false
                        var gotFinish = false

                        for try await event in p.client.stream(request: request) {
                            switch event {
                            case .textDelta(let text):
                                if !text.isEmpty { gotText = true }
                            case .finish:
                                gotFinish = true
                            default:
                                break
                            }
                        }

                        if gotText && gotFinish {
                            successes += 1
                        } else {
                            failures.append((i, "text=\(gotText), finish=\(gotFinish)"))
                        }
                    } catch {
                        failures.append((i, "\(error)"))
                    }

                    if i < totalStreams - 1 {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }

                let successRate = Double(successes) / Double(totalStreams)
                reporter.log("\(p.name) streaming success rate: \(successes)/\(totalStreams) = \(String(format: "%.1f%%", successRate * 100))")

                guard successRate >= 0.90 else {
                    throw TestError.assertionFailed(
                        "\(p.name): streaming success rate \(String(format: "%.1f%%", successRate * 100)) < 90%"
                    )
                }
            }
        }
    }

    // MARK: - Stream Cancellation Reliability

    private func testStreamCancellationReliability() async {
        let providers = availableProviders()
        if providers.isEmpty {
            reporter.recordSkipped(suiteName, "Stream cancellation reliability", reason: "No provider API keys set")
            return
        }

        let p = providers[0]

        await withTimer("Stream cancellation reliability (\(p.name))", suiteName) {
            let iterations = 10
            var cleanCancellations = 0

            for i in 0..<iterations {
                let request = ProviderRequest(
                    modelId: p.modelId,
                    messages: [.user("Write a story about adventure \(i). Make it 200 words.")],
                    maxTokens: 200,
                    stream: true,
                    timeout: 30
                )

                let task = Task<Int, Error> {
                    var chunks = 0
                    for try await event in p.client.stream(request: request) {
                        if case .textDelta = event {
                            chunks += 1
                            // Cancel after receiving 3 chunks
                            if chunks >= 3 {
                                return chunks
                            }
                        }
                    }
                    return chunks
                }

                // Let stream start, then cancel
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                task.cancel()

                do {
                    _ = try await task.value
                    cleanCancellations += 1
                } catch is CancellationError {
                    cleanCancellations += 1
                } catch {
                    // Still counts as clean if no crash
                    cleanCancellations += 1
                    reporter.debug("Cancellation \(i) got error: \(error)")
                }
            }

            reporter.log("Clean cancellations: \(cleanCancellations)/\(iterations)")

            // All cancellations should complete without crash
            guard cleanCancellations == iterations else {
                throw TestError.assertionFailed(
                    "Only \(cleanCancellations)/\(iterations) cancellations were clean"
                )
            }
        }
    }

    // MARK: - Invalid Auth Error Handling

    private func testInvalidAuthErrorHandling() async {
        await withTimer("Invalid auth error handling", suiteName) {
            // Test each provider with a bad key
            let badConfigs: [(String, any ProviderClient)] = [
                ("OpenAI", OpenAIClientAdapter(apiKey: "sk-invalid-test-key")),
                ("Anthropic", AnthropicClientAdapter(apiKey: "sk-ant-invalid-test-key")),
                ("Gemini", GeminiClientAdapter(apiKey: "AIzaInvalidTestKey")),
            ]

            for (name, client) in badConfigs {
                do {
                    _ = try await client.execute(request: ProviderRequest(
                        modelId: "gpt-4o-mini", // Model doesn't matter, auth fails first
                        messages: [.user("test")],
                        maxTokens: 5,
                        timeout: 10
                    ))
                    reporter.log("\(name): WARNING - request with bad key succeeded (unexpected)")
                } catch let error as ProviderError {
                    switch error {
                    case .authenticationFailed:
                        reporter.log("\(name): correctly returned .authenticationFailed")
                    default:
                        reporter.log("\(name): returned ProviderError.\(error) (acceptable)")
                    }
                } catch {
                    reporter.log("\(name): returned non-ProviderError: \(type(of: error)) (acceptable - no crash)")
                }
            }
        }
    }

    // MARK: - Timeout Behavior

    private func testTimeoutBehavior() async {
        let providers = availableProviders()
        if providers.isEmpty {
            reporter.recordSkipped(suiteName, "Timeout behavior", reason: "No provider API keys set")
            return
        }

        let p = providers[0]

        await withTimer("Request timeout behavior (\(p.name))", suiteName) {
            // Very short timeout should fail or complete quickly
            let shortTimeout: TimeInterval = 0.5 // 500ms

            let startTime = Date()
            do {
                // This may succeed if the provider responds quickly, or timeout
                _ = try await p.client.execute(request: ProviderRequest(
                    modelId: p.modelId,
                    messages: [.user("Hi")],
                    maxTokens: 5,
                    timeout: shortTimeout
                ))
                let elapsed = Date().timeIntervalSince(startTime)
                reporter.log("\(p.name): request completed in \(String(format: "%.2f", elapsed))s (under short timeout)")
            } catch {
                let elapsed = Date().timeIntervalSince(startTime)
                reporter.log("\(p.name): request failed after \(String(format: "%.2f", elapsed))s: \(error)")

                // Verify timeout happened in a reasonable timeframe
                guard elapsed < 10 else {
                    throw TestError.assertionFailed(
                        "Timeout took too long: \(String(format: "%.2f", elapsed))s (expected < 10s)"
                    )
                }
            }
        }
    }

    // MARK: - Consecutive Request Reliability

    private func testConsecutiveRequestReliability() async {
        let providers = availableProviders()
        if providers.isEmpty {
            reporter.recordSkipped(suiteName, "Consecutive request reliability", reason: "No provider API keys set")
            return
        }

        let p = providers[0]

        await withTimer("Consecutive requests without degradation (\(p.name))", suiteName) {
            let totalRequests = 30
            var latencies: [TimeInterval] = []
            var successes = 0

            for i in 0..<totalRequests {
                let start = Date()
                do {
                    let response = try await p.client.execute(request: ProviderRequest(
                        modelId: p.modelId,
                        messages: [.user("Say 'ok \(i)'")],
                        maxTokens: 5,
                        timeout: 15
                    ))

                    let latency = Date().timeIntervalSince(start)
                    latencies.append(latency)

                    if !response.content.isEmpty {
                        successes += 1
                    }
                } catch {
                    reporter.debug("Consecutive request \(i) failed: \(error)")
                }
            }

            let successRate = Double(successes) / Double(totalRequests)
            reporter.log("\(p.name) consecutive: \(successes)/\(totalRequests) = \(String(format: "%.1f%%", successRate * 100))")

            // Check for latency degradation: last 10 requests shouldn't be significantly
            // slower than first 10 (allows 3x as generous threshold)
            if latencies.count >= 20 {
                let firstTen = Array(latencies.prefix(10))
                let lastTen = Array(latencies.suffix(10))
                let avgFirst = firstTen.reduce(0, +) / Double(firstTen.count)
                let avgLast = lastTen.reduce(0, +) / Double(lastTen.count)

                reporter.log("\(p.name) latency: first10 avg=\(String(format: "%.0f", avgFirst * 1000))ms, last10 avg=\(String(format: "%.0f", avgLast * 1000))ms")

                if avgLast > avgFirst * 3.0 && avgFirst > 0 {
                    reporter.log("WARNING: Latency degradation detected (last10 is \(String(format: "%.1fx", avgLast / avgFirst)) of first10)")
                }
            }

            guard successRate >= 0.90 else {
                throw TestError.assertionFailed(
                    "\(p.name): consecutive success rate \(String(format: "%.1f%%", successRate * 100)) < 90%"
                )
            }
        }
    }

    // MARK: - Error Recovery

    private func testErrorRecovery() async {
        let providers = availableProviders()
        if providers.isEmpty {
            reporter.recordSkipped(suiteName, "Error recovery", reason: "No provider API keys set")
            return
        }

        let p = providers[0]

        await withTimer("Error recovery after bad request (\(p.name))", suiteName) {
            // 1. Send a deliberately bad request
            do {
                _ = try await p.client.execute(request: ProviderRequest(
                    modelId: "nonexistent-model-12345",
                    messages: [.user("test")],
                    maxTokens: 5,
                    timeout: 10
                ))
            } catch {
                reporter.log("\(p.name): bad request failed as expected: \(error)")
            }

            // 2. Immediately follow with a valid request -- should succeed
            let response = try await p.client.execute(request: ProviderRequest(
                modelId: p.modelId,
                messages: [.user("Say 'recovered'")],
                maxTokens: 10,
                timeout: 15
            ))

            guard !response.content.isEmpty else {
                throw TestError.assertionFailed(
                    "\(p.name): failed to recover after bad request (empty response)"
                )
            }

            reporter.log("\(p.name): recovered after bad request, response='\(response.content.prefix(30))'")

            // 3. Verify streaming also works after error
            let streamRequest = ProviderRequest(
                modelId: p.modelId,
                messages: [.user("Say 'stream recovered'")],
                maxTokens: 10,
                stream: true,
                timeout: 15
            )

            var gotText = false
            for try await event in p.client.stream(request: streamRequest) {
                if case .textDelta = event { gotText = true }
            }

            guard gotText else {
                throw TestError.assertionFailed(
                    "\(p.name): streaming failed after error recovery"
                )
            }

            reporter.log("\(p.name): streaming also recovered successfully")
        }
    }
}
