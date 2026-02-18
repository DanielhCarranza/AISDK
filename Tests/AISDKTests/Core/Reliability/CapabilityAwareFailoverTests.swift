//
//  CapabilityAwareFailoverTests.swift
//  AISDK
//
//  Tests for CapabilityAwareFailover, FailoverPolicy, and TokenEstimator.
//

import Foundation
import Testing
import XCTest
@testable import AISDK

// MARK: - TokenEstimator Tests

@Suite("TokenEstimator Tests")
struct TokenEstimatorTests {
    @Test("Default estimator uses 4 chars per token")
    func testDefaultCharsPerToken() {
        let estimator = TokenEstimator.default
        #expect(estimator.charsPerToken == 4)
    }

    @Test("Conservative estimator uses 3 chars per token")
    func testConservativeCharsPerToken() {
        let estimator = TokenEstimator.conservative
        #expect(estimator.charsPerToken == 3)
    }

    @Test("Custom chars per token is clamped to minimum of 1")
    func testMinimumCharsPerToken() {
        let estimator = TokenEstimator(charsPerToken: 0)
        #expect(estimator.charsPerToken == 1)
    }

    @Test("Estimate string tokens correctly")
    func testEstimateString() {
        let estimator = TokenEstimator.default  // 4 chars per token

        #expect(estimator.estimate("") == 0)
        #expect(estimator.estimate("Hi") == 1)  // 2 chars -> 1 token
        #expect(estimator.estimate("Hello") == 2)  // 5 chars -> 2 tokens
        #expect(estimator.estimate("Hello World!") == 3)  // 12 chars -> 3 tokens
    }

    @Test("Estimate request tokens sums all messages")
    func testEstimateRequest() {
        let estimator = TokenEstimator.default
        let request = AITextRequest(
            messages: [
                .user("Hello"),  // ~2 tokens + 4 overhead
                .assistant("Hi there!")  // ~3 tokens + 4 overhead
            ]
        )

        let tokens = estimator.estimate(request)
        #expect(tokens > 0)
        // Should include message overhead
        #expect(tokens >= 5)
    }

    @Test("Estimate message with image adds token overhead")
    func testEstimateMessageWithImage() {
        let estimator = TokenEstimator.default
        let message = AIMessage(
            role: .user,
            content: .parts([
                .text("Check this image:"),
                .imageURL("https://example.com/image.png")
            ])
        )

        let tokens = estimator.estimateMessage(message)
        // Text + image (200 default) + overhead
        #expect(tokens >= 200)
    }
}

// MARK: - FailoverPolicy Configuration Tests

@Suite("FailoverPolicy Configuration Tests")
struct FailoverPolicyConfigurationTests {
    @Test("Default policy has expected values")
    func testDefaultValues() {
        let policy = FailoverPolicy.default

        #expect(policy.maxCostMultiplier == 5.0)
        #expect(policy.requireCapabilityMatch == true)
        #expect(policy.minimumContextWindow == 0)
        #expect(policy.allowLowerTier == true)
        #expect(policy.requiredCapabilities.isEmpty)
    }

    @Test("Strict policy has stricter values")
    func testStrictPolicy() {
        let policy = FailoverPolicy.strict

        #expect(policy.maxCostMultiplier == 2.0)
        #expect(policy.requireCapabilityMatch == true)
        #expect(policy.allowLowerTier == false)
    }

    @Test("Lenient policy has relaxed values")
    func testLenientPolicy() {
        let policy = FailoverPolicy.lenient

        #expect(policy.maxCostMultiplier == 10.0)
        #expect(policy.requireCapabilityMatch == false)
        #expect(policy.allowLowerTier == true)
    }

    @Test("Cost conscious policy prioritizes budget")
    func testCostConsciousPolicy() {
        let policy = FailoverPolicy.costConscious

        #expect(policy.maxCostMultiplier == 1.5)
    }

    @Test("Max cost multiplier is clamped to minimum of 1")
    func testMinimumCostMultiplier() {
        let policy = FailoverPolicy(maxCostMultiplier: 0.5)
        #expect(policy.maxCostMultiplier == 1.0)
    }

