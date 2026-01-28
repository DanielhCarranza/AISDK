//
//  AnthropicMessageStreamingDeltaBlock.swift
//
//  Created by Lou Zell on 10/7/24.
//

import Foundation

/// Delta types for streaming content blocks
public enum AnthropicStreamingDelta: Codable, Sendable, Equatable {
    /// Incremental text content
    case textDelta(text: String)

    /// Incremental thinking content
    case thinkingDelta(thinking: String)

    /// Thinking block signature (comes just before content_block_stop)
    case signatureDelta(signature: String)

    /// Partial JSON for tool use arguments
    case inputJsonDelta(partialJson: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case thinking
        case signature
        case partialJson = "partial_json"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text_delta":
            let text = try container.decode(String.self, forKey: .text)
            self = .textDelta(text: text)
        case "thinking_delta":
            let thinking = try container.decode(String.self, forKey: .thinking)
            self = .thinkingDelta(thinking: thinking)
        case "signature_delta":
            let signature = try container.decode(String.self, forKey: .signature)
            self = .signatureDelta(signature: signature)
        case "input_json_delta":
            let json = try container.decode(String.self, forKey: .partialJson)
            self = .inputJsonDelta(partialJson: json)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown delta type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .textDelta(let text):
            try container.encode("text_delta", forKey: .type)
            try container.encode(text, forKey: .text)
        case .thinkingDelta(let thinking):
            try container.encode("thinking_delta", forKey: .type)
            try container.encode(thinking, forKey: .thinking)
        case .signatureDelta(let signature):
            try container.encode("signature_delta", forKey: .type)
            try container.encode(signature, forKey: .signature)
        case .inputJsonDelta(let json):
            try container.encode("input_json_delta", forKey: .type)
            try container.encode(json, forKey: .partialJson)
        }
    }
}

/// Content block types that can start in streaming
public enum AnthropicStreamingContentBlockType: String, Codable, Sendable {
    case text
    case thinking
    case toolUse = "tool_use"
}

/// Event data for content_block_start
public struct AnthropicContentBlockStart: Codable, Sendable {
    public let index: Int
    public let contentBlock: ContentBlockStartData

    // Note: CodingKeys not needed - using shared decoder with convertFromSnakeCase

    public struct ContentBlockStartData: Codable, Sendable {
        public let type: String
        public let id: String?
        public let name: String?
        public let text: String?
        public let thinking: String?
    }
}

/// Event data for content_block_delta
public struct AnthropicContentBlockDelta: Codable, Sendable {
    public let index: Int
    public let delta: AnthropicStreamingDelta
}

/// Event data for content_block_stop
public struct AnthropicContentBlockStop: Codable, Sendable {
    public let index: Int
}

// MARK: - SSE Line Helpers

extension AnthropicContentBlockStart {
    static func from(line: String) -> Self? {
        guard line.hasPrefix(#"data: {"type":"content_block_start""#) else {
            return nil
        }
        guard let chunkJSON = line.dropFirst(6).data(using: .utf8),
              let chunk = try? AnthropicHTTPClient.decoder.decode(Self.self, from: chunkJSON) else
        {
            return nil
        }
        return chunk
    }
}

extension AnthropicContentBlockDelta {
    static func from(line: String) -> Self? {
        guard line.hasPrefix(#"data: {"type":"content_block_delta""#) else {
            return nil
        }
        guard let chunkJSON = line.dropFirst(6).data(using: .utf8),
              let chunk = try? AnthropicHTTPClient.decoder.decode(Self.self, from: chunkJSON) else
        {
            return nil
        }
        return chunk
    }
}

extension AnthropicContentBlockStop {
    static func from(line: String) -> Self? {
        guard line.hasPrefix(#"data: {"type":"content_block_stop""#) else {
            return nil
        }
        guard let chunkJSON = line.dropFirst(6).data(using: .utf8),
              let chunk = try? AnthropicHTTPClient.decoder.decode(Self.self, from: chunkJSON) else
        {
            return nil
        }
        return chunk
    }
}
