//
//  AIReasoningConfigTests.swift
//  AISDKTests
//
//  Tests for AIReasoningConfig
//

import Foundation
import Testing
@testable import AISDK

@Suite("AIReasoningConfig Tests")
struct AIReasoningConfigTests {
    @Test("Init with effort only")
    func testInitWithEffort() {
        let config = AIReasoningConfig(effort: .high)
        #expect(config.effort == .high)
        #expect(config.budgetTokens == nil)
        #expect(config.summary == nil)
    }

    @Test("Init with budget only")
    func testInitWithBudget() {
        let config = AIReasoningConfig(budgetTokens: 2048)
        #expect(config.effort == nil)
        #expect(config.budgetTokens == 2048)
        #expect(config.summary == nil)
    }

    @Test("Init with effort and budget")
    func testInitWithEffortAndBudget() {
        let config = AIReasoningConfig(effort: .medium, budgetTokens: 4096)
        #expect(config.effort == .medium)
        #expect(config.budgetTokens == 4096)
        #expect(config.summary == nil)
    }

    @Test("Init with effort and summary")
    func testInitWithEffortAndSummary() {
        let config = AIReasoningConfig(effort: .high, summary: .concise)
        #expect(config.effort == .high)
        #expect(config.summary == .concise)
        #expect(config.budgetTokens == nil)
    }

    @Test("Init with all fields")
    func testInitWithAllFields() {
        let config = AIReasoningConfig(effort: .medium, budgetTokens: 4096, summary: .detailed)
        #expect(config.effort == .medium)
        #expect(config.budgetTokens == 4096)
        #expect(config.summary == .detailed)
    }

    @Test("Factory creates effort config")
    func testEffortFactory() {
        let config = AIReasoningConfig.effort(.low)
        #expect(config.effort == .low)
        #expect(config.budgetTokens == nil)
        #expect(config.summary == nil)
    }

    @Test("Factory creates effort+summary config")
    func testEffortSummaryFactory() {
        let config = AIReasoningConfig.effort(.medium, summary: .detailed)
        #expect(config.effort == .medium)
        #expect(config.summary == .detailed)
        #expect(config.budgetTokens == nil)
    }

    @Test("Codable round-trip")
    func testCodableRoundTrip() throws {
        let original = AIReasoningConfig(effort: .high, budgetTokens: 2048)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIReasoningConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable round-trip with summary")
    func testCodableRoundTripWithSummary() throws {
        let original = AIReasoningConfig(effort: .medium, summary: .auto)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIReasoningConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test("AIReasoningSummary raw values")
    func testSummaryRawValues() {
        #expect(AIReasoningConfig.AIReasoningSummary.auto.rawValue == "auto")
        #expect(AIReasoningConfig.AIReasoningSummary.concise.rawValue == "concise")
        #expect(AIReasoningConfig.AIReasoningSummary.detailed.rawValue == "detailed")
    }

    @Test("AIReasoningSummary Codable round-trip")
    func testSummaryCodableRoundTrip() throws {
        for summary in [AIReasoningConfig.AIReasoningSummary.auto, .concise, .detailed] {
            let data = try JSONEncoder().encode(summary)
            let decoded = try JSONDecoder().decode(AIReasoningConfig.AIReasoningSummary.self, from: data)
            #expect(decoded == summary)
        }
    }
}
