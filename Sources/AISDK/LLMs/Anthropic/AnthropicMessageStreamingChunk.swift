//
//  AnthropicMessageStreamingChunk.swift
//
//  Created by Lou Zell on 10/7/24.
//

import Foundation

public enum AnthropicMessageStreamingChunk: @unchecked Sendable {
    /// The `String` argument is the chat completion response text "delta", meaning the new bit
    /// of text that just became available. It is not the full message.
    case text(String)

    /// Incremental thinking content (for UI updates)
    case thinkingDelta(String)

    /// Complete thinking block with signature
    case thinkingComplete(AnthropicThinkingBlock)

    /// The name of the tool that Claude wants to call, and a buffered input to the function.
    /// The input argument is not a "delta". Internally to this lib, we accumulate the tool
    /// call deltas and map them to `[String: Any]` once all tool call deltas have been
    /// received.
    case toolUse(name: String, input: [String: Any])

    /// LegacyMessage metadata (stop reason, usage)
    case messageDelta(AnthropicMessageDelta)

    /// Stream completed
    case done
}

/// LegacyMessage-level delta metadata in streaming responses
public struct AnthropicMessageDelta: Codable, Sendable, Equatable {
    public let stopReason: String?
    public let stopSequence: String?
    public let usage: AnthropicMessageUsage?

    public init(stopReason: String?, stopSequence: String?, usage: AnthropicMessageUsage?) {
        self.stopReason = stopReason
        self.stopSequence = stopSequence
        self.usage = usage
    }
}

internal struct AnthropicMessageDeltaEvent: Decodable {
    let delta: Delta
    let usage: AnthropicMessageUsage?

    struct Delta: Decodable {
        let stopReason: String?
        let stopSequence: String?
        // Note: CodingKeys not needed - using shared decoder with convertFromSnakeCase
    }
    // Note: CodingKeys not needed - using shared decoder with convertFromSnakeCase
}

internal struct AnthropicMessageStopEvent: Decodable {
    let type: String
}

extension AnthropicMessageDeltaEvent {
    static func from(line: String) -> Self? {
        guard line.hasPrefix(#"data: {"type":"message_delta""#) else {
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

extension AnthropicMessageStopEvent {
    static func from(line: String) -> Self? {
        guard line.hasPrefix(#"data: {"type":"message_stop""#) else {
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