    @Test("Minimum context window is clamped to non-negative")
    func testMinimumContextWindowClamped() {
        let policy = FailoverPolicy(minimumContextWindow: -100)
        #expect(policy.minimumContextWindow == 0)
    }
}

// MARK: - FailoverPolicy Modifier Tests

@Suite("FailoverPolicy Modifier Tests")
struct FailoverPolicyModifierTests {
    @Test("withMaxCostMultiplier creates modified copy")
    func testWithMaxCostMultiplier() {
        let original = FailoverPolicy.default
        let modified = original.withMaxCostMultiplier(2.0)

        #expect(modified.maxCostMultiplier == 2.0)
        #expect(modified.requireCapabilityMatch == original.requireCapabilityMatch)
    }

    @Test("withRequireCapabilityMatch creates modified copy")
    func testWithRequireCapabilityMatch() {
        let original = FailoverPolicy.default
        let modified = original.withRequireCapabilityMatch(false)

        #expect(modified.requireCapabilityMatch == false)
        #expect(modified.maxCostMultiplier == original.maxCostMultiplier)
    }

    @Test("withRequiredCapabilities creates modified copy")
    func testWithRequiredCapabilities() {
        let original = FailoverPolicy.default
        let modified = original.withRequiredCapabilities([.vision, .tools])

        #expect(modified.requiredCapabilities.contains(.vision))
        #expect(modified.requiredCapabilities.contains(.tools))
    }

    @Test("withMinimumContextWindow creates modified copy")
    func testWithMinimumContextWindow() {
        let original = FailoverPolicy.default
        let modified = original.withMinimumContextWindow(8000)

        #expect(modified.minimumContextWindow == 8000)
    }

    @Test("Modifiers can be chained")
    func testChainedModifiers() {
        let policy = FailoverPolicy.default
            .withMaxCostMultiplier(3.0)
            .withRequireCapabilityMatch(false)
            .withMinimumContextWindow(4000)

        #expect(policy.maxCostMultiplier == 3.0)
        #expect(policy.requireCapabilityMatch == false)
        #expect(policy.minimumContextWindow == 4000)
    }
}

// MARK: - FailoverPolicy Allowlist Tests

@Suite("FailoverPolicy Allowlist Tests")
struct FailoverPolicyAllowlistTests {
    @Test("isProviderAllowed returns true when allowedProviders is nil")
    func testAllowedWhenNoRestrictions() {
        let policy = FailoverPolicy.default
        let request = AITextRequest(
            messages: [.user("Test")],
            allowedProviders: nil
        )

        #expect(policy.isProviderAllowed(request: request, providerId: "any-provider"))
    }

    @Test("isProviderAllowed returns true when provider is in allowlist")
    func testAllowedWhenInAllowlist() {
        let policy = FailoverPolicy.default
        let request = AITextRequest(
            messages: [.user("Test")],
            allowedProviders: ["openai", "anthropic"]
        )

        #expect(policy.isProviderAllowed(request: request, providerId: "openai"))
        #expect(policy.isProviderAllowed(request: request, providerId: "anthropic"))
    }

    @Test("isProviderAllowed returns false when provider not in allowlist")
    func testNotAllowedWhenNotInAllowlist() {
        let policy = FailoverPolicy.default
        let request = AITextRequest(
            messages: [.user("Test")],
            allowedProviders: ["openai"]
        )

        #expect(!policy.isProviderAllowed(request: request, providerId: "google"))
        #expect(!policy.isProviderAllowed(request: request, providerId: "anthropic"))
    }

    @Test("isProviderAllowed returns false when allowlist is empty")
    func testNotAllowedWhenEmptyAllowlist() {
        let policy = FailoverPolicy.default
        let request = AITextRequest(
            messages: [.user("Test")],
            allowedProviders: []
        )

        #expect(!policy.isProviderAllowed(request: request, providerId: "any-provider"))
    }
}

// MARK: - FailoverPolicy Equatable Tests

@Suite("FailoverPolicy Equatable Tests")
struct FailoverPolicyEquatableTests {
    @Test("Same policies are equal")
    func testSamePoliciesEqual() {
        let policy1 = FailoverPolicy.default
        let policy2 = FailoverPolicy.default

        #expect(policy1 == policy2)
    }

