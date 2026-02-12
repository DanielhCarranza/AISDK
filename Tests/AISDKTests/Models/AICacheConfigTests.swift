//
//  AICacheConfigTests.swift
//  AISDKTests
//
//  Tests for AICacheConfig
//

import Foundation
import Testing
@testable import AISDK

@Suite("AICacheConfig Tests")
struct AICacheConfigTests {
    @Test("Default init enables caching")
    func testDefaultInit() {
        let config = AICacheConfig()
        #expect(config.enabled == true)
        #expect(config.cachedContentId == nil)
        #expect(config.retention == nil)
    }

    @Test("Init with all parameters")
    func testFullInit() {
        let config = AICacheConfig(enabled: true, cachedContentId: "cachedContents/abc123", retention: .extended)
        #expect(config.enabled == true)
        #expect(config.cachedContentId == "cachedContents/abc123")
        #expect(config.retention == .extended)
    }

    @Test("enabled factory creates simple config")
    func testEnabledFactory() {
        let config = AICacheConfig.enabled
        #expect(config.enabled == true)
        #expect(config.cachedContentId == nil)
        #expect(config.retention == nil)
    }

    @Test("extended factory creates config with extended retention")
    func testExtendedFactory() {
        let config = AICacheConfig.extended()
        #expect(config.enabled == true)
        #expect(config.retention == .extended)
        #expect(config.cachedContentId == nil)
    }

    @Test("withCachedContent factory creates config with Gemini cache ID")
    func testWithCachedContentFactory() {
        let config = AICacheConfig.withCachedContent("cachedContents/xyz789")
        #expect(config.enabled == true)
        #expect(config.cachedContentId == "cachedContents/xyz789")
    }

    @Test("Codable round-trip")
    func testCodableRoundTrip() throws {
        let original = AICacheConfig(enabled: true, cachedContentId: "cachedContents/test", retention: .extended)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AICacheConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable round-trip with nil fields")
    func testCodableRoundTripMinimal() throws {
        let original = AICacheConfig.enabled
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AICacheConfig.self, from: data)
        #expect(decoded == original)
    }

    @Test("Equatable works correctly")
    func testEquatable() {
        let a = AICacheConfig(enabled: true, retention: .standard)
        let b = AICacheConfig(enabled: true, retention: .standard)
        let c = AICacheConfig(enabled: true, retention: .extended)

        #expect(a == b)
        #expect(a != c)
    }

    @Test("CacheRetention raw values")
    func testRetentionRawValues() {
        #expect(AICacheConfig.CacheRetention.standard.rawValue == "standard")
        #expect(AICacheConfig.CacheRetention.extended.rawValue == "extended")
    }
}
