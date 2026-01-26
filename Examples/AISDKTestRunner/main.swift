//
//  main.swift
//  AISDKTestRunner
//
//  Comprehensive test runner for AISDK 2.0 modernization
//  Supports real model testing, stress testing, and provider validation
//

import Foundation
import AISDK

// MARK: - CLI Options

enum TestMode: String, CaseIterable {
    case all
    case reliability
    case generativeUI = "generative-ui"
    case stress
    case litellm
    case providers
    case reasoning
    case help
}

struct TestOptions {
    let mode: TestMode
    let provider: String?
    let model: String?
    let verbose: Bool
    let reasoningMode: ReasoningMode
    let concurrency: Int
}

// MARK: - Main Execution

func runMain() async {
    printBanner()
    loadEnvironmentVariables()

    let options = parseOptions()

    if options.mode == .help {
        printUsage()
        return
    }

    let reporter = TestReporter(verbose: options.verbose)
    let reasoningDisplay = ReasoningDisplay(mode: options.reasoningMode)

    do {
        switch options.mode {
        case .all:
            try await runAllTests(options: options, reporter: reporter, reasoningDisplay: reasoningDisplay)
        case .reliability:
            try await runReliabilityTests(options: options, reporter: reporter)
        case .generativeUI:
            try await runGenerativeUITests(options: options, reporter: reporter)
        case .stress:
            try await runStressTests(options: options, reporter: reporter)
        case .litellm:
            try await runLiteLLMTests(options: options, reporter: reporter)
        case .providers:
            try await runProviderTests(options: options, reporter: reporter, reasoningDisplay: reasoningDisplay)
        case .reasoning:
            try await runReasoningDemo(options: options, reasoningDisplay: reasoningDisplay)
        case .help:
            printUsage()
        }

        reporter.printSummary()
    } catch {
        reporter.recordFailure("TestRunner", "Execution failed: \(error)")
        reporter.printSummary()
    }
}

// MARK: - Option Parsing

func parseOptions() -> TestOptions {
    let args = CommandLine.arguments
    var mode: TestMode = .all
    var provider: String?
    var model: String?
    var verbose = false
    var reasoningMode: ReasoningMode = .inline
    var concurrency = 10

    var index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--mode", "-m":
            if index + 1 < args.count, let parsed = TestMode(rawValue: args[index + 1]) {
                mode = parsed
                index += 1
            }
        case "--provider":
            if index + 1 < args.count {
                provider = args[index + 1]
                index += 1
            }
        case "--model":
            if index + 1 < args.count {
                model = args[index + 1]
                index += 1
            }
        case "--verbose", "-v":
            verbose = true
        case "--reasoning":
            if index + 1 < args.count, let parsed = ReasoningMode(rawValue: args[index + 1]) {
                reasoningMode = parsed
                index += 1
            }
        case "--concurrency":
            if index + 1 < args.count, let parsed = Int(args[index + 1]) {
                concurrency = max(1, min(100, parsed))
                index += 1
            }
        case "--help", "-h":
            mode = .help
        default:
            break
        }
        index += 1
    }

    return TestOptions(
        mode: mode,
        provider: provider,
        model: model,
        verbose: verbose,
        reasoningMode: reasoningMode,
        concurrency: concurrency
    )
}

// MARK: - Banner & Help

func printBanner() {
    print("""

    ╔══════════════════════════════════════════════════════════════════╗
    ║                                                                  ║
    ║   █████╗ ██╗███████╗██████╗ ██╗  ██╗  ████████╗███████╗███████╗ ║
    ║  ██╔══██╗██║██╔════╝██╔══██╗██║ ██╔╝  ╚══██╔══╝██╔════╝██╔════╝ ║
    ║  ███████║██║███████╗██║  ██║█████╔╝      ██║   █████╗  ███████╗ ║
    ║  ██╔══██║██║╚════██║██║  ██║██╔═██╗      ██║   ██╔══╝  ╚════██║ ║
    ║  ██║  ██║██║███████║██████╔╝██║  ██╗     ██║   ███████╗███████║ ║
    ║  ╚═╝  ╚═╝╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝     ╚═╝   ╚══════╝╚══════╝ ║
    ║                                                                  ║
    ║  AISDK 2.0 Test Runner - Real Model Testing & Validation         ║
    ╚══════════════════════════════════════════════════════════════════╝

    """)
}

