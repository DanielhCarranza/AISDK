//
//  AnthropicService.swift
//  
//
//  Created by Lou Zell on 12/13/24.
//

import Foundation
import Alamofire

/// Native Anthropic API service implementing the full /v1/messages endpoint
/// with support for all beta features and enhanced configuration options.
///
/// This service uses the native Anthropic API format, not the OpenAI compatibility layer.
/// It supports all Anthropic-specific features including beta features like token-efficient tools,
/// extended thinking, and interleaved thinking.
///
/// Example Usage:
/// ```swift
/// let service = AnthropicService(apiKey: "your-api-key")
/// 
/// let request = AnthropicMessageRequestBody(
///     maxTokens: 1000,
///     messages: [
///         AnthropicInputMessage(role: "user", content: [
///             .text("Hello, how are you?")
///         ])
///     ],
///     model: "claude-sonnet-4-5-20250929"
/// )
/// 
/// // Non-streaming
/// let response = try await service.messageRequest(body: request)
/// 
/// // Streaming
/// let stream = try await service.streamingMessageRequest(body: request)
/// for try await chunk in stream {
///     // Process chunks
/// }
/// ```
public class AnthropicService {
    
    // MARK: - Properties
    
    private let apiKey: String
    private let baseUrl: String
    private let session: Session
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    
    /// The selected model for this provider instance
    public let model: LLMModelProtocol
    
    // MARK: - Beta Feature Configuration
    
    /// Configuration for beta features
    public struct BetaConfiguration: Sendable, Equatable, Codable {

        // MARK: - Core Features

        /// Enable token-efficient tool definitions
        public var tokenEfficientTools: Bool

        /// Enable extended thinking (configured via request body, not header)
        public var extendedThinking: Bool

        /// Enable interleaved thinking with tools
        public var interleavedThinking: Bool

        /// Enable MCP (Model Context Protocol) client
        public var mcpClient: Bool

        /// Enable search results handling (GA, no beta header)
        public var searchResults: Bool

        // MARK: - New Features

        /// Enable Files API for file upload and reference
        public var filesAPI: Bool

        /// Enable 1M token context window (Sonnet 4.5 only)
        public var context1M: Bool

        /// Enable computer use tool
        public var computerUse: Bool

        /// Enable code execution sandbox
        public var codeExecution: Bool

        /// Enable container skills
        public var skills: Bool

        /// Enable extended cache TTL (1 hour instead of 5 minutes)
        public var extendedCacheTTL: Bool

        /// Enable context management strategies
        public var contextManagement: Bool

        /// Enable 128K output tokens
        public var output128k: Bool

        // MARK: - Initialization

        public init(
            tokenEfficientTools: Bool = false,
            extendedThinking: Bool = false,
            interleavedThinking: Bool = false,
            mcpClient: Bool = false,
            searchResults: Bool = false,
            filesAPI: Bool = false,
            context1M: Bool = false,
            computerUse: Bool = false,
            codeExecution: Bool = false,
            skills: Bool = false,
            extendedCacheTTL: Bool = false,
            contextManagement: Bool = false,
            output128k: Bool = false
        ) {
            self.tokenEfficientTools = tokenEfficientTools
            self.extendedThinking = extendedThinking
            self.interleavedThinking = interleavedThinking
            self.mcpClient = mcpClient
            self.searchResults = searchResults
            self.filesAPI = filesAPI
            self.context1M = context1M
            self.computerUse = computerUse
            self.codeExecution = codeExecution
            self.skills = skills
            self.extendedCacheTTL = extendedCacheTTL
            self.contextManagement = contextManagement
            self.output128k = output128k
        }

        // MARK: - Header Generation

