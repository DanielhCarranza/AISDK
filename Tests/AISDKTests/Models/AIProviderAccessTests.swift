//
//  AIProviderAccessTests.swift
//  AISDK
//
//  Tests for AIProviderAccessError and provider validation
//

import Foundation
import Testing
@testable import AISDK

@Suite("AIProviderAccessError Tests")
struct AIProviderAccessErrorTests {
    @Test("providerNotAllowed error has correct description")
    func testProviderNotAllowedDescription() {
        let error = AIProviderAccessError.providerNotAllowed(
            provider: "google",
            allowedProviders: ["openai", "anthropic"]
        )

        let description = error.detailedDescription
        #expect(description.contains("google"))
        #expect(description.contains("not allowed"))
        #expect(description.contains("anthropic") || description.contains("openai"))
    }

    @Test("sensitiveDataRequiresAllowlist error for sensitive data")
    func testSensitiveDataError() {
        let error = AIProviderAccessError.sensitiveDataRequiresAllowlist(
            sensitivity: .sensitive
        )

        let description = error.detailedDescription
        #expect(description.contains("sensitive"))
        #expect(description.contains("allowlist"))
    }

    @Test("sensitiveDataRequiresAllowlist error for PHI")
    func testPHIDataError() {
        let error = AIProviderAccessError.sensitiveDataRequiresAllowlist(
            sensitivity: .phi
        )

        let description = error.detailedDescription
        #expect(description.contains("phi"))
        #expect(description.contains("allowlist"))
    }

    @Test("AIProviderAccessError is Equatable")
    func testEquatable() {
        let error1 = AIProviderAccessError.providerNotAllowed(
            provider: "google",
            allowedProviders: ["openai"]
        )
        let error2 = AIProviderAccessError.providerNotAllowed(
            provider: "google",
            allowedProviders: ["openai"]
        )
        let error3 = AIProviderAccessError.providerNotAllowed(
            provider: "azure",
            allowedProviders: ["openai"]
        )

        #expect(error1 == error2)
        #expect(error1 != error3)
    }
}

@Suite("Provider Validation Integration Tests")
struct ProviderValidationIntegrationTests {
    @Test("Standard sensitivity allows any provider")
    func testStandardSensitivity() {
        let request = AITextRequest(
            messages: [.user("Hello")],
            sensitivity: .standard
        )

        // Standard data should allow any provider even without allowlist
        #expect(request.canUseProvider("openai"))
        #expect(request.canUseProvider("anthropic"))
        #expect(request.canUseProvider("random-provider"))
    }

    @Test("Sensitive request with allowlist restricts providers")
    func testSensitiveWithAllowlist() {
        let request = AITextRequest(
            messages: [.user("Sensitive data")],
            allowedProviders: ["openai", "anthropic"],
            sensitivity: .sensitive
        )

        #expect(request.canUseProvider("openai"))
        #expect(request.canUseProvider("anthropic"))
        #expect(!request.canUseProvider("google"))
        #expect(!request.canUseProvider("azure"))
    }

    @Test("PHI request with allowlist restricts providers")
    func testPHIWithAllowlist() {
        let request = AITextRequest(
            messages: [.user("PHI data")],
            allowedProviders: ["openai"],
            sensitivity: .phi
        )

        #expect(request.canUseProvider("openai"))
        #expect(!request.canUseProvider("anthropic"))
        #expect(!request.canUseProvider("google"))
    }

    @Test("Empty allowlist blocks all providers")
    func testEmptyAllowlist() {
        let request = AITextRequest(
            messages: [.user("Test")],
            allowedProviders: []
        )

        #expect(!request.canUseProvider("openai"))
        #expect(!request.canUseProvider("anthropic"))
        #expect(!request.canUseProvider("any"))
    }
}

@Suite("AILanguageModelAdapter Provider Validation Tests")
struct AILanguageModelAdapterProviderValidationTests {
    @Test("Adapter rejects request when provider not in allowlist")
    func testAdapterRejectsDisallowedProvider() async throws {
        let mockLLM = MockLLMProvider()
        let adapter = AILanguageModelAdapter(
            llm: mockLLM,
            provider: "google",  // Not in the allowlist
            modelId: "gemini"
        )

        let request = AITextRequest(
            messages: [.user("Test")],
            allowedProviders: ["openai", "anthropic"],  // google not allowed
            sensitivity: .standard
        )

        do {
            _ = try await adapter.generateText(request: request)
            #expect(Bool(false), "Expected AIProviderAccessError.providerNotAllowed")
        } catch let error as AIProviderAccessError {
            if case .providerNotAllowed(let provider, let allowed) = error {
                #expect(provider == "google")
                #expect(allowed.contains("openai"))
                #expect(!allowed.contains("google"))
            } else {
                #expect(Bool(false), "Expected providerNotAllowed error")
            }
        }
    }

    @Test("Adapter allows request when provider is in allowlist")
    func testAdapterAllowsAllowedProvider() async throws {
        let mockLLM = MockLLMProvider()
        let adapter = AILanguageModelAdapter(
            llm: mockLLM,
            provider: "openai",  // In the allowlist
            modelId: "gpt-4"
        )

        let request = AITextRequest(
            messages: [.user("Test")],
            allowedProviders: ["openai", "anthropic"],
            sensitivity: .standard
        )

        // Should not throw
        let result = try await adapter.generateText(request: request)
        #expect(result.text.contains("Mock response"))
    }

