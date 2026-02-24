//
//  CitationLiveTests.swift
//  AISDKTests
//
//  Live API integration tests for citation and web search source extraction.
//  Validates that all three providers correctly extract sources, citations,
//  and web search lifecycle events.
//
//  Run with: RUN_LIVE_TESTS=1 swift test --filter CitationLiveTests
//

import Foundation
import XCTest
@testable import AISDK

final class CitationLiveTests: XCTestCase {

    // MARK: - Helpers

    private func liveTestGuard() throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Live tests disabled (set RUN_LIVE_TESTS=1)")
        }
    }

    private func loadEnvironmentVariables() {
        let envPath = ".env"
        guard let envContent = try? String(contentsOfFile: envPath) else { return }
        for line in envContent.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                let parts = trimmedLine.components(separatedBy: "=")
                if parts.count >= 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
                    setenv(key, value, 0)
                }
            }
        }
    }

    private func openAIKeyOrSkip() throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY required")
        }
        return apiKey
    }

    private func anthropicKeyOrSkip() throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("ANTHROPIC_API_KEY required")
        }
        return apiKey
    }

    private func geminiKeyOrSkip() throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("GOOGLE_API_KEY required")
        }
        return apiKey
    }

    // MARK: - OpenAI Responses API Citation Tests

    func test_openai_responses_streaming_citations() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()
        let client = OpenAIResponsesClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gpt-4o-mini",
            messages: [.user("What are the health benefits of green tea? Search the web and cite your sources.")],
            maxTokens: 1024,
            stream: true,
            builtInTools: [.webSearchDefault]
        )

        var sources: [AISource] = []
        var textChunks: [String] = []
        var webSearchStartedCount = 0
        var webSearchCompletedCount = 0
        var webSearchResults: [AIWebSearchResult] = []

        do {
            for try await event in client.stream(request: request) {
                switch event {
                case .source(let source):
                    sources.append(source)
                case .textDelta(let text):
                    textChunks.append(text)
                case .webSearchStarted:
                    webSearchStartedCount += 1
                case .webSearchCompleted(let result):
                    webSearchCompletedCount += 1
                    webSearchResults.append(result)
                default:
                    break
                }
            }
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("OpenAI rate limited") }
            throw error
        }

        let fullText = textChunks.joined()
        XCTAssertFalse(fullText.isEmpty, "OpenAI streaming should produce text")

        // Verify sources were extracted
        XCTAssertFalse(sources.isEmpty, "OpenAI web search should produce citation sources")

        // Verify sources have URLs
        for source in sources {
            XCTAssertNotNil(source.url, "Source should have a URL")
            XCTAssertFalse(source.url?.isEmpty ?? true, "Source URL should not be empty")
        }

        // Verify web search lifecycle events
        XCTAssertGreaterThan(webSearchStartedCount, 0, "Should have at least one webSearchStarted event")
        XCTAssertGreaterThan(webSearchCompletedCount, 0, "Should have at least one webSearchCompleted event")

        // Verify some sources have position data (startIndex/endIndex)
        let sourcesWithPositions = sources.filter { $0.startIndex != nil && $0.endIndex != nil }
        XCTAssertFalse(sourcesWithPositions.isEmpty, "At least some sources should have position data")

        print("✅ [OpenAI Responses streaming citations]")
        print("   Text: \(fullText.prefix(200))...")
        print("   Sources: \(sources.count)")
        print("   Sources with positions: \(sourcesWithPositions.count)")
        print("   Web search events: started=\(webSearchStartedCount), completed=\(webSearchCompletedCount)")
        if let firstSource = sources.first {
            print("   First source: \(firstSource.title ?? "no title") - \(firstSource.url ?? "no url")")
            if let start = firstSource.startIndex, let end = firstSource.endIndex {
                print("   Position: [\(start)..\(end)]")
                if let snippet = fullText.citedText(startIndex: start, endIndex: end) {
                    print("   Cited text: \"\(snippet.prefix(100))\"")
                }
            }
        }
    }

    func test_openai_responses_nonstreaming_sources() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()
        let client = OpenAIResponsesClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gpt-4o-mini",
            messages: [.user("What is the current population of Tokyo? Use web search.")],
            maxTokens: 1024,
            builtInTools: [.webSearchDefault]
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("OpenAI rate limited") }
            throw error
        }

        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "OpenAI non-streaming web search should return content")

        // Non-streaming responses should also have sources
        XCTAssertFalse(response.sources.isEmpty, "Non-streaming response should have sources")

        print("✅ [OpenAI Responses non-streaming sources]")
        print("   Text: \(text.prefix(200))...")
        print("   Sources: \(response.sources.count)")
        for (i, source) in response.sources.prefix(3).enumerated() {
            print("   [\(i+1)] \(source.title ?? "no title") - \(source.url ?? "no url")")
        }
    }

    // MARK: - Anthropic Citation Tests

    func test_anthropic_streaming_citations() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("What are the latest developments in AI safety research? Search the web.")],
            maxTokens: 1024,
            stream: true,
            builtInTools: [.webSearchDefault]
        )

        var sources: [AISource] = []
        var textChunks: [String] = []
        var webSearchStartedCount = 0
        var webSearchCompletedCount = 0

        do {
            for try await event in client.stream(request: request) {
                switch event {
                case .source(let source):
                    sources.append(source)
                case .textDelta(let text):
                    textChunks.append(text)
                case .webSearchStarted:
                    webSearchStartedCount += 1
                case .webSearchCompleted:
                    webSearchCompletedCount += 1
                default:
                    break
                }
            }
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Anthropic rate limited") }
            let desc = "\(error)"
            if desc.contains("overloaded") || desc.contains("529") {
                throw XCTSkip("Anthropic server overloaded (529)")
            }
            throw error
        } catch {
            if "\(error)".contains("overloaded") || "\(error)".contains("529") {
                throw XCTSkip("Anthropic server overloaded")
            }
            throw error
        }

        let fullText = textChunks.joined()
        XCTAssertFalse(fullText.isEmpty, "Anthropic streaming should produce text")

        // Anthropic should produce source events from citations_delta
        XCTAssertFalse(sources.isEmpty, "Anthropic web search should produce citation sources")

        // Verify sources have URLs (web search result location citations have URLs)
        let webSources = sources.filter { $0.url != nil }
        XCTAssertFalse(webSources.isEmpty, "At least some Anthropic sources should have URLs")

        print("✅ [Anthropic streaming citations]")
        print("   Text: \(fullText.prefix(200))...")
        print("   Sources: \(sources.count) (web: \(webSources.count))")
        print("   Web search events: started=\(webSearchStartedCount), completed=\(webSearchCompletedCount)")
        if let firstWebSource = webSources.first {
            print("   First web source: \(firstWebSource.title ?? "no title") - \(firstWebSource.url ?? "no url")")
            if let snippet = firstWebSource.snippet {
                print("   Snippet: \"\(snippet.prefix(100))\"")
            }
        }
    }

    func test_anthropic_nonstreaming_sources() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("What is the current weather in London? Search the web.")],
            maxTokens: 1024,
            builtInTools: [.webSearchDefault]
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Anthropic rate limited") }
            let desc = "\(error)"
            if desc.contains("overloaded") || desc.contains("529") {
                throw XCTSkip("Anthropic server overloaded (529)")
            }
            throw error
        } catch {
            if "\(error)".contains("overloaded") || "\(error)".contains("529") {
                throw XCTSkip("Anthropic server overloaded")
            }
            throw error
        }

        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "Anthropic non-streaming should return content")

        // Non-streaming should have structured sources (not corrupted text)
        XCTAssertFalse(response.sources.isEmpty, "Non-streaming response should have structured sources")
        // Verify text is not corrupted with URL metadata
        XCTAssertFalse(text.contains("http"), "Text content should not contain raw URLs from web search results")

        print("✅ [Anthropic non-streaming sources]")
        print("   Text: \(text.prefix(200))...")
        print("   Sources: \(response.sources.count)")
        for (i, source) in response.sources.prefix(3).enumerated() {
            print("   [\(i+1)] \(source.title ?? "no title") - \(source.url ?? "no url")")
        }
    }

    // MARK: - Gemini Citation Tests

    func test_gemini_streaming_grounding_sources() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try geminiKeyOrSkip()
        let client = GeminiClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [.user("What are the latest Space X launches? Search the web.")],
            maxTokens: 1024,
            stream: true,
            builtInTools: [.webSearchDefault]
        )

        var sources: [AISource] = []
        var textChunks: [String] = []
        var webSearchStartedCount = 0
        var webSearchCompletedCount = 0

        do {
            for try await event in client.stream(request: request) {
                switch event {
                case .source(let source):
                    sources.append(source)
                case .textDelta(let text):
                    textChunks.append(text)
                case .webSearchStarted:
                    webSearchStartedCount += 1
                case .webSearchCompleted:
                    webSearchCompletedCount += 1
                default:
                    break
                }
            }
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Gemini rate limited") }
            throw error
        }

        let fullText = textChunks.joined()
        XCTAssertFalse(fullText.isEmpty, "Gemini streaming should produce text")

        // Gemini should produce source events from grounding metadata
        XCTAssertFalse(sources.isEmpty, "Gemini web search should produce grounding sources")

        // Verify sources have URLs
        let webSources = sources.filter { $0.url != nil }
        XCTAssertFalse(webSources.isEmpty, "Gemini sources should have URLs")

        // Verify web search lifecycle events
        XCTAssertGreaterThan(webSearchStartedCount, 0, "Should have at least one webSearchStarted event from queries")

        // Check for positional data (from groundingSupports)
        let sourcesWithPositions = sources.filter { $0.startIndex != nil && $0.endIndex != nil }

        print("✅ [Gemini streaming grounding sources]")
        print("   Text: \(fullText.prefix(200))...")
        print("   Sources: \(sources.count) (web: \(webSources.count))")
        print("   Sources with positions: \(sourcesWithPositions.count)")
        print("   Web search events: started=\(webSearchStartedCount), completed=\(webSearchCompletedCount)")
        if let firstSource = webSources.first {
            print("   First source: \(firstSource.title ?? "no title") - \(firstSource.url ?? "no url")")
        }
    }

    func test_gemini_nonstreaming_sources() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try geminiKeyOrSkip()
        let client = GeminiClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [.user("What are the latest developments in quantum computing?")],
            maxTokens: 1024,
            builtInTools: [.webSearchDefault]
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Gemini rate limited") }
            throw error
        }

        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "Gemini non-streaming should return content")

        // Non-streaming should have sources from grounding metadata
        XCTAssertFalse(response.sources.isEmpty, "Non-streaming response should have sources from grounding")

        print("✅ [Gemini non-streaming sources]")
        print("   Text: \(text.prefix(200))...")
        print("   Sources: \(response.sources.count)")
        for (i, source) in response.sources.prefix(3).enumerated() {
            print("   [\(i+1)] \(source.title ?? "no title") - \(source.url ?? "no url")")
        }
    }

    // MARK: - Cross-Provider Citation Format Tests

    func test_citation_position_extraction_with_real_text() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()
        let client = OpenAIResponsesClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gpt-4o-mini",
            messages: [.user("Give me a one paragraph summary of the latest Swift programming language features. Cite sources.")],
            maxTokens: 512,
            stream: true,
            builtInTools: [.webSearchDefault]
        )

        var sources: [AISource] = []
        var textChunks: [String] = []

        do {
            for try await event in client.stream(request: request) {
                switch event {
                case .source(let source):
                    sources.append(source)
                case .textDelta(let text):
                    textChunks.append(text)
                default:
                    break
                }
            }
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("OpenAI rate limited") }
            throw error
        }

        let fullText = textChunks.joined()
        XCTAssertFalse(fullText.isEmpty)

        // For sources with position data, verify citedText extraction works
        let sourcesWithPositions = sources.filter { $0.startIndex != nil && $0.endIndex != nil }
        for source in sourcesWithPositions {
            guard let start = source.startIndex, let end = source.endIndex else { continue }
            let cited = fullText.citedText(startIndex: start, endIndex: end)
            // The cited text should be extractable (positions should be valid)
            XCTAssertNotNil(cited, "Position [\(start)..\(end)] should be valid in text of length \(fullText.utf16.count)")
            if let cited = cited {
                print("   Citation at [\(start)..\(end)]: \"\(cited.prefix(80))\"")
            }
        }

        print("✅ [Citation position extraction] \(sourcesWithPositions.count) citations verified")
    }
}
