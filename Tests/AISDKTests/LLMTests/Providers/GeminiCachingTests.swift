//
//  GeminiCachingTests.swift
//  AISDKTests
//
//  Tests for Gemini caching support
//

import Foundation
import Testing
@testable import AISDK

@Suite("Gemini Caching Tests")
struct GeminiCachingTests {
    @Test("createGeminiRequest passes through cachedContent")
    func testCachedContentPassthrough() {
        let message = AIInputMessage(role: .user, content: [.text("Hello")])
        let request = createGeminiRequest(
            messages: [message],
            cachedContent: "cachedContents/abc123"
        )

        #expect(request.cachedContent == "cachedContents/abc123")
    }

    @Test("createGeminiRequest defaults cachedContent to nil")
    func testCachedContentDefaultsNil() {
        let message = AIInputMessage(role: .user, content: [.text("Hello")])
        let request = createGeminiRequest(messages: [message])

        #expect(request.cachedContent == nil)
    }

    @Test("Single message helper passes through cachedContent")
    func testSingleMessageCachedContent() {
        let message = AIInputMessage(role: .user, content: [.text("Hello")])
        let request = createGeminiRequest(
            message: message,
            cachedContent: "cachedContents/xyz789"
        )

        #expect(request.cachedContent == "cachedContents/xyz789")
    }

    @Test("Single message helper defaults cachedContent to nil")
    func testSingleMessageDefaultsNil() {
        let message = AIInputMessage(role: .user, content: [.text("Hello")])
        let request = createGeminiRequest(message: message)

        #expect(request.cachedContent == nil)
    }
}
