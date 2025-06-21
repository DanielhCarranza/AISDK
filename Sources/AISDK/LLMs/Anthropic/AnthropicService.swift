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
///     model: "claude-3-7-sonnet-20250219"
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
    
    // MARK: - Beta Feature Configuration
    
    /// Configuration for beta features
    public struct BetaConfiguration {
        public let tokenEfficientTools: Bool
        public let extendedThinking: Bool
        public let interleavedThinking: Bool
        public let mcpClient: Bool
        
        public init(
            tokenEfficientTools: Bool = false,
            extendedThinking: Bool = false,
            interleavedThinking: Bool = false,
            mcpClient: Bool = false
        ) {
            self.tokenEfficientTools = tokenEfficientTools
            self.extendedThinking = extendedThinking
            self.interleavedThinking = interleavedThinking
            self.mcpClient = mcpClient
        }
        
        public static let none = BetaConfiguration()
        public static let all = BetaConfiguration(
            tokenEfficientTools: true,
            extendedThinking: true,
            interleavedThinking: true,
            mcpClient: true
        )
    }
    
    private let betaConfiguration: BetaConfiguration
    
    // MARK: - Initialization
    
    /// Initialize the Anthropic service with configuration options
    ///
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
            apiKey: nil,
            betaConfiguration: betaConfiguration,
            maxRetries: maxRetries
        )
    }
    
    /// Initialize with all beta features enabled
    public convenience init(
        apiKey: String,
        withAllBetaFeatures: Bool = false
    ) {
        self.init(
            apiKey: apiKey,
            betaConfiguration: withAllBetaFeatures ? .all : .none
        )
    }
    
    /// Initialize with MCP support enabled
    public convenience init(
        apiKey: String,
        withMCPSupport: Bool = true
    ) {
        self.init(
            apiKey: apiKey,
            betaConfiguration: BetaConfiguration(mcpClient: withMCPSupport)
        )
    }
    
    // MARK: - Headers Management
    
    private var authorizationHeaders: HTTPHeaders {
        var headers = HTTPHeaders()
        // Anthropic uses x-api-key header, not Authorization Bearer
        headers.add(name: "x-api-key", value: apiKey)
        headers.add(.contentType("application/json"))
        headers.add(name: "anthropic-version", value: "2023-06-01")
        
        // Add beta feature headers
        var betaHeaders: [String] = []
        
        if betaConfiguration.tokenEfficientTools {
            betaHeaders.append("token-efficient-tools-2025-02-19")
        }
        
        // Note: Extended thinking is now enabled via the 'thinking' object in request body, not headers
        // if betaConfiguration.extendedThinking {
        //     betaHeaders.append("extended-thinking-2024-12-12")
        // }
        
        if betaConfiguration.interleavedThinking {
            betaHeaders.append("interleaved-thinking-2025-05-14")
        }
        
        if betaConfiguration.mcpClient {
            betaHeaders.append("mcp-client-2025-04-04")
        }
        
        if !betaHeaders.isEmpty {
            headers.add(name: "anthropic-beta", value: betaHeaders.joined(separator: ","))
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
        body: AnthropicMessageRequestBody
    ) async throws -> AnthropicMessageResponseBody {
        
        guard !apiKey.isEmpty else {
            throw LLMError.authenticationError
        }
        
        var enhancedRequest = body
        
        // Apply beta feature configurations
        if betaConfiguration.tokenEfficientTools {
            enhancedRequest.enableTokenEfficientTools = true
        }
        
        // Add thinking configuration for extended thinking
        if betaConfiguration.extendedThinking {
            // Use 1/4 of max_tokens for thinking, with minimum of 1024
            let thinkingBudget = max(1024, enhancedRequest.maxTokens / 4)
            enhancedRequest = AnthropicMessageRequestBody(
                maxTokens: enhancedRequest.maxTokens,
                messages: enhancedRequest.messages,
                model: enhancedRequest.model,
                metadata: enhancedRequest.metadata,
                stopSequences: enhancedRequest.stopSequences,
                stream: enhancedRequest.stream,
                system: enhancedRequest.system,
                temperature: enhancedRequest.temperature,
                toolChoice: enhancedRequest.toolChoice,
                tools: enhancedRequest.tools,
                topK: enhancedRequest.topK,
                topP: enhancedRequest.topP,
                thinking: AnthropicThinkingConfig(budgetTokens: thinkingBudget),
                mcpServers: enhancedRequest.mcpServers
            )
            enhancedRequest.enableTokenEfficientTools = betaConfiguration.tokenEfficientTools
        }
        
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
                    headers: authorizationHeaders
                )
                .validate()
                .serializingDecodable(AnthropicMessageResponseBody.self)
                
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
        body: AnthropicMessageRequestBody
    ) async throws -> AnthropicAsyncChunks {
        
        guard !apiKey.isEmpty else {
            throw LLMError.authenticationError
        }
        
        var enhancedRequest = body
        
        // Apply beta feature configurations
        if betaConfiguration.tokenEfficientTools {
            enhancedRequest.enableTokenEfficientTools = true
        }
        
        // Add thinking configuration for extended thinking
        if betaConfiguration.extendedThinking {
            // Use 1/4 of max_tokens for thinking, with minimum of 1024
            let thinkingBudget = max(1024, enhancedRequest.maxTokens / 4)
            enhancedRequest = AnthropicMessageRequestBody(
                maxTokens: enhancedRequest.maxTokens,
                messages: enhancedRequest.messages,
                model: enhancedRequest.model,
                metadata: enhancedRequest.metadata,
                stopSequences: enhancedRequest.stopSequences,
                stream: enhancedRequest.stream,
                system: enhancedRequest.system,
                temperature: enhancedRequest.temperature,
                toolChoice: enhancedRequest.toolChoice,
                tools: enhancedRequest.tools,
                topK: enhancedRequest.topK,
                topP: enhancedRequest.topP,
                thinking: AnthropicThinkingConfig(budgetTokens: thinkingBudget),
                mcpServers: enhancedRequest.mcpServers
            )
            enhancedRequest.enableTokenEfficientTools = betaConfiguration.tokenEfficientTools
        }
        
        enhancedRequest.stream = true
        
        let endpoint = "\(baseUrl)/messages"
        
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid Anthropic API URL configuration")
        }
        
        // Create URLRequest for streaming
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        
        // Add headers
        for header in authorizationHeaders {
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
        mcpClient: Bool = false
    ) -> AnthropicService {
        let configuration = BetaConfiguration(
            tokenEfficientTools: tokenEfficientTools,
            extendedThinking: extendedThinking,
            interleavedThinking: interleavedThinking,
            mcpClient: mcpClient
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
        
        return """
        AnthropicService Configuration:
        - Base URL: \(baseUrl)
        - Beta Features: \(features.isEmpty ? "none" : features.joined(separator: ", "))
        - Max Retries: \(maxRetries)
        - Retry Delay: \(retryDelay)s
        """
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
            temperature: originalRequest.temperature,
            toolChoice: originalRequest.toolChoice,
            tools: originalRequest.tools,
            topK: originalRequest.topK,
            topP: originalRequest.topP,
            thinking: originalRequest.thinking,
            mcpServers: originalRequest.mcpServers
        )
    }
}