        private static let headerMap: [(KeyPath<BetaConfiguration, Bool>, String)] = [
            (\.tokenEfficientTools, "token-efficient-tools-2025-02-19"),
            (\.interleavedThinking, "interleaved-thinking-2025-05-14"),
            (\.mcpClient, "mcp-client-2025-11-20"),
            (\.filesAPI, "files-api-2025-04-14"),
            (\.context1M, "context-1m-2025-08-07"),
            (\.computerUse, "computer-use-2025-01-24"),
            (\.codeExecution, "code-execution-2025-05-22"),
            (\.skills, "skills-2025-10-02"),
            (\.extendedCacheTTL, "extended-cache-ttl-2025-04-11"),
            (\.contextManagement, "context-management-2025-06-27"),
            (\.output128k, "output-128k-2025-02-19")
        ]

        /// Generate the `anthropic-beta` header value
        public func headerValue() -> String? {
            let features = Self.headerMap
                .filter { self[keyPath: $0.0] }
                .map { $0.1 }

            return features.isEmpty ? nil : features.joined(separator: ",")
        }

        // MARK: - Merging

        /// Merge with another configuration (other takes precedence for true values)
        public func merging(with other: BetaConfiguration) -> BetaConfiguration {
            BetaConfiguration(
                tokenEfficientTools: tokenEfficientTools || other.tokenEfficientTools,
                extendedThinking: extendedThinking || other.extendedThinking,
                interleavedThinking: interleavedThinking || other.interleavedThinking,
                mcpClient: mcpClient || other.mcpClient,
                searchResults: searchResults || other.searchResults,
                filesAPI: filesAPI || other.filesAPI,
                context1M: context1M || other.context1M,
                computerUse: computerUse || other.computerUse,
                codeExecution: codeExecution || other.codeExecution,
                skills: skills || other.skills,
                extendedCacheTTL: extendedCacheTTL || other.extendedCacheTTL,
                contextManagement: contextManagement || other.contextManagement,
                output128k: output128k || other.output128k
            )
        }

        // MARK: - Presets

        public static let none = BetaConfiguration()

        public static let all = BetaConfiguration(
            tokenEfficientTools: true,
            extendedThinking: true,
            interleavedThinking: true,
            mcpClient: true,
            searchResults: true,
            filesAPI: true,
            context1M: true,
            computerUse: true,
            codeExecution: true,
            skills: true,
            extendedCacheTTL: true,
            contextManagement: true,
            output128k: true
        )

        public static var thinkingWithTools: BetaConfiguration {
            BetaConfiguration(
                extendedThinking: true,
                interleavedThinking: true
            )
        }

        public static var files: BetaConfiguration {
            BetaConfiguration(filesAPI: true)
        }

        public static var maxContext: BetaConfiguration {
            BetaConfiguration(context1M: true)
        }
    }

    public var betaConfiguration: BetaConfiguration
    
    // MARK: - Initialization
    