    @Test("Adapter rejects sensitive request without allowlist")
    func testAdapterRejectsSensitiveWithoutAllowlist() async throws {
        let mockLLM = MockLLMProvider()
        let adapter = AILanguageModelAdapter(
            llm: mockLLM,
            provider: "openai",
            modelId: "gpt-4"
        )

        let request = AITextRequest(
            messages: [.user("Sensitive data")],
            allowedProviders: nil,  // No allowlist
            sensitivity: .sensitive  // Requires allowlist
        )

        do {
            _ = try await adapter.generateText(request: request)
            #expect(Bool(false), "Expected AIProviderAccessError.sensitiveDataRequiresAllowlist")
        } catch let error as AIProviderAccessError {
            if case .sensitiveDataRequiresAllowlist(let sensitivity) = error {
                #expect(sensitivity == .sensitive)
            } else {
                #expect(Bool(false), "Expected sensitiveDataRequiresAllowlist error")
            }
        }
    }

    @Test("Adapter rejects PHI request without allowlist")
    func testAdapterRejectsPHIWithoutAllowlist() async throws {
        let mockLLM = MockLLMProvider()
        let adapter = AILanguageModelAdapter(
            llm: mockLLM,
            provider: "openai",
            modelId: "gpt-4"
        )

        let request = AITextRequest(
            messages: [.user("PHI data")],
            allowedProviders: nil,  // No allowlist
            sensitivity: .phi  // PHI requires allowlist
        )

        do {
            _ = try await adapter.generateText(request: request)
            #expect(Bool(false), "Expected AIProviderAccessError.sensitiveDataRequiresAllowlist")
        } catch let error as AIProviderAccessError {
            if case .sensitiveDataRequiresAllowlist(let sensitivity) = error {
                #expect(sensitivity == .phi)
            } else {
                #expect(Bool(false), "Expected sensitiveDataRequiresAllowlist error")
            }
        }
    }

    @Test("Adapter allows standard request without allowlist")
    func testAdapterAllowsStandardWithoutAllowlist() async throws {
        let mockLLM = MockLLMProvider()
        let adapter = AILanguageModelAdapter(
            llm: mockLLM,
            provider: "openai",
            modelId: "gpt-4"
        )

        let request = AITextRequest(
            messages: [.user("Regular data")],
            allowedProviders: nil,  // No restrictions
            sensitivity: .standard  // Standard doesn't require allowlist
        )

        // Should not throw
        let result = try await adapter.generateText(request: request)
        #expect(result.text.contains("Mock response"))
    }

    @Test("Streaming also validates provider access")
    func testStreamingValidatesProviderAccess() async throws {
        let mockLLM = MockLLMProvider()
        let adapter = AILanguageModelAdapter(
            llm: mockLLM,
            provider: "azure",  // Not in allowlist
            modelId: "gpt-4"
        )

        let request = AITextRequest(
            messages: [.user("Test")],
            allowedProviders: ["openai"],  // azure not allowed
            sensitivity: .standard
        )

        let stream = adapter.streamText(request: request)
        var errorEventCaught = false
        var throwingErrorCaught: AIProviderAccessError?

        do {
            for try await event in stream {
                // The adapter may yield an error event before throwing
                if case .error(let error) = event {
                    if let accessError = error as? AIProviderAccessError {
                        throwingErrorCaught = accessError
                    }
                    errorEventCaught = true
                }
            }
        } catch let error as AIProviderAccessError {
            throwingErrorCaught = error
        }

        // Either an error event was yielded or an error was thrown
        #expect(errorEventCaught || throwingErrorCaught != nil)
        if let accessError = throwingErrorCaught {
            if case .providerNotAllowed(let provider, _) = accessError {
                #expect(provider == "azure")
            }
        }
    }
}

// MARK: - AIObjectRequest Provider Validation Tests

/// Test model for object generation
fileprivate struct TestProfile: Codable, Sendable, JSONSchemaModel {
    @Field(description: "User's name")
    var name: String = ""

    init() {}
}

@Suite("AIObjectRequest Provider Validation Tests")
struct AIObjectRequestProviderValidationTests {
    @Test("AIObjectRequest.canUseProvider with nil allowedProviders allows any provider")
    func testCanUseProviderWithNil() {
        let schema = TestProfile.schema()
        let request = AIObjectRequest<TestProfile>(
            messages: [.user("Create a profile")],
            schema: schema,
            sensitivity: .standard
        )

        #expect(request.canUseProvider("openai"))
        #expect(request.canUseProvider("anthropic"))
        #expect(request.canUseProvider("any-provider"))
    }

    @Test("AIObjectRequest.canUseProvider respects allowedProviders")
    func testCanUseProviderWithAllowlist() {
        let schema = TestProfile.schema()
        let request = AIObjectRequest<TestProfile>(
            messages: [.user("Create a profile")],
            schema: schema,
            allowedProviders: ["openai", "anthropic"],
            sensitivity: .sensitive
        )

        #expect(request.canUseProvider("openai"))
        #expect(request.canUseProvider("anthropic"))
        #expect(!request.canUseProvider("google"))
        #expect(!request.canUseProvider("azure"))
    }

    @Test("AIObjectRequest PHI sensitivity with allowlist")
    func testPHIWithAllowlist() {
        let schema = TestProfile.schema()
        let request = AIObjectRequest<TestProfile>(
            messages: [.user("PHI profile")],
            schema: schema,
            allowedProviders: ["openai"],
            sensitivity: .phi
        )

        #expect(request.canUseProvider("openai"))
        #expect(!request.canUseProvider("anthropic"))
        #expect(request.sensitivity == .phi)
    }

    @Test("AIObjectRequest transformation methods preserve sensitivity")
    func testTransformationPreservesSensitivity() {
        let schema = TestProfile.schema()
        let original = AIObjectRequest<TestProfile>(
            messages: [.user("Create profile")],
            schema: schema,
            sensitivity: .phi
        )

        let withProviders = original.withAllowedProviders(["openai"])

        #expect(withProviders.sensitivity == .phi)
        #expect(withProviders.allowedProviders == ["openai"])
    }
}
