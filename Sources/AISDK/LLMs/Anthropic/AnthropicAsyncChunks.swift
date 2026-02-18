//
//  AnthropicAsyncChunks.swift
//
//
//  Created by Lou Zell on 10/7/24.
//

import Foundation

/// Iterate the streaming chunks using the following pattern:
///
///     let stream = try await anthropicService.streamingMessageRequest(...)
///
///     for try await chunk in stream {
///         switch chunk {
///         case .text(let text):
///             print(text)
///         case .toolUse(name: let toolName, input: let toolInput):
///             print("Claude wants to call tool \(toolName) with input \(toolInput)")
///         case .thinkingDelta(let delta):
///             print("Thinking: \(delta)")
///         case .thinkingComplete(let block):
///             print("Thinking complete: \(block.thinking)")
///         default:
///             break
///         }
///     }
public struct AnthropicAsyncChunks: AsyncSequence {
    public typealias Element = AnthropicMessageStreamingChunk
    private let asyncLines: AsyncLineSequence<URLSession.AsyncBytes>

    internal init(asyncLines: AsyncLineSequence<URLSession.AsyncBytes>) {
        self.asyncLines = asyncLines
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var asyncBytesIterator: AsyncLineSequence<URLSession.AsyncBytes>.AsyncIterator

        private struct ToolCallState {
            var name: String
            var arguments: String = ""
        }

        private struct ThinkingBlockState {
            var thinking: String = ""
            var signature: String = ""
        }

        private var currentToolState: ToolCallState?
        private var currentThinkingState: ThinkingBlockState?
        private var currentBlockType: AnthropicStreamingContentBlockType?

        init(asyncBytesIterator: AsyncLineSequence<URLSession.AsyncBytes>.AsyncIterator) {
            self.asyncBytesIterator = asyncBytesIterator
        }

        /// This buffers up any tool calls that are part of the streaming response before
        /// emitting the next streaming chunk. Tool calls are not emitted to the
        /// caller as partial values.
        mutating public func next() async throws -> AnthropicMessageStreamingChunk? {
            while true {
                guard let value = try await self.asyncBytesIterator.next() else {
                    return nil
                }

                if let blockStart = AnthropicContentBlockStart.from(line: value) {
                    currentBlockType = AnthropicStreamingContentBlockType(rawValue: blockStart.contentBlock.type)

                    switch currentBlockType {
                    case .thinking:
                        currentThinkingState = ThinkingBlockState()
                    case .toolUse:
                        currentToolState = ToolCallState(
                            name: blockStart.contentBlock.name ?? ""
                        )
                    case .text, .none:
                        break
                    }
                    continue
                }

                if let blockDelta = AnthropicContentBlockDelta.from(line: value) {
                    switch blockDelta.delta {
                    case .textDelta(let text):
                        return .text(text)
                    case .thinkingDelta(let thinking):
                        if currentThinkingState == nil {
                            currentThinkingState = ThinkingBlockState()
                        }
                        currentThinkingState?.thinking += thinking
                        return .thinkingDelta(thinking)
                    case .signatureDelta(let signature):
                        if currentThinkingState == nil {
                            currentThinkingState = ThinkingBlockState()
                        }
                        currentThinkingState?.signature = signature
                    case .inputJsonDelta(let json):
                        if currentToolState == nil {
                            currentToolState = ToolCallState(name: "")
                        }
                        currentToolState?.arguments += json
                    }
                    continue
                }

                if let _ = AnthropicContentBlockStop.from(line: value) {
                    switch currentBlockType {
                    case .thinking:
                        if let state = currentThinkingState {
                            let block = AnthropicThinkingBlock(
                                thinking: state.thinking,
                                signature: state.signature
                            )
                            currentThinkingState = nil
                            currentBlockType = nil
                            return .thinkingComplete(block)
                        }
                    case .toolUse:
                        if let state = currentToolState {
                            let input = try JSONDecoder()
                                .decode([String: AIProxyJSONValue].self, from: state.arguments.data(using: .utf8) ?? Data())
                                .mapValues { $0.anyValue }
                            currentToolState = nil
                            currentBlockType = nil
                            return .toolUse(name: state.name, input: input)
                        }
                    case .text, .none:
                        currentBlockType = nil
                        break
                    }
                    continue
                }

                if let messageDelta = AnthropicMessageDeltaEvent.from(line: value) {
                    let payload = AnthropicMessageDelta(
                        stopReason: messageDelta.delta.stopReason,
                        stopSequence: messageDelta.delta.stopSequence,
                        usage: messageDelta.usage
                    )
                    return .messageDelta(payload)
                }

                if AnthropicMessageStopEvent.from(line: value) != nil {
                    return .done
                }
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(asyncBytesIterator: asyncLines.makeAsyncIterator())
    }
}
