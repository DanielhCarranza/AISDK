//
//  LiveTestHelpersTests.swift
//  AISDKTests
//
//  Unit tests for the live-test provider health classifier.
//  These tests verify classification logic without hitting any network —
//  they feed synthetic ProviderError values into LiveTestHelpers.classify
//  and assert the returned LiveTestFailureKind.
//

import Foundation
import XCTest
@testable import AISDK

final class LiveTestHelpersTests: XCTestCase {

    override func setUp() {
        super.setUp()
        LiveProviderHealth.shared.reset()
    }

    override func tearDown() {
        LiveProviderHealth.shared.reset()
        super.tearDown()
    }

    // MARK: - classify: OpenAI shapes

    func test_classify_openAI_insufficientQuotaInAuthMessage_returnsQuotaExhausted() {
        let error = ProviderError.authenticationFailed("You exceeded your current quota, please check your plan and billing details.")
        let kind = LiveTestHelpers.classify(error, provider: .openAI)
        guard case .quotaExhausted = kind else {
            XCTFail("Expected .quotaExhausted, got \(String(describing: kind))")
            return
        }
    }

    func test_classify_openAI_genericAuthFailure_returnsAuthInvalid() {
        let error = ProviderError.authenticationFailed("Incorrect API key provided.")
        let kind = LiveTestHelpers.classify(error, provider: .openAI)
        guard case .authInvalid = kind else {
            XCTFail("Expected .authInvalid, got \(String(describing: kind))")
            return
        }
    }

    func test_classify_openAI_rateLimited_returnsRateLimited() {
        let error = ProviderError.rateLimited(retryAfter: 30)
        let kind = LiveTestHelpers.classify(error, provider: .openAI)
        guard case .rateLimited = kind else {
            XCTFail("Expected .rateLimited, got \(String(describing: kind))")
            return
        }
    }

    // MARK: - classify: Anthropic shapes

    func test_classify_anthropic_server529_returnsServerOverloaded() {
        let error = ProviderError.serverError(statusCode: 529, message: "Overloaded")
        let kind = LiveTestHelpers.classify(error, provider: .anthropic)
        guard case .serverOverloaded = kind else {
            XCTFail("Expected .serverOverloaded, got \(String(describing: kind))")
            return
        }
    }

    // MARK: - classify: OpenRouter shapes

    func test_classify_openRouter_unknown402_returnsPaymentRequired() {
        // OpenRouterClient maps 402 to .unknown("HTTP 402: ...")
        let error = ProviderError.unknown("HTTP 402: Payment required, please add credits")
        let kind = LiveTestHelpers.classify(error, provider: .openRouter)
        guard case .paymentRequired = kind else {
            XCTFail("Expected .paymentRequired, got \(String(describing: kind))")
            return
        }
    }

    func test_classify_modelNotFound_returnsModelUnavailable() {
        let error = ProviderError.modelNotFound("Resource not found")
        let kind = LiveTestHelpers.classify(error, provider: .openRouter)
        guard case .modelUnavailable = kind else {
            XCTFail("Expected .modelUnavailable, got \(String(describing: kind))")
            return
        }
    }

    // MARK: - classify: Gemini shapes

    func test_classify_gemini_permissionDeniedInProviderSpecific_returnsPermissionDenied() {
        let error = ProviderError.providerSpecific(code: "PERMISSION_DENIED", message: "The caller does not have permission")
        let kind = LiveTestHelpers.classify(error, provider: .gemini)
        guard case .permissionDenied = kind else {
            XCTFail("Expected .permissionDenied, got \(String(describing: kind))")
            return
        }
    }

    func test_classify_gemini_resourceExhausted_returnsQuotaExhausted() {
        let error = ProviderError.providerSpecific(code: "RESOURCE_EXHAUSTED", message: "Quota exceeded for requests")
        let kind = LiveTestHelpers.classify(error, provider: .gemini)
        guard case .quotaExhausted = kind else {
            XCTFail("Expected .quotaExhausted, got \(String(describing: kind))")
            return
        }
    }

    // MARK: - classify: non-health errors

    func test_classify_invalidRequest_returnsNil() {
        let error = ProviderError.invalidRequest("messages.0.role must be one of...")
        XCTAssertNil(LiveTestHelpers.classify(error, provider: .openAI),
                     "Bad request shapes should not be classified as provider health issues")
    }

    func test_classify_serverError500_returnsNil() {
        let error = ProviderError.serverError(statusCode: 500, message: "Internal server error")
        XCTAssertNil(LiveTestHelpers.classify(error, provider: .openAI),
                     "Plain 5xx errors should bubble up as real failures, not skips")
    }

    // MARK: - persistence behavior

    func test_persistentFailure_marksProviderBroken() {
        XCTAssertNil(LiveProviderHealth.shared.brokenKind(.openAI))
        LiveProviderHealth.shared.markBroken(.openAI, kind: .quotaExhausted(message: "test"))
        XCTAssertNotNil(LiveProviderHealth.shared.brokenKind(.openAI))
    }

    func test_skipIfProviderBroken_throwsWhenMarked() {
        LiveProviderHealth.shared.markBroken(.anthropic, kind: .authInvalid(message: "test"))
        XCTAssertThrowsError(try LiveTestHelpers.skipIfProviderBroken(.anthropic)) { error in
            // XCTSkip's String(describing:) doesn't expose the message, but
            // any thrown error from this path proves the guard fired.
            XCTAssertTrue(error is XCTSkip,
                          "Expected XCTSkip, got \(type(of: error)): \(error)")
        }
    }

    func test_skipIfProviderBroken_noopWhenNotMarked() {
        XCTAssertNoThrow(try LiveTestHelpers.skipIfProviderBroken(.gemini))
    }

    // MARK: - handle: end-to-end behavior

    func test_handle_quotaError_throwsSkipAndMarksBroken() async {
        let error = ProviderError.authenticationFailed("insufficient_quota: you exceeded your current quota")
        do {
            try LiveTestHelpers.handle(error, provider: .openAI)
            XCTFail("handle should always throw")
        } catch {
            // Expected — should have thrown XCTSkip (or rethrown; we only
            // care that the provider got marked).
            XCTAssertNotNil(LiveProviderHealth.shared.brokenKind(.openAI),
                            "Expected OpenAI to be marked broken after quota error")
        }
    }

    func test_handle_unclassifiedError_rethrowsOriginal() async {
        // A ProviderError.invalidRequest is not a health issue — handle should
        // re-throw it so the test fails for the real reason.
        let original = ProviderError.invalidRequest("bad params")
        do {
            try LiveTestHelpers.handle(original, provider: .openAI)
            XCTFail("handle should always throw")
        } catch let error as ProviderError {
            // Should have rethrown the original ProviderError, not an XCTSkip
            guard case .invalidRequest = error else {
                XCTFail("Expected invalidRequest passthrough, got \(error)")
                return
            }
            XCTAssertNil(LiveProviderHealth.shared.brokenKind(.openAI),
                         "Unclassified errors must not mark the provider broken")
        } catch {
            XCTFail("Expected ProviderError, got \(error)")
        }
    }
}
