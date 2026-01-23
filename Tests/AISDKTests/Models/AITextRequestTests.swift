//
//  AITextRequestTests.swift
//  AISDK
//
//  Tests for AITextRequest, DataSensitivity, and StreamBufferPolicy
//

import Foundation
import Testing
@testable import AISDK

@Suite("AITextRequest Tests")
struct AITextRequestTests {
    // MARK: - Basic Initialization

    @Test("Creates request with minimal parameters")
    func testMinimalInit() {
        let request = AITextRequest(messages: [.user("Hello")])

        #expect(request.messages.count == 1)
        #expect(request.messages[0].role == .user)
        #expect(request.model == nil)
        #expect(request.maxTokens == nil)
        #expect(request.temperature == nil)
        #expect(request.sensitivity == .standard)
        #expect(request.allowedProviders == nil)
        #expect(request.bufferPolicy == nil)
    }

    @Test("Creates request with all parameters")
    func testFullInit() {
        let messages = [AIMessage.user("Hello"), AIMessage.assistant("Hi there")]
        let allowedProviders: Set<String> = ["openai", "anthropic"]
        let bufferPolicy = StreamBufferPolicy(capacity: 500, overflowBehavior: .dropOldest)

        let request = AITextRequest(
            messages: messages,
            model: "gpt-4",
            maxTokens: 1000,
            temperature: 0.7,
            topP: 0.9,
            stop: ["END"],
            tools: nil,
            toolChoice: nil,
            responseFormat: nil,
            allowedProviders: allowedProviders,
            sensitivity: .phi,
            bufferPolicy: bufferPolicy,
            metadata: ["requestId": "test-123"]
        )

        #expect(request.messages.count == 2)
        #expect(request.model == "gpt-4")
        #expect(request.maxTokens == 1000)
        #expect(request.temperature == 0.7)
        #expect(request.topP == 0.9)
        #expect(request.stop == ["END"])
        #expect(request.sensitivity == .phi)
        #expect(request.allowedProviders == allowedProviders)
        #expect(request.bufferPolicy?.capacity == 500)
        #expect(request.metadata?["requestId"] == "test-123")
    }

    // MARK: - PHI Protection

    @Test("canUseProvider returns true when allowedProviders is nil")
    func testCanUseProviderWithNilAllowed() {
        let request = AITextRequest(messages: [.user("Hello")])

        #expect(request.canUseProvider("openai") == true)
        #expect(request.canUseProvider("anthropic") == true)
        #expect(request.canUseProvider("any-provider") == true)
    }

    @Test("canUseProvider respects allowedProviders")
    func testCanUseProviderWithRestrictions() {
        let request = AITextRequest(
            messages: [.user("Hello")],
            allowedProviders: ["openai", "anthropic"]
        )

        #expect(request.canUseProvider("openai") == true)
        #expect(request.canUseProvider("anthropic") == true)
        #expect(request.canUseProvider("google") == false)
        #expect(request.canUseProvider("unknown") == false)
    }

    // MARK: - Request Transformations

    @Test("withSensitivity creates new request with updated sensitivity")
    func testWithSensitivity() {
        let original = AITextRequest(
            messages: [.user("Test")],
            model: "gpt-4",
            sensitivity: .standard
        )

        let updated = original.withSensitivity(.phi)

        #expect(updated.sensitivity == .phi)
        #expect(updated.model == "gpt-4")
        #expect(updated.messages.count == 1)
        #expect(original.sensitivity == .standard) // Original unchanged
    }

    @Test("withAllowedProviders creates new request with provider restrictions")
    func testWithAllowedProviders() {
        let original = AITextRequest(
            messages: [.user("Test")],
            sensitivity: .phi
        )

        let providers: Set<String> = ["openai"]
        let updated = original.withAllowedProviders(providers)

        #expect(updated.allowedProviders == providers)
        #expect(updated.sensitivity == .phi)
        #expect(original.allowedProviders == nil) // Original unchanged
    }

    @Test("withBufferPolicy creates new request with buffer policy")
    func testWithBufferPolicy() {
        let original = AITextRequest(messages: [.user("Test")])
        let policy = StreamBufferPolicy(capacity: 2000, overflowBehavior: .dropNewest)

        let updated = original.withBufferPolicy(policy)

        #expect(updated.bufferPolicy?.capacity == 2000)
        #expect(updated.bufferPolicy?.overflowBehavior == .dropNewest)
        #expect(original.bufferPolicy == nil) // Original unchanged
    }
}

@Suite("DataSensitivity Tests")
struct DataSensitivityTests {
    @Test("All sensitivity levels exist")
    func testAllLevels() {
        let standard = DataSensitivity.standard
        let sensitive = DataSensitivity.sensitive
        let phi = DataSensitivity.phi

        #expect(standard.rawValue == "standard")
        #expect(sensitive.rawValue == "sensitive")
        #expect(phi.rawValue == "phi")
    }

    @Test("DataSensitivity is Codable")
    func testCodable() throws {
        let original = DataSensitivity.phi

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DataSensitivity.self, from: data)

        #expect(decoded == original)
    }

    @Test("DataSensitivity is Equatable")
    func testEquatable() {
        #expect(DataSensitivity.standard == DataSensitivity.standard)
        #expect(DataSensitivity.phi != DataSensitivity.standard)
    }
}

@Suite("StreamBufferPolicy Tests")
struct StreamBufferPolicyTests {
    @Test("Default bounded policy has correct capacity")
    func testDefaultBounded() {
        let policy = StreamBufferPolicy.bounded

        #expect(policy.capacity == 1000)
        #expect(policy.overflowBehavior == .suspendProducer)
    }

    @Test("Unbounded policy uses max capacity")
    func testUnbounded() {
        let policy = StreamBufferPolicy.unbounded

        #expect(policy.capacity == Int.max)
    }

    @Test("Custom policy with dropOldest")
    func testDropOldest() {
        let policy = StreamBufferPolicy(capacity: 500, overflowBehavior: .dropOldest)

        #expect(policy.capacity == 500)
        #expect(policy.overflowBehavior == .dropOldest)
    }

    @Test("Custom policy with dropNewest")
    func testDropNewest() {
        let policy = StreamBufferPolicy(capacity: 100, overflowBehavior: .dropNewest)

        #expect(policy.capacity == 100)
        #expect(policy.overflowBehavior == .dropNewest)
    }

    @Test("StreamBufferPolicy is Equatable")
    func testEquatable() {
        let policy1 = StreamBufferPolicy(capacity: 1000, overflowBehavior: .suspendProducer)
        let policy2 = StreamBufferPolicy(capacity: 1000, overflowBehavior: .suspendProducer)
        let policy3 = StreamBufferPolicy(capacity: 500, overflowBehavior: .suspendProducer)

        #expect(policy1 == policy2)
        #expect(policy1 != policy3)
    }
}