    /// Model-aware initializer with smart default
    /// - Parameters:
    ///   - model: The Anthropic model to use (defaults to Claude Sonnet 4.5)
    ///   - apiKey: Your Anthropic API key (falls back to environment variables)
    ///   - baseUrl: Base URL for Anthropic's native API (defaults to official API)
    ///   - session: Custom Alamofire session for advanced networking configuration
    ///   - betaConfiguration: Configuration for beta features
    ///   - maxRetries: Maximum number of retry attempts for failed requests
    ///   - retryDelay: Delay between retry attempts in seconds
    public init(
        model: LLMModelProtocol? = nil,
        apiKey: String? = nil,
        baseUrl: String = "https://api.anthropic.com/v1",
        session: Session = .default,
        betaConfiguration: BetaConfiguration = .none,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0
    ) {
        // Use provided model or default to Anthropic's best general-purpose model
        self.model = model ?? AnthropicModels.sonnet45
        
        // Support both ANTHROPIC_API_KEY and CLAUDE_API_KEY environment variables
        self.apiKey = apiKey 
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] 
            ?? ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] 
            ?? ""
        
        self.baseUrl = baseUrl
        self.session = session
        self.betaConfiguration = betaConfiguration
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
    
    /// Legacy initializer - maintained for backward compatibility
    /// - Parameters:
    ///   - apiKey: Your Anthropic API key (supports both ANTHROPIC_API_KEY and CLAUDE_API_KEY)
    ///   - baseUrl: Base URL for Anthropic's native API (defaults to official API)
    ///   - session: Custom Alamofire session for advanced networking configuration
    ///   - betaConfiguration: Configuration for beta features
    ///   - maxRetries: Maximum number of retry attempts for failed requests
    ///   - retryDelay: Delay between retry attempts in seconds
    public init(
        apiKey: String? = nil,
        baseUrl: String = "https://api.anthropic.com/v1",
        session: Session = .default,
        betaConfiguration: BetaConfiguration = .none,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0
    ) {
        self.model = AnthropicModels.sonnet45 // Default model for legacy usage
        
        // Support both ANTHROPIC_API_KEY and CLAUDE_API_KEY environment variables
        self.apiKey = apiKey 
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] 
            ?? ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] 
            ?? ""
        
        self.baseUrl = baseUrl
        self.session = session
        self.betaConfiguration = betaConfiguration
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
    
    // MARK: - Convenience Initializers
    
    /// Initialize with environment variable API key
    public convenience init(
        betaConfiguration: BetaConfiguration = .none,
        maxRetries: Int = 3
    ) {
        self.init(
            model: nil,
            apiKey: nil,
            betaConfiguration: betaConfiguration,
            maxRetries: maxRetries
        )
    }
    
    // MARK: - Headers Management

    /// Check if the request body requires the extended cache TTL beta header.
    /// Returns true if any system block or tool has cache_control with ttl "1h".
    private func needsExtendedCacheTTL(_ body: AnthropicMessageRequestBody) -> Bool {
        if let blocks = body.systemBlocks {
            for block in blocks {
                if block.cacheControl?.ttl == "1h" { return true }
            }
        }
        if let tools = body.tools {
            for tool in tools {
                if tool.cacheControl?.ttl == "1h" { return true }
            }
        }
        return false
    }

    private func logDeprecationWarningIfNeeded(for modelName: String) {
        guard let model = AnthropicModels.findModel(modelName) else { return }
        guard model.isDeprecated else { return }

        var message = "⚠️ Warning: Model '\(model.name)' is deprecated."
        if let deprecationMessage = model.metadata["deprecationMessage"] as? String {
            message += " \(deprecationMessage)"
        }
        print(message)
    }
    
    private func authorizationHeaders(using beta: BetaConfiguration) -> HTTPHeaders {
        var headers = HTTPHeaders()
        // Anthropic uses x-api-key header, not Authorization Bearer
        headers.add(name: "x-api-key", value: apiKey)
        headers.add(.contentType("application/json"))
        headers.add(name: "anthropic-version", value: "2023-06-01")

        if let betaHeader = beta.headerValue() {
            headers.add(name: "anthropic-beta", value: betaHeader)
        }

        return headers
    }
    

    
    // MARK: - Error Handling
    
    private func handleAnthropicError(_ error: Error, statusCode: Int? = nil) -> LLMError {
        if let afError = error as? AFError {
            if let responseCode = afError.responseCode {
                switch responseCode {
                case 400:
                    return .invalidRequest("Anthropic API: \(afError.localizedDescription)")
                case 401:
                    return .authenticationError
                case 403:
                    return .invalidRequest("Anthropic API: Permission denied")
                case 404:
                    return .modelNotAvailable
                case 413:
                    return .contextLengthExceeded
                case 429:
                    return .rateLimitExceeded
                case 500...599:
                    return .networkError(responseCode, "Anthropic API server error")
                default:
                    return .networkError(responseCode, "Anthropic API: \(afError.localizedDescription)")
                }
            }
            return .networkError(nil, "Anthropic API: \(afError.localizedDescription)")
        }
        
        if let decodingError = error as? DecodingError {
            return .parsingError("Anthropic API response parsing failed: \(decodingError.localizedDescription)")
        }
        
        return .underlying(error)
    }
    
    // MARK: - Public API Methods
    
    /// Initiates a non-streaming request to the native Anthropic /v1/messages endpoint.
    ///
    /// - Parameters:
    ///   - body: The message request body following Anthropic's native API format
    /// - Returns: The complete message response from Anthropic
    /// - Throws: LLMError for various failure scenarios with provider-specific context
    public func messageRequest(
        body: AnthropicMessageRequestBody,
        betaOverride: BetaConfiguration? = nil
    ) async throws -> AnthropicMessageResponseBody {
        
        guard !apiKey.isEmpty else {
            throw LLMError.authenticationError
        }
        
        var enhancedRequest = body
        var effectiveBeta = betaOverride.map { betaConfiguration.merging(with: $0) } ?? betaConfiguration

        logDeprecationWarningIfNeeded(for: enhancedRequest.model)

        // Auto-enable extended cache TTL header when request uses 1h cache control
        if needsExtendedCacheTTL(enhancedRequest) {
            effectiveBeta.extendedCacheTTL = true
        }

        // Apply beta feature configurations
        if effectiveBeta.tokenEfficientTools {
            enhancedRequest.enableTokenEfficientTools = true
        }

        // Add thinking configuration for extended thinking
        if effectiveBeta.extendedThinking, enhancedRequest.thinking == nil {
            // Use 1/4 of max_tokens for thinking, with minimum of 1024
            let thinkingBudget = max(1024, enhancedRequest.maxTokens / 4)
            enhancedRequest.thinking = .enabled(budgetTokens: thinkingBudget)
        }

        try enhancedRequest.validate()

        let endpoint = "\(baseUrl)/messages"

        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid Anthropic API URL configuration")
        }

        var lastError: Error?
        

        

        
        // Retry logic
        for attempt in 0...maxRetries {
            do {
                let dataTask = session.request(
                    url,
                    method: .post,
                    parameters: enhancedRequest,
                    encoder: JSONParameterEncoder.default,
                    headers: authorizationHeaders(using: effectiveBeta)
                )
                .validate()
                .serializingDecodable(AnthropicMessageResponseBody.self, decoder: AnthropicHTTPClient.decoder)
                
                let result = await dataTask.result
                
                switch result {
                case .success(let response):
                    return response
                case .failure(let afError):
                    lastError = afError
                    
                    // Don't retry on client errors (4xx) except rate limiting
                    if let statusCode = afError.responseCode {
                        if statusCode >= 400 && statusCode < 500 && statusCode != 429 {
                            throw handleAnthropicError(afError)
                        }
                    }
                    
                    // If this is our last attempt, throw the error
                    if attempt == maxRetries {
                        throw handleAnthropicError(afError)
                    }
                    
                    // Wait before retrying
                    try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            } catch {
                lastError = error
                
                // If this is our last attempt, throw the error
                if attempt == maxRetries {
                    throw handleAnthropicError(error)
                }
                
                // Wait before retrying
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
        
        // This should never be reached, but just in case
        throw handleAnthropicError(lastError ?? LLMError.networkError(nil, "Unknown error"))
    }
    
    /// Initiates a streaming request to the native Anthropic /v1/messages endpoint.
    ///
    /// - Parameters:
    ///   - body: The message request body with streaming enabled
    /// - Returns: An async sequence of streaming chunks
    /// - Throws: LLMError for various failure scenarios with provider-specific context
    public func streamingMessageRequest(
        body: AnthropicMessageRequestBody,
        betaOverride: BetaConfiguration? = nil
    ) async throws -> AnthropicAsyncChunks {
        
        guard !apiKey.isEmpty else {
            throw LLMError.authenticationError
        }
        
        var enhancedRequest = body
        var effectiveBeta = betaOverride.map { betaConfiguration.merging(with: $0) } ?? betaConfiguration

        logDeprecationWarningIfNeeded(for: enhancedRequest.model)

        // Auto-enable extended cache TTL header when request uses 1h cache control
        if needsExtendedCacheTTL(enhancedRequest) {
            effectiveBeta.extendedCacheTTL = true
        }

        // Apply beta feature configurations
        if effectiveBeta.tokenEfficientTools {
            enhancedRequest.enableTokenEfficientTools = true
        }

        // Add thinking configuration for extended thinking
        if effectiveBeta.extendedThinking, enhancedRequest.thinking == nil {
            // Use 1/4 of max_tokens for thinking, with minimum of 1024
            let thinkingBudget = max(1024, enhancedRequest.maxTokens / 4)
            enhancedRequest.thinking = .enabled(budgetTokens: thinkingBudget)
        }

        enhancedRequest.stream = true

        try enhancedRequest.validate()
        
        let endpoint = "\(baseUrl)/messages"
        
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid Anthropic API URL configuration")
        }
        
        // Create URLRequest for streaming
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        
        // Add headers
        for header in authorizationHeaders(using: effectiveBeta) {
            urlRequest.setValue(header.value, forHTTPHeaderField: header.name)
        }
        
        // Encode body
        do {
            urlRequest.httpBody = try JSONEncoder().encode(enhancedRequest)
        } catch {
            throw LLMError.parsingError("Failed to encode request: \(error.localizedDescription)")
        }
        
        // Create streaming session
        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: urlRequest)
            
            // Check response status
            if let httpResponse = response as? HTTPURLResponse {
                guard 200...299 ~= httpResponse.statusCode else {
                    throw handleAnthropicError(
                        LLMError.networkError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)"),
                        statusCode: httpResponse.statusCode
                    )
                }
            }
            
            return AnthropicAsyncChunks(asyncLines: asyncBytes.lines)
            
        } catch {
            throw handleAnthropicError(error)
        }
    }
    
    // MARK: - Configuration Methods
    
    /// Update beta feature configuration
    public func withBetaConfiguration(_ configuration: BetaConfiguration) -> AnthropicService {
        return AnthropicService(
            apiKey: self.apiKey,
            baseUrl: self.baseUrl,
            session: self.session,
            betaConfiguration: configuration,
            maxRetries: self.maxRetries,
            retryDelay: self.retryDelay
        )
    }
    
    /// Enable specific beta features
    public func withBetaFeatures(
        tokenEfficientTools: Bool = false,
        extendedThinking: Bool = false,
        interleavedThinking: Bool = false,
        mcpClient: Bool = false,
        searchResults: Bool = false,
        filesAPI: Bool = false,
        context1M: Bool = false,
        computerUse: Bool = false,
        codeExecution: Bool = false,
        skills: Bool = false,
        extendedCacheTTL: Bool = false,
        contextManagement: Bool = false,
        output128k: Bool = false
    ) -> AnthropicService {
        let configuration = BetaConfiguration(
            tokenEfficientTools: tokenEfficientTools,
            extendedThinking: extendedThinking,
            interleavedThinking: interleavedThinking,
            mcpClient: mcpClient,
            searchResults: searchResults,
            filesAPI: filesAPI,
            context1M: context1M,
            computerUse: computerUse,
            codeExecution: codeExecution,
            skills: skills,
            extendedCacheTTL: extendedCacheTTL,
            contextManagement: contextManagement,
            output128k: output128k
        )
        return withBetaConfiguration(configuration)
    }
    
    /// Get current configuration status
    public var configurationStatus: String {
        var features: [String] = []
        if betaConfiguration.tokenEfficientTools { features.append("token-efficient-tools") }
        if betaConfiguration.extendedThinking { features.append("extended-thinking") }
        if betaConfiguration.interleavedThinking { features.append("interleaved-thinking") }
        if betaConfiguration.mcpClient { features.append("mcp-client") }
        if betaConfiguration.searchResults { features.append("search-results") }
        if betaConfiguration.filesAPI { features.append("files-api") }
        if betaConfiguration.context1M { features.append("context-1m") }
        if betaConfiguration.computerUse { features.append("computer-use") }
        if betaConfiguration.codeExecution { features.append("code-execution") }
        if betaConfiguration.skills { features.append("skills") }
        if betaConfiguration.extendedCacheTTL { features.append("extended-cache-ttl") }
        if betaConfiguration.contextManagement { features.append("context-management") }
        if betaConfiguration.output128k { features.append("output-128k") }
        
        return """
        AnthropicService Configuration:
        - Base URL: \(baseUrl)
        - Beta Features: \(features.isEmpty ? "none" : features.joined(separator: ", "))
        - Max Retries: \(maxRetries)
        - Retry Delay: \(retryDelay)s
        """
    }
    
    // MARK: - Structured Output Methods
    
    /// Generate a structured object from Anthropic using JSON mode and type-safe decoding
    ///
    /// This method provides OpenAI-compatible structured output functionality for Anthropic models.
    /// It automatically handles system prompt modification to ensure JSON responses and provides
    /// type-safe decoding of the structured data.
    ///
    /// Examples:
    /// ```swift
    /// // For raw responses:
    /// let request = AnthropicMessageRequestBody(
    ///     maxTokens: 1000,
    ///     messages: [
    ///         AnthropicInputMessage(content: [.text("Hello")], role: .user)
    ///     ],
    ///     model: "claude-sonnet-4-5-20250929"
    /// )
    /// let response: AnthropicMessageResponseBody = try await service.generateObject(request: request)
    ///
    /// // For JSON object responses:
    /// let jsonRequest = AnthropicMessageRequestBody(
    ///     maxTokens: 1000,
    ///     messages: [...],
    ///     model: "claude-sonnet-4-5-20250929",
    ///     responseFormat: .jsonObject
    /// )
    /// let book: Book = try await service.generateObject(request: jsonRequest)
    ///
    /// // For schema-validated objects:
    /// let schemaRequest = AnthropicMessageRequestBody(
    ///     maxTokens: 1000,
    ///     messages: [...],
    ///     model: "claude-sonnet-4-5-20250929",
    ///     responseFormat: .jsonSchema(
    ///         name: "book_recommendation",
    ///         description: "A book recommendation with details",
    ///         schemaBuilder: Book.schema(),
    ///         strict: true
    ///     )
    /// )
    /// let book: Book = try await service.generateObject(request: schemaRequest)
    /// ```
    public func generateObject<T: Decodable>(
        request: AnthropicMessageRequestBody
    ) async throws -> T {
        // Create an enhanced request with modified system prompt for structured output
        var enhancedRequest = request
        
        // Handle response format by modifying the system prompt
        if let responseFormat = request.responseFormat {
            let originalSystem = request.system ?? ""
            
            if let systemAddition = responseFormat.systemPromptAddition {
                let enhancedSystem = originalSystem.isEmpty 
                    ? systemAddition
                    : "\(originalSystem)\n\n\(systemAddition)"
                
                enhancedRequest = AnthropicMessageRequestBody(
                    maxTokens: request.maxTokens,
                    messages: request.messages,
                    model: request.model,
                    metadata: request.metadata,
                    stopSequences: request.stopSequences,
                    stream: request.stream,
                    system: enhancedSystem,
                    temperature: request.temperature,
                    toolChoice: request.toolChoice,
                    tools: request.tools,
                    topK: request.topK,
                    topP: request.topP,
                    thinking: request.thinking,
                    mcpServers: request.mcpServers,
                    container: request.container,
                    responseFormat: nil // Remove from actual request since Anthropic doesn't support it
                )
            }
        }
        
        // Make the request using the existing messageRequest method
        let response = try await messageRequest(body: enhancedRequest)
        
        // If T is AnthropicMessageResponseBody, return it directly
        if T.self is AnthropicMessageResponseBody.Type {
            return response as! T
        }
        
        // Otherwise, extract content and parse as JSON
        guard let firstContent = response.content.first else {
            throw LLMError.parsingError("No content in Anthropic response")
        }
        
        // Extract text content from the response
        let contentText: String
        switch firstContent {
        case .text(let text, citations: _):
            contentText = text
        case .toolUse(_):
            throw LLMError.parsingError("Received tool use response when expecting structured data")
        case .mcpToolUse(_):
            throw LLMError.parsingError("Received MCP tool use response when expecting structured data")
        case .mcpToolResult(_):
            throw LLMError.parsingError("Received MCP tool result response when expecting structured data")
        case .thinking(_):
            throw LLMError.parsingError("Received thinking response when expecting structured data")
        case .redactedThinking(_):
            throw LLMError.parsingError("Received redacted thinking response when expecting structured data")
        }
        
        // Strip markdown code fences if present (Claude often wraps JSON in ```json ... ```)
        var cleanedContent = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedContent.hasPrefix("```json") {
            cleanedContent = String(cleanedContent.dropFirst(7))
        } else if cleanedContent.hasPrefix("```") {
            cleanedContent = String(cleanedContent.dropFirst(3))
        }
        if cleanedContent.hasSuffix("```") {
            cleanedContent = String(cleanedContent.dropLast(3))
        }
        cleanedContent = cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Convert response content to JSON data
        guard let jsonData = cleanedContent.data(using: .utf8) else {
            throw LLMError.parsingError("Failed to convert Anthropic response to UTF-8 data")
        }

        // Attempt to decode the content into the target type
        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(T.self, from: jsonData)
            return result
        } catch {
            throw LLMError.parsingError("Failed to decode Anthropic response to \(T.self): \(error.localizedDescription). Response content: \(cleanedContent)")
        }
    }

    // MARK: - MCP Utilities
    
    /// Check if MCP client is enabled
    public var isMCPEnabled: Bool {
        return betaConfiguration.mcpClient
    }
    
    /// Extract MCP tool use blocks from a response
    /// 
    /// - Parameter response: The response to process
    /// - Returns: Array of MCP tool use blocks found in the response
    public func extractMCPToolUses(from response: AnthropicMessageResponseBody) -> [AnthropicMCPToolUseBlock] {
        return response.content.compactMap { content in
            if case .mcpToolUse(let mcpToolUse) = content {
                return mcpToolUse
            }
            return nil
        }
    }
    
    /// Extract MCP tool result blocks from a response
    /// 
    /// - Parameter response: The response to process
    /// - Returns: Array of MCP tool result blocks found in the response
    public func extractMCPToolResults(from response: AnthropicMessageResponseBody) -> [AnthropicMCPToolResultBlock] {
        return response.content.compactMap { content in
            if case .mcpToolResult(let mcpToolResult) = content {
                return mcpToolResult
            }
            return nil
        }
    }
    
    /// Create a follow-up request with MCP tool results
    /// 
    /// - Parameters:
    ///   - originalRequest: The original request
    ///   - toolResults: The MCP tool results to include
    /// - Returns: A new request body with the tool results added
    public func createFollowUpRequest(
        from originalRequest: AnthropicMessageRequestBody,
        withMCPToolResults toolResults: [AnthropicMCPToolResultBlock]
    ) -> AnthropicMessageRequestBody {
        // Convert MCP tool results to input content
        let resultContents: [AnthropicInputContent] = toolResults.map { result in
            // For now, create a simple text representation
            // In a full implementation, this would properly format the MCP result
            let resultText = result.allTextContent
            return .text("MCP tool result for \(result.toolUseId): \(resultText)")
        }
        
        // Create a new assistant message with the tool results
        let assistantMessage = AnthropicInputMessage(
            content: resultContents,
            role: .assistant
        )
        
        // Add to the conversation
        var updatedMessages = originalRequest.messages
        updatedMessages.append(assistantMessage)
        
        return AnthropicMessageRequestBody(
            maxTokens: originalRequest.maxTokens,
            messages: updatedMessages,
            model: originalRequest.model,
            metadata: originalRequest.metadata,
            stopSequences: originalRequest.stopSequences,
            stream: originalRequest.stream,
            system: originalRequest.system,
            systemBlocks: originalRequest.systemBlocks,
            temperature: originalRequest.temperature,
            toolChoice: originalRequest.toolChoice,
            tools: originalRequest.tools,
            topK: originalRequest.topK,
            topP: originalRequest.topP,
            thinking: originalRequest.thinking,
            mcpServers: originalRequest.mcpServers,
            container: originalRequest.container,
            responseFormat: originalRequest.responseFormat
        )
    }
}
