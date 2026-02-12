//
//  AnthropicCachingTests.swift
//  AISDKTests
//
//  Tests for Anthropic prompt caching support
//

import Foundation
import Testing
@testable import AISDK

@Suite("AnthropicCacheControl Tests")
struct AnthropicCacheControlTests {
    @Test("Default type is ephemeral")
    func testDefaultType() throws {
        let cc = AnthropicCacheControl()
        let data = try JSONEncoder().encode(cc)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "ephemeral")
        #expect(json["ttl"] == nil)
    }

    @Test("Encodes ttl when present")
    func testEncodesWithTTL() throws {
        let cc = AnthropicCacheControl(type: "ephemeral", ttl: "1h")
        let data = try JSONEncoder().encode(cc)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "ephemeral")
        #expect(json["ttl"] as? String == "1h")
    }

    @Test("Omits ttl when nil")
    func testOmitsTTLWhenNil() throws {
        let cc = AnthropicCacheControl(type: "ephemeral")
        let data = try JSONEncoder().encode(cc)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["ttl"] == nil)
    }
}

@Suite("AnthropicSystemBlock Tests")
struct AnthropicSystemBlockTests {
    @Test("Encodes correctly without cache_control")
    func testEncodeWithoutCacheControl() throws {
        let block = AnthropicSystemBlock(text: "You are a helpful assistant.")
        let data = try JSONEncoder().encode(block)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "text")
        #expect(json["text"] as? String == "You are a helpful assistant.")
        #expect(json["cache_control"] == nil)
    }

    @Test("Encodes correctly with cache_control")
    func testEncodeWithCacheControl() throws {
        let block = AnthropicSystemBlock(
            text: "You are a helpful assistant.",
            cacheControl: AnthropicCacheControl()
        )
        let data = try JSONEncoder().encode(block)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "text")
        #expect(json["text"] as? String == "You are a helpful assistant.")
        let cacheControlJSON = json["cache_control"] as? [String: Any]
        #expect(cacheControlJSON != nil)
        #expect(cacheControlJSON?["type"] as? String == "ephemeral")
    }

    @Test("Encodes cache_control with ttl")
    func testEncodeWithCacheControlTTL() throws {
        let block = AnthropicSystemBlock(
            text: "System prompt",
            cacheControl: AnthropicCacheControl(type: "ephemeral", ttl: "1h")
        )
        let data = try JSONEncoder().encode(block)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let cacheControlJSON = json["cache_control"] as? [String: Any]
        #expect(cacheControlJSON?["type"] as? String == "ephemeral")
        #expect(cacheControlJSON?["ttl"] as? String == "1h")
    }
}

@Suite("AnthropicMessageRequestBody Caching Tests")
struct AnthropicMessageRequestBodyCachingTests {
    @Test("Encodes system as string when systemBlocks is nil")
    func testEncodesSystemAsString() throws {
        let body = AnthropicMessageRequestBody(
            maxTokens: 1000,
            messages: [AnthropicInputMessage(content: [.text("Hello")], role: .user)],
            model: "claude-sonnet-4-5-20250929",
            system: "You are helpful."
        )

        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["system"] as? String == "You are helpful.")
    }

    @Test("Encodes system as array when systemBlocks is set")
    func testEncodesSystemAsArray() throws {
        let blocks = [
            AnthropicSystemBlock(text: "You are helpful.", cacheControl: AnthropicCacheControl())
        ]
        let body = AnthropicMessageRequestBody(
            maxTokens: 1000,
            messages: [AnthropicInputMessage(content: [.text("Hello")], role: .user)],
            model: "claude-sonnet-4-5-20250929",
            system: "This should be ignored",
            systemBlocks: blocks
        )

        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // systemBlocks should take precedence
        let systemArray = json["system"] as? [[String: Any]]
        #expect(systemArray != nil)
        #expect(systemArray?.count == 1)
        #expect(systemArray?.first?["type"] as? String == "text")
        #expect(systemArray?.first?["text"] as? String == "You are helpful.")
    }

    @Test("Omits system when both system and systemBlocks are nil")
    func testOmitsSystemWhenNil() throws {
        let body = AnthropicMessageRequestBody(
            maxTokens: 1000,
            messages: [AnthropicInputMessage(content: [.text("Hello")], role: .user)],
            model: "claude-sonnet-4-5-20250929"
        )

        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["system"] == nil)
    }
}

@Suite("AnthropicTool Cache Control Tests")
struct AnthropicToolCacheControlTests {
    @Test("Encodes tool without cache_control")
    func testEncodeWithoutCacheControl() throws {
        let tool = AnthropicTool(
            name: "get_weather",
            description: "Gets the weather",
            inputSchema: AnthropicToolSchema(properties: [:])
        )

        let data = try JSONEncoder().encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["name"] as? String == "get_weather")
        #expect(json["description"] as? String == "Gets the weather")
        #expect(json["cache_control"] == nil)
    }

    @Test("Encodes tool with cache_control")
    func testEncodeWithCacheControl() throws {
        let tool = AnthropicTool(
            name: "get_weather",
            description: "Gets the weather",
            inputSchema: AnthropicToolSchema(properties: [:]),
            cacheControl: AnthropicCacheControl()
        )

        let data = try JSONEncoder().encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["name"] as? String == "get_weather")
        let cacheControlJSON = json["cache_control"] as? [String: Any]
        #expect(cacheControlJSON != nil)
        #expect(cacheControlJSON?["type"] as? String == "ephemeral")
    }
}
