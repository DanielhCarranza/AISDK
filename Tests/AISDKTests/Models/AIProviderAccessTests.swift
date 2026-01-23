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
