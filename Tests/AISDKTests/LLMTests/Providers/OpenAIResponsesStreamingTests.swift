//
//  OpenAIResponsesStreamingTests.swift
//  AISDKTests
//
//  Created for AISDK Testing - OpenAI Responses API Streaming
//

import XCTest
@testable import AISDK

final class OpenAIResponsesStreamingTests: XCTestCase {
    
    var provider: OpenAIProvider!
    var mockProvider: MockOpenAIResponsesProvider!
    
    override func setUp() {
        super.setUp()
        
        if shouldUseRealAPI() {
            provider = OpenAIProvider(apiKey: getOpenAIAPIKey())
        } else {
            mockProvider = MockOpenAIResponsesProvider()
        }
    }
    
    override func tearDown() {
        provider = nil
        mockProvider = nil
        super.tearDown()
    }
    
    // MARK: - Basic Streaming Tests
    
    func testBasicStreamingResponse() async throws {
        if let provider = provider {
            // Real API test
            var chunks: [ResponseChunk] = []
            var accumulatedText = ""
            
            for try await chunk in provider.createTextResponseStream(
                model: "gpt-4o-mini",
                text: "Count from 1 to 5",
                maxOutputTokens: 20
            ) {
                chunks.append(chunk)
                
                if let deltaText = chunk.delta?.outputText {
                    accumulatedText += deltaText
                }
            }
            
            XCTAssertGreaterThan(chunks.count, 0)
            XCTAssertFalse(accumulatedText.isEmpty)
            
            // Check that the last chunk has final status
            if let lastChunk = chunks.last {
                XCTAssertTrue(lastChunk.status?.isFinal ?? false)
            }
            
        } else {
            // Mock test
            var chunks: [ResponseChunk] = []
            var accumulatedText = ""
            
            for try await chunk in mockProvider.createResponseStream(
                request: ResponseRequest(
                    model: "gpt-4o",
                    input: .string("Count from 1 to 5"),
                    stream: true
                )
            ) {
                chunks.append(chunk)
                
                if let deltaText = chunk.delta?.outputText {
                    accumulatedText += deltaText
                }
            }
            
            XCTAssertEqual(chunks.count, 9) // Default mock has 9 chunks
            XCTAssertEqual(accumulatedText, "This is a mock streaming response for testing.")
            XCTAssertEqual(mockProvider.requestCount, 1)
        }
    }
    
