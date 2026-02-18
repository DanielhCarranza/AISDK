//
//  TestReporter.swift
//  AISDKTestRunner
//
//  Comprehensive test reporting with timing, pass/fail tracking, and formatted output
//

import Foundation

/// Test result tracking and reporting utility
public final class TestReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [TestResult] = []
    private var currentSuite: String?
    private let startTime: Date
    public let verbose: Bool

    public struct TestResult: Sendable {
        let suite: String
        let name: String
        let passed: Bool
        let duration: TimeInterval
        let message: String?
        let timestamp: Date
    }

    public init(verbose: Bool = false) {
        self.verbose = verbose
        self.startTime = Date()
    }

    // MARK: - Recording Results

    public func recordSuccess(_ suite: String, _ name: String, duration: TimeInterval = 0, message: String? = nil) {
        let result = TestResult(
            suite: suite,
            name: name,
            passed: true,
            duration: duration,
            message: message,
            timestamp: Date()
        )
        lock.lock()
        results.append(result)
        lock.unlock()

        printResult(result)
    }

    public func recordFailure(_ suite: String, _ name: String, duration: TimeInterval = 0, message: String? = nil) {
        let result = TestResult(
            suite: suite,
            name: name,
            passed: false,
            duration: duration,
            message: message,
            timestamp: Date()
        )
        lock.lock()
        results.append(result)
        lock.unlock()

        printResult(result)
    }

    public func recordSkipped(_ suite: String, _ name: String, reason: String) {
        print("   [SKIP] \(name)")
        if verbose {
            print("          Reason: \(reason)")
        }
    }

    // MARK: - Section Management

    public func printSection(_ title: String) {
        currentSuite = title
        print("\n" + String(repeating: "=", count: 60))
        print("  \(title)")
        print(String(repeating: "=", count: 60) + "\n")
    }

    public func printSubsection(_ title: String) {
        print("\n" + String(repeating: "-", count: 40))
        print("  \(title)")
        print(String(repeating: "-", count: 40))
    }

    // MARK: - Output

    private func printResult(_ result: TestResult) {
        let icon = result.passed ? "[PASS]" : "[FAIL]"
        let durationStr = result.duration > 0 ? String(format: " (%.2fs)", result.duration) : ""
        print("   \(icon) \(result.name)\(durationStr)")

        if verbose || !result.passed, let message = result.message {
            print("          \(message)")
        }
    }

    public func log(_ message: String) {
        if verbose {
            print("   [LOG] \(message)")
        }
    }

    public func debug(_ message: String) {
        if verbose {
            print("   [DEBUG] \(message)")
        }
    }

    // MARK: - Summary

    public func printSummary() {
        lock.lock()
        let allResults = results
        lock.unlock()

        let passed = allResults.filter { $0.passed }.count
        let failed = allResults.filter { !$0.passed }.count
        let total = allResults.count
        let totalDuration = Date().timeIntervalSince(startTime)

        print("\n" + String(repeating: "=", count: 60))
        print("  TEST SUMMARY")
        print(String(repeating: "=", count: 60))

        // Group by suite
        let suites = Dictionary(grouping: allResults) { $0.suite }
        for (suite, suiteResults) in suites.sorted(by: { $0.key < $1.key }) {
            let suitePassed = suiteResults.filter { $0.passed }.count
            let suiteFailed = suiteResults.filter { !$0.passed }.count
            let icon = suiteFailed == 0 ? "[OK]" : "[!!]"
            print("   \(icon) \(suite): \(suitePassed)/\(suiteResults.count) passed")
        }

        print(String(repeating: "-", count: 60))
        print("   Total: \(passed)/\(total) passed, \(failed) failed")
        print(String(format: "   Duration: %.2f seconds", totalDuration))

        if failed > 0 {
            print("\n   Failed Tests:")
            for result in allResults.where({ !$0.passed }) {
                print("     - [\(result.suite)] \(result.name)")
                if let message = result.message {
                    print("       \(message)")
                }
            }
        }

        let finalStatus = failed == 0 ? "ALL TESTS PASSED" : "TESTS FAILED"
        print("\n   \(finalStatus)")
        print(String(repeating: "=", count: 60) + "\n")
    }

    // MARK: - Statistics

    public var passedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return results.filter { $0.passed }.count
    }

    public var failedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return results.filter { !$0.passed }.count
    }

    public var totalCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return results.count
    }
}

// Extension for filtering
extension Array {
    func `where`(_ predicate: (Element) -> Bool) -> [Element] {
        filter(predicate)
    }
}

// MARK: - Test Timing Helper

public struct TestTimer {
    private let startTime: Date

    public init() {
        self.startTime = Date()
    }

    public var elapsed: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}

// MARK: - Test Suite Protocol

public protocol TestSuiteProtocol {
    var reporter: TestReporter { get }
    var verbose: Bool { get }
    func run() async throws
}

extension TestSuiteProtocol {
    public func withTimer(_ name: String, _ suite: String, _ block: () async throws -> Void) async {
        let timer = TestTimer()
        do {
            try await block()
            reporter.recordSuccess(suite, name, duration: timer.elapsed)
        } catch {
            reporter.recordFailure(suite, name, duration: timer.elapsed, message: "\(error)")
        }
    }

    public func requireEnvVar(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            return nil
        }
        return value
    }
}