func printUsage() {
    print("""
    Usage: swift run AISDKTestRunner [options]

    Test Modes:
      --mode all           Run all test suites (default)
      --mode reliability   Test circuit breaker, failover, retry policies
      --mode generative-ui Test UITree generation and streaming
      --mode stress        Run stress and memory tests
      --mode litellm       Test LiteLLM proxy integration
      --mode providers     Test provider adapters (OpenAI, Anthropic, Gemini)
      --mode reasoning     Demo reasoning/thinking display
      --mode help          Show this help

    Provider Options:
      --provider NAME      Filter to specific provider (openai, anthropic, gemini)
      --model MODEL_ID     Use specific model (e.g., gemini-3.0-flash-preview)

    Display Options:
      --reasoning MODE     Reasoning display mode: inline, collapsed, split
      --verbose, -v        Show detailed output
      --concurrency N      Number of concurrent requests for stress tests (default: 10)

    Environment Variables:
      OPENAI_API_KEY       Required for OpenAI tests
      ANTHROPIC_API_KEY    Required for Anthropic tests
      GOOGLE_API_KEY       Required for Gemini tests
      OPENROUTER_API_KEY   Required for OpenRouter tests
      LITELLM_BASE_URL     LiteLLM proxy URL (default: http://localhost:8000)
      LITELLM_API_KEY      LiteLLM API key

    Examples:
      swift run AISDKTestRunner --mode all --verbose
      swift run AISDKTestRunner --mode providers --provider gemini --model gemini-3.0-flash-preview
      swift run AISDKTestRunner --mode stress --concurrency 50
      swift run AISDKTestRunner --mode reasoning --reasoning inline

    Supported Models:
      OpenAI:     gpt-5-nano, gpt-4o-mini, gpt-4o
      Anthropic:  claude-sonnet-4, claude-3-5-sonnet-20241022
      Gemini:     gemini-3.0-flash-preview, gemini-2.0-flash
    """)
}

// MARK: - Environment

func loadEnvironmentVariables() {
    let paths = [".env", "../.env", "../../.env"]
    for path in paths {
        if let content = try? String(contentsOfFile: path) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count >= 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
                        setenv(key, value, 0)
                    }
                }
            }
            print("Loaded environment from \(path)")
            return
        }
    }
}

// MARK: - Test Execution

func runAllTests(options: TestOptions, reporter: TestReporter, reasoningDisplay: ReasoningDisplay) async throws {
    reporter.printSection("Running All Test Suites")

    try await runReliabilityTests(options: options, reporter: reporter)
    try await runProviderTests(options: options, reporter: reporter, reasoningDisplay: reasoningDisplay)
    try await runGenerativeUITests(options: options, reporter: reporter)
    try await runStressTests(options: options, reporter: reporter)
    try await runLiteLLMTests(options: options, reporter: reporter)
}

func runReliabilityTests(options: TestOptions, reporter: TestReporter) async throws {
    reporter.printSection("Reliability Layer Tests")
    let suite = ReliabilityTestSuite(reporter: reporter, verbose: options.verbose)
    try await suite.run()
}

func runGenerativeUITests(options: TestOptions, reporter: TestReporter) async throws {
    reporter.printSection("Generative UI Tests")
    let suite = GenerativeUITestSuite(reporter: reporter, verbose: options.verbose)
    try await suite.run()
}

func runStressTests(options: TestOptions, reporter: TestReporter) async throws {
    reporter.printSection("Stress & Memory Tests")
    let suite = StressTestSuite(
        reporter: reporter,
        verbose: options.verbose,
        concurrency: options.concurrency,
        model: options.model
    )
    try await suite.run()
}

func runLiteLLMTests(options: TestOptions, reporter: TestReporter) async throws {
    reporter.printSection("LiteLLM Integration Tests")
    let suite = LiteLLMTestSuite(reporter: reporter, verbose: options.verbose)
    try await suite.run()
}

func runProviderTests(options: TestOptions, reporter: TestReporter, reasoningDisplay: ReasoningDisplay) async throws {
    reporter.printSection("Provider Adapter Tests")
    let suite = ProviderTestSuite(
        reporter: reporter,
        verbose: options.verbose,
        provider: options.provider,
        model: options.model,
        reasoningDisplay: reasoningDisplay
    )
    try await suite.run()
}

func runReasoningDemo(options: TestOptions, reasoningDisplay: ReasoningDisplay) async throws {
    print("\nReasoning Display Demo")
    print(String(repeating: "=", count: 60))

    // Simulate reasoning output
    let thinkingSteps = [
        "Let me analyze this problem step by step...",
        "First, I need to understand the requirements...",
        "Breaking down the components...",
        "Considering edge cases...",
        "Formulating the solution..."
    ]

    print("\nSimulating reasoning output with mode: \(options.reasoningMode)")
    print(String(repeating: "-", count: 40))

    for step in thinkingSteps {
        reasoningDisplay.displayThinking(step)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
    }

    reasoningDisplay.finishThinking()
    print("\nFinal answer would appear here after reasoning completes.")
}

// MARK: - Entry Point

// Run the async main function
let semaphore = DispatchSemaphore(value: 0)
Task {
    await runMain()
    semaphore.signal()
}
semaphore.wait()