    func testStreamingWithBuilder() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Write a haiku"),
            temperature: 0.8,
            maxOutputTokens: 50,
            stream: true
        )
        
        if let provider = provider {
            // Real API test
            var chunkCount = 0
            var finalStatus: ResponseStatus?
            
            for try await chunk in provider.createResponseStream(request: request) {
                chunkCount += 1
                
                XCTAssertNotNil(chunk.id)
                XCTAssertEqual(chunk.object, "response.chunk")
                XCTAssertTrue(chunk.model.contains("gpt-4o-mini"), "Expected model to contain 'gpt-4o-mini', got: \(chunk.model)")
                
                if let status = chunk.status {
                    finalStatus = status
                }
            }
            
            XCTAssertGreaterThan(chunkCount, 0)
            XCTAssertNotNil(finalStatus)
            
        } else {
            // Mock test
            var chunkCount = 0
            
            for try await chunk in mockProvider.createResponseStream(request: request) {
                chunkCount += 1
                XCTAssertNotNil(chunk.id)
                XCTAssertEqual(chunk.object, "response.chunk")
            }
            
            XCTAssertGreaterThan(chunkCount, 0)
            XCTAssertEqual(mockProvider.lastRequest?.stream, true)
        }
    }
    
    // MARK: - Delta Accumulation Tests
    
    func testDeltaAccumulation() async throws {
        if let provider = provider {
            // Real API test
            var fullText = ""
            var deltaTexts: [String] = []
            
            for try await chunk in provider.createTextResponseStream(
                model: "gpt-4o-mini",
                text: "Say 'Hello World'",
                maxOutputTokens: 50
            ) {
                if let deltaText = chunk.delta?.outputText {
                    deltaTexts.append(deltaText)
                    fullText += deltaText
                }
            }
            
            XCTAssertGreaterThan(deltaTexts.count, 0)
            XCTAssertFalse(fullText.isEmpty)
            
            // Verify that concatenating deltas gives us the full text
            let reconstructedText = deltaTexts.joined()
            XCTAssertEqual(fullText, reconstructedText)
            
        } else {
            // Mock test
            var fullText = ""
            var deltaTexts: [String] = []
            
            for try await chunk in mockProvider.createResponseStream(
                request: ResponseRequest(
                    model: "gpt-4o",
                    input: .string("Say 'Hello World'"),
                    stream: true
                )
            ) {
                if let deltaText = chunk.delta?.outputText {
                    deltaTexts.append(deltaText)
                    fullText += deltaText
                }
            }
            
            XCTAssertEqual(deltaTexts.count, 9)
            XCTAssertEqual(fullText, "This is a mock streaming response for testing.")
        }
    }
    
    // MARK: - Stream Event Types Tests
    
    func testStreamEventTypes() async throws {
        if mockProvider != nil {
            // Mock test with custom chunks
            let customChunks = [
                ResponseChunk(
                    id: "chunk-1",
                    object: "response.chunk",
                    createdAt: Date().timeIntervalSince1970,
                    model: "gpt-4o",
                    status: .inProgress,
                    delta: ResponseDelta(
                        output: nil,
                        outputText: "Hello",
                        reasoning: nil,
                        text: "Hello"
                    ),
                    usage: nil,
                    error: nil
                ),
                ResponseChunk(
                    id: "chunk-2",
                    object: "response.chunk",
                    createdAt: Date().timeIntervalSince1970,
                    model: "gpt-4o",
                    status: .completed,
                    delta: ResponseDelta(
                        output: nil,
                        outputText: " World!",
                        reasoning: nil,
                        text: " World!"
                    ),
                    usage: ResponseUsage(
                        inputTokens: 5,
                        outputTokens: 10,
                        totalTokens: 15,
                        inputTokensDetails: nil,
                        outputTokensDetails: nil
                    ),
                    error: nil
                )
            ]
            
            mockProvider.setMockStreamChunks(customChunks)
            
            var chunks: [ResponseChunk] = []
            var hasUsage = false
            
            for try await chunk in mockProvider.createResponseStream(
                request: ResponseRequest(
                    model: "gpt-4o",
                    input: .string("Test"),
                    stream: true
                )
            ) {
                chunks.append(chunk)
                
                if chunk.usage != nil {
                    hasUsage = true
                }
            }
            
            XCTAssertEqual(chunks.count, 2)
            XCTAssertTrue(hasUsage)
            XCTAssertEqual(chunks[0].status, .inProgress)
            XCTAssertEqual(chunks[1].status, .completed)
        }
    }
    
    // MARK: - Stream Interruption Tests
    
    func testStreamCancellation() async throws {
        if let provider = provider {
            // Real API test - start a stream and cancel it
            let request = ResponseRequest(
                model: "gpt-4o-mini",
                input: .string("Write a very long story"),
                maxOutputTokens: 200,
                stream: true
            )
            
            var chunkCount = 0
            let maxChunks = 3 // Cancel after a few chunks
            
            do {
                for try await chunk in provider.createResponseStream(request: request) {
                    chunkCount += 1
                    
                    if chunkCount >= maxChunks {
                        break // Simulate cancellation
                    }
                }
            } catch {
                // Stream cancellation might throw an error, which is expected
            }
            
            XCTAssertGreaterThanOrEqual(chunkCount, 1)
            XCTAssertLessThanOrEqual(chunkCount, maxChunks)
            
        } else {
            // Mock test - simulate cancellation
            var chunkCount = 0
            let maxChunks = 3
            
            for try await _ in mockProvider.createResponseStream(
                request: ResponseRequest(
                    model: "gpt-4o",
                    input: .string("Write a very long story"),
                    stream: true
                )
            ) {
                chunkCount += 1
                
                if chunkCount >= maxChunks {
                    break
                }
            }
            
            XCTAssertEqual(chunkCount, maxChunks)
        }
    }
    
    // MARK: - Error Handling in Streams
    
    func testStreamErrorHandling() async throws {
        if mockProvider != nil {
            // Mock test - simulate stream error
            mockProvider.shouldThrowError = true
            mockProvider.errorToThrow = AISDKError.streamError("Mock stream error")
            
            do {
                for try await _ in mockProvider.createResponseStream(
                    request: ResponseRequest(
                        model: "gpt-4o",
                        input: .string("Test"),
                        stream: true
                    )
                ) {
                    XCTFail("Should not receive chunks when error is thrown")
                }
                XCTFail("Expected error to be thrown")
            } catch let error as AISDKError {
                if case .streamError(let message) = error {
                    XCTAssertEqual(message, "Mock stream error")
                } else {
                    XCTFail("Unexpected error type: \(error)")
                }
            }
        }
    }
    
    // MARK: - Stream Completion Detection
    
    func testStreamCompletionDetection() async throws {
        if let provider = provider {
            // Real API test
            var lastChunk: ResponseChunk?
            var completedChunks = 0
            
            for try await chunk in provider.createTextResponseStream(
                model: "gpt-4o-mini",
                text: "Say goodbye",
                maxOutputTokens: 50
            ) {
                lastChunk = chunk
                
                if chunk.status?.isFinal == true {
                    completedChunks += 1
                }
            }
            
            XCTAssertNotNil(lastChunk)
            XCTAssertGreaterThan(completedChunks, 0)
            
        } else {
            // Mock test
            var lastChunk: ResponseChunk?
            var completedChunks = 0
            
            for try await chunk in mockProvider.createResponseStream(
                request: ResponseRequest(
                    model: "gpt-4o",
                    input: .string("Say goodbye"),
                    stream: true
                )
            ) {
                lastChunk = chunk
                
                if chunk.status?.isFinal == true {
                    completedChunks += 1
                }
            }
            
            XCTAssertNotNil(lastChunk)
            XCTAssertEqual(completedChunks, 1) // Mock has one completed chunk
        }
    }
    
    // MARK: - Performance Tests
    
    func testStreamingPerformance() async throws {
        if let provider = provider {
            // Real API test - measure streaming performance
            let startTime = Date()
            var chunkCount = 0
            
            for try await _ in provider.createTextResponseStream(
                model: "gpt-4o-mini",
                text: "Count from 1 to 10",
                maxOutputTokens: 50
            ) {
                chunkCount += 1
            }
            
            let duration = Date().timeIntervalSince(startTime)
            
            XCTAssertGreaterThan(chunkCount, 0)
            XCTAssertLessThan(duration, 30.0) // Should complete within 30 seconds
            
            print("Streaming performance: \(chunkCount) chunks in \(duration) seconds")
        }
    }
    
    // MARK: - Helper Methods
    
    private func shouldUseRealAPI() -> Bool {
        return ProcessInfo.processInfo.environment["USE_REAL_API"] == "true" && 
               !getOpenAIAPIKey().isEmpty
    }
    
    private func getOpenAIAPIKey() -> String {
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }
} 