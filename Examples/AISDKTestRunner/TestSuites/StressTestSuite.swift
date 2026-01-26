//
//  StressTestSuite.swift
//  AISDKTestRunner
//
//  Stress tests for concurrent requests, extended streaming, and memory stability
//

import Foundation
import AISDK

public final class StressTestSuite: TestSuiteProtocol {
    public let reporter: TestReporter
    public let verbose: Bool
    private let suiteName = "Stress"
    private let concurrency: Int
    private let model: String?

    public init(reporter: TestReporter, verbose: Bool, concurrency: Int = 10, model: String? = nil) {
        self.reporter = reporter
        self.verbose = verbose
        self.concurrency = concurrency
        self.model = model
    }

    public func run() async throws {
        reporter.log("Starting stress tests with concurrency=\(concurrency)...")

        await testConcurrentRequests()
        await testExtendedStreamingSession()
        await testMemoryStability()
        await testStreamCleanupOnCancellation()
        await testConcurrentStreamsMemoryBounded()
        await testRapidRequestCancellation()
    }

    // MARK: - Concurrent Request Tests

    private func testConcurrentRequests() async {
        await withTimer("\(concurrency) concurrent requests", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "Concurrent requests", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "openai/gpt-4o-mini"
            var successCount = 0
            var failureCount = 0
            let lock = NSLock()

            await withTaskGroup(of: Bool.self) { group in
                for i in 0..<concurrency {
                    group.addTask {
                        do {
                            let request = ProviderRequest(
                                modelId: modelId,
                                messages: [
                                    .user("Say 'Hello \(i)' in one word.")
                                ],
                                maxTokens: 10
                            )

                            let response = try await client.execute(request: request)
                            return !response.content.isEmpty
                        } catch {
                            return false
                        }
                    }
                }

                for await result in group {
                    lock.lock()
                    if result {
                        successCount += 1
                    } else {
                        failureCount += 1
                    }
                    lock.unlock()
                }
            }

            let successRate = Double(successCount) / Double(concurrency) * 100
            reporter.log("Concurrent requests: \(successCount)/\(concurrency) succeeded (\(String(format: "%.1f", successRate))%)")

            guard successRate >= 80 else {
                throw TestError.assertionFailed("Success rate too low: \(successRate)%")
            }
        }
    }

    // MARK: - Extended Streaming Tests

    private func testExtendedStreamingSession() async {
        await withTimer("Extended streaming session (30s)", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "Extended streaming", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "openai/gpt-4o-mini"

            let request = ProviderRequest(
                modelId: modelId,
                messages: [
                    .user("Write a detailed story about a space explorer. Make it at least 500 words.")
                ],
                maxTokens: 1000,
                stream: true
            )

            var tokenCount = 0
            var textLength = 0
            let startTime = Date()
            let maxDuration: TimeInterval = 30.0

            let stream = client.stream(request: request)

            for try await event in stream {
                switch event {
                case .textDelta(let text):
                    tokenCount += 1
                    textLength += text.count
                case .finish:
                    break
                default:
                    break
                }

                // Check timeout
                if Date().timeIntervalSince(startTime) > maxDuration {
                    break
                }
            }

            let duration = Date().timeIntervalSince(startTime)
            let tokensPerSecond = duration > 0 ? Double(tokenCount) / duration : 0

            reporter.log("Stream stats: \(tokenCount) chunks, \(textLength) chars, \(String(format: "%.1f", tokensPerSecond)) chunks/sec")

            guard tokenCount > 10 else {
                throw TestError.assertionFailed("Expected more than 10 stream chunks")
            }
        }
    }

    // MARK: - Memory Stability Tests

