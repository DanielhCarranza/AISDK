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
    }

    @Test("Init with budget only")
    func testInitWithBudget() {
        let config = AIReasoningConfig(budgetTokens: 2048)
        #expect(config.effort == nil)
        #expect(config.budgetTokens == 2048)
    }

    @Test("Init with effort and budget")
    func testInitWithEffortAndBudget() {
        let config = AIReasoningConfig(effort: .medium, budgetTokens: 4096)
        #expect(config.effort == .medium)
        #expect(config.budgetTokens == 4096)
    }

    @Test("Factory creates effort config")
    func testEffortFactory() {
        let config = AIReasoningConfig.effort(.low)
        #expect(config.effort == .low)
        #expect(config.budgetTokens == nil)
    }

    @Test("Codable round-trip")
    func testCodableRoundTrip() throws {
        let original = AIReasoningConfig(effort: .high, budgetTokens: 2048)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIReasoningConfig.self, from: data)
        #expect(decoded == original)
    }
}
