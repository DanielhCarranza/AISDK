import XCTest
import Alamofire
@testable import AISDK

/// Comprehensive tests for Anthropic Search Results functionality
final class AnthropicServiceSearchResultsTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var service: AnthropicService!
    private var searchResultsService: AnthropicService!
    private var mockSession: Session!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Create a mock session for controlled testing
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        mockSession = Session(configuration: configuration)
        
        // Initialize services
        service = AnthropicService(
            apiKey: "test-api-key",
            session: mockSession,
            betaConfiguration: .none
        )
        
        searchResultsService = AnthropicService(
            apiKey: "test-api-key",
            session: mockSession,
            betaConfiguration: .none
        ).withBetaFeatures(searchResults: true)
    }
    
    override func tearDown() {
        service = nil
        searchResultsService = nil
        mockSession = nil
        MockURLProtocol.reset()
        super.tearDown()
    }
    
    // MARK: - Search Result Content Block Tests
    
    func testSearchResultContentBlockCreation() {
        let textBlock = AnthropicSearchResultTextBlock(text: "Test content")
        XCTAssertEqual(textBlock.type, "text")
        XCTAssertEqual(textBlock.text, "Test content")
    }
    
    func testSearchResultCitationsConfiguration() {
        let citations = AnthropicSearchResultCitations(enabled: true)
        XCTAssertTrue(citations.enabled)
        
        let disabledCitations = AnthropicSearchResultCitations(enabled: false)
        XCTAssertFalse(disabledCitations.enabled)
    }
    
    func testSearchResultCacheControl() {
        let cacheControl = AnthropicCacheControl(type: "ephemeral")
        XCTAssertEqual(cacheControl.type, "ephemeral")
        
        let defaultCacheControl = AnthropicCacheControl()
        XCTAssertEqual(defaultCacheControl.type, "ephemeral")
    }
    
    func testSearchResultInputContent() {
        let textBlock = AnthropicSearchResultTextBlock(text: "API documentation content")
        let citations = AnthropicSearchResultCitations(enabled: true)
        let cacheControl = AnthropicCacheControl(type: "ephemeral")
        
        let searchResult = AnthropicInputContent.searchResult(
            source: "https://docs.company.com/api",
            title: "API Documentation",
            content: [textBlock],
            citations: citations,
            cacheControl: cacheControl
        )
        
        // Test that search result can be created successfully
        XCTAssertNotNil(searchResult)
    }
    
    // MARK: - Beta Header Tests
    
    func testBetaHeaderConfiguration() {
        let config = AnthropicService.BetaConfiguration(searchResults: true)
        XCTAssertTrue(config.searchResults)
        XCTAssertFalse(config.tokenEfficientTools)
        XCTAssertFalse(config.extendedThinking)
    }
    
    func testWithBetaFeaturesSearchResults() {
        let originalService = AnthropicService(apiKey: "test-key")
        let searchService = originalService.withBetaFeatures(searchResults: true)
        
        // Test that the configuration is properly set
        XCTAssertNotNil(searchService)
        XCTAssertTrue(searchService.configurationStatus.contains("search-results"))
    }
    
    func testAllBetaFeaturesIncludesSearchResults() {
        let allFeaturesService = AnthropicService(
            apiKey: "test-key",
            betaConfiguration: .all
        )
        
        XCTAssertTrue(allFeaturesService.configurationStatus.contains("search-results"))
    }
    
    // MARK: - Top-Level Search Results Tests
    
    func testTopLevelSearchResultsRequest() async {
        // Mock successful response with citations
        let mockResponse = """
        {
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-7-sonnet-20250219",
            "content": [
                {
                    "type": "text",
                    "text": "Based on the API documentation, you need to include an API key in the Authorization header",
                    "citations": [
                        {
                            "type": "search_result_location",
                            "source": "https://docs.company.com/api",
                            "title": "API Documentation",
                            "cited_text": "include an API key in the Authorization header",
                            "search_result_index": 0,
                            "start_block_index": 0,
                            "end_block_index": 0
                        }
                    ]
                }
            ],
            "stop_reason": "end_turn",
            "stop_sequence": null,
            "usage": {
                "input_tokens": 100,
                "output_tokens": 50
            }
        }
        """
        
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        MockURLProtocol.mockData = mockResponse.data(using: .utf8)
        
        let searchResultContent = AnthropicInputContent.searchResult(
            source: "https://docs.company.com/api",
            title: "API Documentation",
            content: [AnthropicSearchResultTextBlock(text: "All API requests must include an API key in the Authorization header.")],
            citations: AnthropicSearchResultCitations(enabled: true),
            cacheControl: nil
        )
        
        let textContent = AnthropicInputContent.text("How do I authenticate API requests?")
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 1000,
            messages: [
                AnthropicInputMessage(
                    content: [searchResultContent, textContent],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219"
        )
        
        do {
            let response = try await searchResultsService.messageRequest(body: request)
            XCTAssertEqual(response.content.count, 1)
            
            if case .text(let text, let citations) = response.content.first {
                XCTAssertTrue(text.contains("API key"))
                XCTAssertNotNil(citations)
                XCTAssertEqual(citations?.count, 1)
                XCTAssertEqual(citations?.first?.type, "search_result_location")
                XCTAssertEqual(citations?.first?.source, "https://docs.company.com/api")
                XCTAssertEqual(citations?.first?.title, "API Documentation")
            } else {
                XCTFail("Expected text content with citations")
            }
        } catch {
            XCTFail("Request failed: \(error)")
        }
    }
    
    // MARK: - Tool-Based Search Results Tests
    
    func testToolBasedSearchResultsRequest() async {
        // Mock tool use response
        let mockToolUseResponse = """
        {
            "id": "msg_123",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-7-sonnet-20250219",
            "content": [
                {
                    "type": "tool_use",
                    "id": "toolu_123",
                    "name": "search_knowledge_base",
                    "input": {
                        "query": "user authentication"
                    }
                }
            ],
            "stop_reason": "tool_use",
            "stop_sequence": null,
            "usage": {
                "input_tokens": 100,
                "output_tokens": 50
            }
        }
        """
        
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        MockURLProtocol.mockData = mockToolUseResponse.data(using: .utf8)
        
        let searchTool = AnthropicTool(
            name: "search_knowledge_base",
            description: "Search the knowledge base for information",
            inputSchema: AnthropicToolSchema(
                properties: [
                    "query": AnthropicPropertySchema(
                        type: "string",
                        description: "The search query"
                    )
                ],
                required: ["query"]
            )
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 1000,
            messages: [
                AnthropicInputMessage(
                    content: [.text("How does user authentication work?")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            tools: [searchTool]
        )
        
        do {
            let response = try await searchResultsService.messageRequest(body: request)
            XCTAssertEqual(response.content.count, 1)
            
            if case .toolUse(let toolUse) = response.content.first {
                XCTAssertEqual(toolUse.name, "search_knowledge_base")
                XCTAssertEqual(toolUse.input["query"] as? String, "user authentication")
            } else {
                XCTFail("Expected tool use content")
            }
        } catch {
            XCTFail("Request failed: \(error)")
        }
    }
    
    func testToolResultWithSearchResults() {
        let searchResult = AnthropicInputContent.searchResult(
            source: "https://docs.company.com/auth",
            title: "Authentication Guide",
            content: [AnthropicSearchResultTextBlock(text: "Authentication is required for all API calls.")],
            citations: AnthropicSearchResultCitations(enabled: true),
            cacheControl: nil
        )
        
        let toolResult = AnthropicInputContent.toolResult(
            toolUseId: "toolu_123",
            content: "Tool executed successfully",
            isError: false
        )
        
        let message = AnthropicInputMessage(
            content: [searchResult, toolResult],
            role: .user
        )
        
        XCTAssertEqual(message.content.count, 2)
        XCTAssertEqual(message.role, .user)
    }
    
    // MARK: - Citation Handling Tests
    
    func testCitationDecoding() {
        let citationJSON = """
        {
            "type": "search_result_location",
            "source": "https://docs.company.com/api",
            "title": "API Documentation",
            "cited_text": "API key required",
            "search_result_index": 0,
            "start_block_index": 0,
            "end_block_index": 0
        }
        """
        
        let data = citationJSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        
        do {
            let citation = try decoder.decode(AnthropicSearchResultCitation.self, from: data)
            XCTAssertEqual(citation.type, "search_result_location")
            XCTAssertEqual(citation.source, "https://docs.company.com/api")
            XCTAssertEqual(citation.title, "API Documentation")
            XCTAssertEqual(citation.citedText, "API key required")
            XCTAssertEqual(citation.searchResultIndex, 0)
            XCTAssertEqual(citation.startBlockIndex, 0)
            XCTAssertEqual(citation.endBlockIndex, 0)
        } catch {
            XCTFail("Failed to decode citation: \(error)")
        }
    }
    
    func testCitationCreation() {
        let citation = AnthropicSearchResultCitation(
            source: "https://example.com",
            title: "Example",
            citedText: "Sample text",
            searchResultIndex: 1,
            startBlockIndex: 2,
            endBlockIndex: 3
        )
        
        XCTAssertEqual(citation.type, "search_result_location")
        XCTAssertEqual(citation.source, "https://example.com")
        XCTAssertEqual(citation.title, "Example")
        XCTAssertEqual(citation.citedText, "Sample text")
        XCTAssertEqual(citation.searchResultIndex, 1)
        XCTAssertEqual(citation.startBlockIndex, 2)
        XCTAssertEqual(citation.endBlockIndex, 3)
    }
    
    // MARK: - Error Handling Tests
    
    func testSearchResultsWithoutBetaHeader() async {
        // Mock error response for missing beta header
        let mockErrorResponse = """
        {
            "type": "error",
            "error": {
                "type": "invalid_request_error",
                "message": "search_result content blocks require the search-results-2025-06-09 beta header"
            }
        }
        """
        
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        MockURLProtocol.mockData = mockErrorResponse.data(using: .utf8)
        
        let searchResultContent = AnthropicInputContent.searchResult(
            source: "https://docs.company.com/api",
            title: "API Documentation",
            content: [AnthropicSearchResultTextBlock(text: "Content")],
            citations: AnthropicSearchResultCitations(enabled: true),
            cacheControl: nil
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 1000,
            messages: [
                AnthropicInputMessage(
                    content: [searchResultContent],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219"
        )
        
        do {
            _ = try await service.messageRequest(body: request) // Using service without beta header
            XCTFail("Expected error for missing beta header")
        } catch {
            // Expected to fail
            XCTAssertTrue(error is LLMError || error is AFError)
        }
    }
    
    func testMixedCitationConfiguration() {
        // According to the docs, all search results must have the same citation setting
        let searchResult1 = AnthropicInputContent.searchResult(
            source: "https://docs.company.com/api",
            title: "API Documentation",
            content: [AnthropicSearchResultTextBlock(text: "Content 1")],
            citations: AnthropicSearchResultCitations(enabled: true),
            cacheControl: nil
        )
        
        let searchResult2 = AnthropicInputContent.searchResult(
            source: "https://docs.company.com/guide",
            title: "User Guide",
            content: [AnthropicSearchResultTextBlock(text: "Content 2")],
            citations: AnthropicSearchResultCitations(enabled: true),
            cacheControl: nil
        )
        
        let message = AnthropicInputMessage(
            content: [searchResult1, searchResult2],
            role: .user
        )
        
        // Both should have consistent citation settings
        XCTAssertEqual(message.content.count, 2)
    }
    
    // MARK: - Integration Tests
    
    func testCompleteSearchResultsWorkflow() async {
        // Mock the complete workflow: initial request -> tool use -> tool result with search results -> final response
        let mockFinalResponse = """
        {
            "id": "msg_456",
            "type": "message",
            "role": "assistant",
            "model": "claude-3-7-sonnet-20250219",
            "content": [
                {
                    "type": "text",
                    "text": "Based on the search results, user authentication requires an API key in the Authorization header.",
                    "citations": [
                        {
                            "type": "search_result_location",
                            "source": "https://docs.company.com/auth",
                            "title": "Authentication Guide",
                            "cited_text": "API key in the Authorization header",
                            "search_result_index": 0,
                            "start_block_index": 0,
                            "end_block_index": 0
                        }
                    ]
                }
            ],
            "stop_reason": "end_turn",
            "stop_sequence": null,
            "usage": {
                "input_tokens": 200,
                "output_tokens": 100
            }
        }
        """
        
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        MockURLProtocol.mockData = mockFinalResponse.data(using: .utf8)
        
        // Simulate tool result with search results
        let searchResult = AnthropicInputContent.searchResult(
            source: "https://docs.company.com/auth",
            title: "Authentication Guide",
            content: [AnthropicSearchResultTextBlock(text: "All API requests must include an API key in the Authorization header.")],
            citations: AnthropicSearchResultCitations(enabled: true),
            cacheControl: nil
        )
        
        let toolResult = AnthropicInputContent.toolResult(
            toolUseId: "toolu_123",
            content: "Found authentication documentation",
            isError: false
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 1000,
            messages: [
                AnthropicInputMessage(
                    content: [.text("How does authentication work?")],
                    role: .user
                ),
                AnthropicInputMessage(
                    content: [.toolUse(id: "toolu_123", name: "search_docs", input: ["query": .string("authentication")])],
                    role: .assistant
                ),
                AnthropicInputMessage(
                    content: [toolResult, searchResult],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219"
        )
        
        do {
            let response = try await searchResultsService.messageRequest(body: request)
            XCTAssertEqual(response.content.count, 1)
            
            if case .text(let text, let citations) = response.content.first {
                XCTAssertTrue(text.contains("authentication"))
                XCTAssertNotNil(citations)
                XCTAssertEqual(citations?.count, 1)
                XCTAssertEqual(citations?.first?.source, "https://docs.company.com/auth")
            } else {
                XCTFail("Expected text content with citations")
            }
        } catch {
            XCTFail("Complete workflow failed: \(error)")
        }
    }
} 