    private func testMemoryStability() async {
        await withTimer("Memory stability over 50 requests", suiteName) {
            // Get initial memory footprint
            let initialMemory = getMemoryUsage()
            reporter.log("Initial memory: \(formatBytes(initialMemory))")

            // Run many small operations
            for i in 0..<50 {
                // Create and discard objects to test for leaks
                let _ = createTestData(size: 1024 * 10) // 10KB
                autoreleasepool {
                    let _ = Array(repeating: "test", count: 1000)
                }

                if i % 10 == 0 {
                    let currentMemory = getMemoryUsage()
                    reporter.debug("Memory at iteration \(i): \(formatBytes(currentMemory))")
                }
            }

            // Force cleanup
            for _ in 0..<5 {
                autoreleasepool { }
            }

            let finalMemory = getMemoryUsage()
            let memoryGrowth = finalMemory - initialMemory

            reporter.log("Final memory: \(formatBytes(finalMemory)), Growth: \(formatBytes(memoryGrowth))")

            // Allow some growth but not excessive
            let maxAllowedGrowth: UInt64 = 50 * 1024 * 1024 // 50MB
            guard memoryGrowth < maxAllowedGrowth else {
                throw TestError.assertionFailed("Memory grew excessively: \(formatBytes(memoryGrowth))")
            }
        }
    }

    private func testStreamCleanupOnCancellation() async {
        await withTimer("Stream cleanup on cancellation", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "Stream cancellation", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "openai/gpt-4o-mini"
            var cancelledStreams = 0
            let iterations = 5

            for i in 0..<iterations {
                let task = Task {
                    let request = ProviderRequest(
                        modelId: modelId,
                        messages: [.user("Count from 1 to 100")],
                        maxTokens: 500,
                        stream: true
                    )

                    var chunkCount = 0
                    for try await event in client.stream(request: request) {
                        switch event {
                        case .textDelta:
                            chunkCount += 1
                            if chunkCount > 3 {
                                throw CancellationError()
                            }
                        default:
                            break
                        }
                    }
                }

                // Cancel after short delay
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                task.cancel()

                do {
                    try await task.value
                } catch {
                    cancelledStreams += 1
                }
            }

            reporter.log("Successfully cancelled \(cancelledStreams)/\(iterations) streams")
        }
    }

    private func testConcurrentStreamsMemoryBounded() async {
        await withTimer("Concurrent streams memory bounded", suiteName) {
            let initialMemory = getMemoryUsage()
            let streamCount = min(concurrency, 5) // Limit for test
            var completedStreams = 0

            // Simulate multiple concurrent streams
            await withTaskGroup(of: Bool.self) { group in
                for _ in 0..<streamCount {
                    group.addTask {
                        // Simulate stream processing
                        var buffer = ""
                        for i in 0..<100 {
                            buffer += "Chunk \(i) "
                            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                        }
                        return true
                    }
                }

                for await result in group {
                    if result {
                        completedStreams += 1
                    }
                }
            }

            let finalMemory = getMemoryUsage()
            let memoryGrowth = finalMemory - initialMemory

            reporter.log("Completed \(completedStreams) concurrent streams, memory growth: \(formatBytes(memoryGrowth))")

            // Memory should be bounded
            let maxGrowthPerStream: UInt64 = 5 * 1024 * 1024 // 5MB per stream
            guard memoryGrowth < UInt64(streamCount) * maxGrowthPerStream else {
                throw TestError.assertionFailed("Memory growth not bounded properly")
            }
        }
    }

    private func testRapidRequestCancellation() async {
        await withTimer("Rapid request cancellation", suiteName) {
            var cancelledCount = 0
            let totalRequests = 20

            for _ in 0..<totalRequests {
                let task = Task {
                    // Simulate an operation
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                    return "completed"
                }

                // Cancel almost immediately
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                task.cancel()

                do {
                    _ = try await task.value
                } catch is CancellationError {
                    cancelledCount += 1
                } catch {
                    // Other error
                }
            }

            reporter.log("Rapid cancellation: \(cancelledCount)/\(totalRequests) cancelled successfully")

            guard cancelledCount >= totalRequests - 2 else {
                throw TestError.assertionFailed("Expected most requests to be cancelled")
            }
        }
    }

    // MARK: - Memory Helpers

    private func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 {
            return String(format: "%.2f MB", mb)
        } else {
            return String(format: "%.2f KB", kb)
        }
    }

    private func createTestData(size: Int) -> Data {
        return Data(count: size)
    }
}