    @Test("Different policies are not equal")
    func testDifferentPoliciesNotEqual() {
        let policy1 = FailoverPolicy.default
        let policy2 = FailoverPolicy.strict

        #expect(policy1 != policy2)
    }

    @Test("Custom policies with same values are equal")
    func testCustomPoliciesEqual() {
        let policy1 = FailoverPolicy(
            maxCostMultiplier: 3.0,
            requireCapabilityMatch: false,
            minimumContextWindow: 1000
        )
        let policy2 = FailoverPolicy(
            maxCostMultiplier: 3.0,
            requireCapabilityMatch: false,
            minimumContextWindow: 1000
        )

        #expect(policy1 == policy2)
    }
}

// MARK: - FailoverCompatibilityResult Tests

@Suite("FailoverCompatibilityResult Tests")
struct FailoverCompatibilityResultTests {
    @Test("compatible result has correct values")
    func testCompatibleResult() {
        let result = FailoverCompatibilityResult.compatible

        #expect(result.isCompatible == true)
        #expect(result.reason == nil)
    }

    @Test("notInAllowlist result has correct values")
    func testNotInAllowlistResult() {
        let result = FailoverCompatibilityResult.notInAllowlist

        #expect(result.isCompatible == false)
        #expect(result.reason == .providerNotAllowed)
    }

    @Test("missingCapabilities result captures missing caps")
    func testMissingCapabilitiesResult() {
        let result = FailoverCompatibilityResult.missingCapabilities([.vision, .tools])

        #expect(result.isCompatible == false)
        if case .missingCapabilities(let caps) = result.reason {
            #expect(caps.contains(.vision))
            #expect(caps.contains(.tools))
        } else {
            #expect(Bool(false), "Expected missingCapabilities reason")
        }
    }

    @Test("costTooHigh result captures multiplier")
    func testCostTooHighResult() {
        let result = FailoverCompatibilityResult.costTooHigh(multiplier: 7.5)

        #expect(result.isCompatible == false)
        if case .costExceedsLimit(let mult) = result.reason {
            #expect(mult == 7.5)
        } else {
            #expect(Bool(false), "Expected costExceedsLimit reason")
        }
    }

    @Test("contextTooSmall result captures values")
    func testContextTooSmallResult() {
        let result = FailoverCompatibilityResult.contextTooSmall(required: 10000, available: 4096)

        #expect(result.isCompatible == false)
        if case .insufficientContext(let req, let avail) = result.reason {
            #expect(req == 10000)
            #expect(avail == 4096)
        } else {
            #expect(Bool(false), "Expected insufficientContext reason")
        }
    }
}

// MARK: - IncompatibilityReason Tests

@Suite("IncompatibilityReason Tests")
struct IncompatibilityReasonTests {
    @Test("IncompatibilityReason is Equatable")
    func testEquatable() {
        #expect(IncompatibilityReason.providerNotAllowed == IncompatibilityReason.providerNotAllowed)
        #expect(IncompatibilityReason.tierTooLow == IncompatibilityReason.tierTooLow)
        #expect(IncompatibilityReason.costExceedsLimit(5.0) == IncompatibilityReason.costExceedsLimit(5.0))
        #expect(IncompatibilityReason.costExceedsLimit(5.0) != IncompatibilityReason.costExceedsLimit(10.0))
        #expect(IncompatibilityReason.providerNotAllowed != IncompatibilityReason.tierTooLow)
    }
}

// MARK: - TokenEstimator Equatable Tests

@Suite("TokenEstimator Equatable Tests")
struct TokenEstimatorEquatableTests {
    @Test("Same estimators are equal")
    func testSameEstimatorsEqual() {
        let est1 = TokenEstimator.default
        let est2 = TokenEstimator.default

        #expect(est1 == est2)
    }

    @Test("Different estimators are not equal")
    func testDifferentEstimatorsNotEqual() {
        let est1 = TokenEstimator.default
        let est2 = TokenEstimator.conservative

        #expect(est1 != est2)
    }
}
