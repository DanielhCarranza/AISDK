//
//  CLIIntegrationTests.swift
//  AISDKTests
//
//  Integration tests for AISDKCLI
//

import Foundation
import XCTest

final class CLIIntegrationTests: XCTestCase {

    func testCLIHelp() throws {
        let result = try CLITestRunner.run(["--help"], timeout: 60)
        XCTAssertTrue(result.succeeded, "CLI help should succeed: \(result.errorOutput)")
        XCTAssertTrue(result.output.contains("USAGE"), "Help output should contain usage information")
    }

    func testCLIBasicChat() throws {
        let config = try requireProviderConfig()

        let input = "Say exactly BANANA\n/exit\n"
        let result = try CLITestRunner.run([
            "--provider", config.provider,
            "--model", config.model,
            "--max-tokens", "50",
            "--temperature", "0"
        ], input: input, timeout: 120)

        XCTAssertTrue(result.succeeded, "CLI should exit successfully: \(result.errorOutput)")
        let outputUpper = result.output.uppercased()
        XCTAssertTrue(outputUpper.contains("BANANA"), "Expected response to contain BANANA")
    }

    func testCLIMultiTurn() throws {
        let config = try requireProviderConfig()

        let input = "Remember the word PINEAPPLE\nWhat word did I tell you?\n/exit\n"
        let result = try CLITestRunner.run([
            "--provider", config.provider,
            "--model", config.model,
            "--max-tokens", "80",
            "--temperature", "0"
        ], input: input, timeout: 180)

        XCTAssertTrue(result.succeeded, "CLI should exit successfully: \(result.errorOutput)")
        let promptCount = result.output.components(separatedBy: "You>").count
        XCTAssertTrue(promptCount >= 3, "Expected multiple prompts for multi-turn input")
    }

    // MARK: - Helpers

    private func requireProviderConfig() throws -> (provider: String, model: String) {
        if let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty {
            let model = ProcessInfo.processInfo.environment["AISDK_CLI_MODEL"] ?? "openai/gpt-4o-mini"
            return (provider: "openrouter", model: model)
        }

        if let baseURL = ProcessInfo.processInfo.environment["LITELLM_BASE_URL"], !baseURL.isEmpty {
            let model = ProcessInfo.processInfo.environment["AISDK_LITELLM_MODEL"] ?? "gpt-4o-mini"
            return (provider: "litellm", model: model)
        }

        throw XCTSkip("OPENROUTER_API_KEY or LITELLM_BASE_URL not set")
    }
}
