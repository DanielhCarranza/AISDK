//
//  StreamingChatTests.swift
//  AISDKTests
//
//  Created for AISDK Testing
//

import XCTest
@testable import AISDK

final class StreamingChatTests: XCTestCase {
    
    var mockProvider: MockLLMProvider!
    
    override func setUp() {
        super.setUp()
        mockProvider = MockLLMProvider()
    }
    
    override func tearDown() {
        mockProvider = nil
        super.tearDown()
    }
    
    // MARK: - Basic Streaming Tests
    
    func testBasicStreamingChat() async throws {
        // Given
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [.user(content: .text("Tell me a story"))],
            stream: true
        )
        
        var receivedChunks: [ChatCompletionChunk] = []
        var receivedContent = ""
        
        // When
        for try await chunk in try await mockProvider.sendChatCompletionStream(request: request) {
            receivedChunks.append(chunk)
            if let content = chunk.choices.first?.delta.content {
                receivedContent += content
            }
        }
        
        // Then
        XCTAssertEqual(mockProvider.requestCount, 1)
        XCTAssertNotNil(mockProvider.lastRequest)
        XCTAssertGreaterThan(receivedChunks.count, 0)
        XCTAssertFalse(receivedContent.isEmpty)
        
        // Check that the last chunk has a finish reason
        XCTAssertEqual(receivedChunks.last?.choices.first?.finishReason, "stop")
    }
    
    func testStreamingWithCustomChunks() async throws {
        // Given
        let customChunks = [
            ChatCompletionChunk(
                id: "chunk-1",
                object: "chat.completion.chunk",
                created: Int(Date().timeIntervalSince1970),
                model: "test-model",
                systemFingerprint: nil,
                serviceTier: nil,
                choices: [
                    ChatCompletionChunk.Choice(
                        index: 0,
                        delta: ChatCompletionChunk.Delta(
                            role: "assistant",
                            content: "Hello",
                            toolCalls: nil
                        ),
                        finishReason: nil
                    )
                ],
                usage: nil
            ),
            ChatCompletionChunk(
                id: "chunk-2",
                object: "chat.completion.chunk",
                created: Int(Date().timeIntervalSince1970),
                model: "test-model",
                systemFingerprint: nil,
                serviceTier: nil,
                choices: [
                    ChatCompletionChunk.Choice(
                        index: 0,
                        delta: ChatCompletionChunk.Delta(
                            role: nil,
                            content: " world!",
                            toolCalls: nil
                        ),
                        finishReason: "stop"
                    )
                ],
                usage: nil
            )
        ]
        
        mockProvider.setMockStreamChunks(customChunks)
        
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [.user(content: .text("Say hello"))],
            stream: true
        )
        
        var receivedChunks: [ChatCompletionChunk] = []
        var fullContent = ""
        
        // When
        for try await chunk in try await mockProvider.sendChatCompletionStream(request: request) {
            receivedChunks.append(chunk)
            if let content = chunk.choices.first?.delta.content {
                fullContent += content
            }
        }
        
        // Then
        XCTAssertEqual(receivedChunks.count, 2)
        XCTAssertEqual(fullContent, "Hello world!")
        XCTAssertEqual(receivedChunks.first?.choices.first?.delta.role, "assistant")
        XCTAssertEqual(receivedChunks.last?.choices.first?.finishReason, "stop")
    }
    
    // MARK: - Streaming Error Tests
    
    func testStreamingErrorHandling() async throws {
        // Given
        mockProvider.shouldThrowError = true
        mockProvider.errorToThrow = LLMError.networkError(nil, "Network failure")
        
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [.user(content: .text("Test"))],
            stream: true
        )
        
        // When & Then
        do {
            for try await _ in try await mockProvider.sendChatCompletionStream(request: request) {
                XCTFail("Should not receive chunks when error is thrown")
            }
            XCTFail("Expected error to be thrown")
        } catch let error as LLMError {
            if case .networkError(_, let message) = error {
                XCTAssertEqual(message, "Network failure")
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    // MARK: - Streaming Content Assembly Tests
    
    func testStreamingContentAssembly() async throws {
        // Given
        let words = ["The", " quick", " brown", " fox", " jumps"]
        let customChunks = words.enumerated().map { index, word in
            ChatCompletionChunk(
                id: "chunk-\(index)",
                object: "chat.completion.chunk",
                created: Int(Date().timeIntervalSince1970),
                model: "test-model",
                systemFingerprint: nil,
                serviceTier: nil,
                choices: [
                    ChatCompletionChunk.Choice(
                        index: 0,
                        delta: ChatCompletionChunk.Delta(
                            role: index == 0 ? "assistant" : nil,
                            content: word,
                            toolCalls: nil
                        ),
                        finishReason: index == words.count - 1 ? "stop" : nil
                    )
                ],
                usage: nil
            )
        }
        
        mockProvider.setMockStreamChunks(customChunks)
        
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [.user(content: .text("Complete this sentence"))],
            stream: true
        )
        
        var assembledContent = ""
        var chunkCount = 0
        
        // When
        for try await chunk in try await mockProvider.sendChatCompletionStream(request: request) {
            chunkCount += 1
            if let content = chunk.choices.first?.delta.content {
                assembledContent += content
            }
        }
        
        // Then
        XCTAssertEqual(chunkCount, words.count)
        XCTAssertEqual(assembledContent, "The quick brown fox jumps")
    }
    
    // MARK: - Empty and Edge Case Tests
    
    func testStreamingWithEmptyChunks() async throws {
        // Given
        mockProvider.setMockStreamChunks([])
        
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [.user(content: .text("Test"))],
            stream: true
        )
        
        var chunkCount = 0
        
        // When
        for try await _ in try await mockProvider.sendChatCompletionStream(request: request) {
            chunkCount += 1
        }
        
        // Then
        XCTAssertGreaterThan(chunkCount, 0) // Should use default chunks when empty
    }
    
    func testStreamingWithNilContent() async throws {
        // Given
        let chunksWithNilContent = [
            ChatCompletionChunk(
                id: "chunk-1",
                object: "chat.completion.chunk",
                created: Int(Date().timeIntervalSince1970),
                model: "test-model",
                systemFingerprint: nil,
                serviceTier: nil,
                choices: [
                    ChatCompletionChunk.Choice(
                        index: 0,
                        delta: ChatCompletionChunk.Delta(
                            role: "assistant",
                            content: nil, // Nil content
                            toolCalls: nil
                        ),
                        finishReason: nil
                    )
                ],
                usage: nil
            ),
            ChatCompletionChunk(
                id: "chunk-2",
                object: "chat.completion.chunk",
                created: Int(Date().timeIntervalSince1970),
                model: "test-model",
                systemFingerprint: nil,
                serviceTier: nil,
                choices: [
                    ChatCompletionChunk.Choice(
                        index: 0,
                        delta: ChatCompletionChunk.Delta(
                            role: nil,
                            content: "Hello",
                            toolCalls: nil
                        ),
                        finishReason: "stop"
                    )
                ],
                usage: nil
            )
        ]
        
        mockProvider.setMockStreamChunks(chunksWithNilContent)
        
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [.user(content: .text("Test"))],
            stream: true
        )
        
        var receivedContent = ""
        
        // When
        for try await chunk in try await mockProvider.sendChatCompletionStream(request: request) {
            if let content = chunk.choices.first?.delta.content {
                receivedContent += content
            }
        }
        
        // Then
        XCTAssertEqual(receivedContent, "Hello")
    }
    
    // MARK: - Performance Tests
    
    func testStreamingPerformance() async throws {
        // Given
        mockProvider.delay = 0.001 // Very small delay for performance testing
        
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [.user(content: .text("Performance test"))],
            stream: true
        )
        
        // When & Then
        let startTime = Date()
        var chunkCount = 0
        
        for try await _ in try await mockProvider.sendChatCompletionStream(request: request) {
            chunkCount += 1
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete streaming reasonably quickly
        XCTAssertLessThan(duration, 1.0)
        XCTAssertGreaterThan(chunkCount, 0)
    }
    
    // MARK: - Concurrent Streaming Tests
    
    func testConcurrentStreaming() async throws {
        // Given
        let request1 = ChatCompletionRequest(
            model: "test-model-1",
            messages: [.user(content: .text("First stream"))],
            stream: true
        )
        
        let request2 = ChatCompletionRequest(
            model: "test-model-2",
            messages: [.user(content: .text("Second stream"))],
            stream: true
        )
        
        var stream1Chunks: [ChatCompletionChunk] = []
        var stream2Chunks: [ChatCompletionChunk] = []
        
        // When
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    for try await chunk in try await self.mockProvider.sendChatCompletionStream(request: request1) {
                        stream1Chunks.append(chunk)
                    }
                } catch {
                    XCTFail("Stream 1 failed: \(error)")
                }
            }
            
            group.addTask {
                do {
                    for try await chunk in try await self.mockProvider.sendChatCompletionStream(request: request2) {
                        stream2Chunks.append(chunk)
                    }
                } catch {
                    XCTFail("Stream 2 failed: \(error)")
                }
            }
        }
        
        // Then
        XCTAssertGreaterThan(stream1Chunks.count, 0)
        XCTAssertGreaterThan(stream2Chunks.count, 0)
        XCTAssertEqual(mockProvider.requestCount, 2)
    }
    
    // MARK: - Integration Tests with Real OpenAI Provider
    
    func testOpenAIIntegration() async throws {
        // Skip if no API key is available
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY environment variable is required for integration tests")
        }
        
        // Get model from environment variable or use default
        let model = ProcessInfo.processInfo.environment["TEST_MODEL"] ?? "gpt-4o"
        
        print("🧠 Testing OpenAI streaming with model: \(model)")
        
        // Initialize real OpenAI provider
        let provider = OpenAIProvider(apiKey: apiKey)
        
        // Create request
        let request = ChatCompletionRequest(
            model: model,
            messages: [
                .system(content: .text("You are a helpful assistant. Think step by step.")),
                .user(content: .text("Count from 1 to 5 and explain each number."))
            ],
            maxTokens: 300,
            stream: true
        )
        
        var receivedChunks: [ChatCompletionChunk] = []
        var fullContent = ""
        var hasAssistantRole = false
        var hasFinishReason = false
        
        // When
        for try await chunk in try await provider.sendChatCompletionStream(request: request) {
            receivedChunks.append(chunk)
            
            if let choice = chunk.choices.first {
                if let content = choice.delta.content {
                    fullContent += content
                    print(content, terminator: "")
                }
                
                if choice.delta.role == "assistant" {
                    hasAssistantRole = true
                }
                
                if choice.finishReason != nil {
                    hasFinishReason = true
                }
            }
        }
        
        print("\n") // New line after streaming
        
        // Then
        XCTAssertGreaterThan(receivedChunks.count, 0, "Should receive at least one chunk")
        XCTAssertFalse(fullContent.isEmpty, "Should receive content")
        XCTAssertTrue(hasAssistantRole, "Should receive assistant role")
        XCTAssertTrue(hasFinishReason, "Should receive finish reason")
        
        print("✅ Streaming completed")
        print("📊 Received \(receivedChunks.count) chunks")
        print("📝 Full content length: \(fullContent.count) characters")
        print("🏷️  Returned model: \(receivedChunks.first?.model ?? "N/A")")
    }
} 