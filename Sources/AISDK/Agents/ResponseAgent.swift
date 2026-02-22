//
//  ResponseAgent.swift
//  AISDK
//
//  Created by AISDK on 01/01/25.
//

import Foundation

/// Background task configuration for enhanced task processing
public struct BackgroundTaskConfiguration {
    let maxWaitTime: TimeInterval
    let pollInterval: TimeInterval
    let enableReasoning: Bool
    let enableProgressTracking: Bool
    let cancellationToken: CancellationToken?
    let onProgress: ((TaskProgress) -> Void)?
    let onStatusChange: ((ResponseAgentState.BackgroundTaskStatus) -> Void)?
    
    public init(
        maxWaitTime: TimeInterval = 600,
        pollInterval: TimeInterval = 5,
        enableReasoning: Bool = true,
        enableProgressTracking: Bool = true,
        cancellationToken: CancellationToken? = nil,
        onProgress: ((TaskProgress) -> Void)? = nil,
        onStatusChange: ((ResponseAgentState.BackgroundTaskStatus) -> Void)? = nil
    ) {
        self.maxWaitTime = maxWaitTime
        self.pollInterval = pollInterval
        self.enableReasoning = enableReasoning
        self.enableProgressTracking = enableProgressTracking
        self.cancellationToken = cancellationToken
        self.onProgress = onProgress
        self.onStatusChange = onStatusChange
    }
    
    public static let `default` = BackgroundTaskConfiguration()
    public static let detailed = BackgroundTaskConfiguration(
        maxWaitTime: 1200,
        enableReasoning: true,
        enableProgressTracking: true
    )
}

/// Task progress information
public struct TaskProgress {
    public let percentage: Double
    public let currentStep: String?
    public let estimatedTimeRemaining: TimeInterval?
    
    public init(percentage: Double, currentStep: String? = nil, estimatedTimeRemaining: TimeInterval? = nil) {
        self.percentage = percentage
        self.currentStep = currentStep
        self.estimatedTimeRemaining = estimatedTimeRemaining
    }
}

/// Cancellation token for background tasks
public class CancellationToken {
    private var _isCancelled = false
    
    public var isCancelled: Bool {
        return _isCancelled
    }
    
    public func cancel() {
        _isCancelled = true
    }
}

/// Enhanced background task result
public struct BackgroundTaskResult {
    public let response: ResponseLegacyChatMessage
    public let taskId: String
    public let duration: TimeInterval
    public let reasoning: [ReasoningStep]?
    public let toolExecutions: [ResponseToolExecutionResult]
    public let status: ResponseStatus
}

/// Reasoning step information
public struct ReasoningStep {
    public let content: String
    public let effort: String?
    public let timestamp: Date
    
    public init(content: String, effort: String? = nil, timestamp: Date = Date()) {
        self.content = content
        self.effort = effort
        self.timestamp = timestamp
    }
}

/// Tool execution result information
public struct ResponseToolExecutionResult {
    public let toolName: String
    public let arguments: String
    public let result: String
    public let duration: TimeInterval
    public let metadata: ToolMetadata?
    
    public init(toolName: String, arguments: String, result: String, duration: TimeInterval, metadata: ToolMetadata? = nil) {
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
        self.duration = duration
        self.metadata = metadata
    }
}

/// ResponseAgent - 100% OpenAI Response API native agent implementation
/// Provides multimodal support, built-in tools, background processing, and clean developer experience
public class ResponseAgent {
    
    // MARK: - Properties
    
    private let provider: OpenAIProvider
    private let tools: [Tool.Type]
    private let builtInTools: [ResponseBuiltInTool]
    private let mcpServers: [MCPServerConfiguration]
    private let instructions: String?
    private let model: String
    
    /// Current agent state
    public private(set) var state: ResponseAgentState = .idle
    
    /// Callback for state changes
    public var onStateChange: ((ResponseAgentState) -> Void)?
    
    /// In-memory conversation history
    public private(set) var messages: [AIInputMessage] = []
    
    /// Current conversation ID for session management
    public private(set) var conversationId: String = UUID().uuidString
    
    /// Last response ID for conversation continuation
    private var lastResponseId: String?
    
    // MARK: - Initialization
    
    /// Initialize ResponseAgent with OpenAI provider and optional tools
    /// - Parameters:
    ///   - provider: OpenAI provider configured for Response API
    ///   - tools: Custom tools to register (default: empty)
    ///   - builtInTools: Built-in Response API tools to enable (default: all available)
    ///   - mcpServers: MCP servers to register (default: empty)
    ///   - instructions: System instructions for the agent
    ///   - model: Model to use (default: gpt-4o)
    public init(
        provider: OpenAIProvider,
        tools: [Tool.Type] = [],
        builtInTools: [ResponseBuiltInTool] = [.webSearchPreview, .codeInterpreter, .imageGeneration(), .fileSearch(vectorStoreId: "")],
        mcpServers: [MCPServerConfiguration] = [],
        instructions: String? = nil,
        model: String = "gpt-4o"
    ) throws {
        // Validate provider
        guard !provider.apiKey.isEmpty else {
            throw ResponseAgentError.invalidProvider("OpenAI provider must have valid API key")
        }
        
        self.provider = provider
        self.tools = tools
        self.builtInTools = builtInTools
        self.mcpServers = mcpServers
        self.instructions = instructions
        self.model = model
        
        // Validate tool conflicts
        try validateToolConflicts()
        
        // Register custom tools
        ToolRegistry.registerAll(tools: tools)
        
        // Add system instructions if provided
        if let instructions = instructions {
            self.messages.append(.system(instructions))
        }
    }
    
    // MARK: - Main Send Method
    
    /// Send a message to the agent with streaming control
    /// - Parameters:
    ///   - message: The input message (supports multimodal content)
    ///   - streaming: Enable streaming responses (default: false)
    /// - Returns: AsyncThrowingStream of ResponseLegacyChatMessage responses
    public func send(
        _ message: AIInputMessage,
        streaming: Bool = false
    ) -> AsyncThrowingStream<ResponseLegacyChatMessage, Error> {
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Validate agent state
                    try validateLegacyAgentState()
                    
                    // Add user message to conversation
                    messages.append(message)
                    
                    // Update state
                    setState(.processing)
                    
                    if streaming {
                        try await processStreamingResponse(message, continuation: continuation)
                    } else {
                        try await processNonStreamingResponse(message, continuation: continuation)
                    }
                    
                } catch {
                    setState(.error(ResponseAgentError.from(error)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Send text message with streaming control
    /// - Parameters:
    ///   - text: The text message to send
    ///   - streaming: Enable streaming responses (default: false)
    /// - Returns: AsyncThrowingStream of ResponseLegacyChatMessage responses
    public func send(
        _ text: String,
        streaming: Bool = false
    ) -> AsyncThrowingStream<ResponseLegacyChatMessage, Error> {
        return send(.user(text), streaming: streaming)
    }
    
    /// Send multimodal message with streaming control
    /// - Parameters:
    ///   - contentParts: Array of content parts (text, images, etc.)
    ///   - streaming: Enable streaming responses (default: false)
    /// - Returns: AsyncThrowingStream of ResponseLegacyChatMessage responses
    public func send(
        _ contentParts: [AIContentPart],
        streaming: Bool = false
    ) -> AsyncThrowingStream<ResponseLegacyChatMessage, Error> {
        return send(.user(contentParts), streaming: streaming)
    }
    
    // MARK: - Background Processing
    
    /// Execute a task in the background with enhanced configuration and tracking
    /// - Parameters:
    ///   - message: The input message for background processing
    ///   - configuration: Configuration for background task processing
    /// - Returns: Enhanced background task result with detailed information
    public func task(
        _ message: AIInputMessage,
        configuration: BackgroundTaskConfiguration = .default
    ) async throws -> BackgroundTaskResult {
        
        try validateLegacyAgentState()
        
        // Check cancellation before starting
        if configuration.cancellationToken?.isCancelled == true {
            throw ResponseAgentError.operationCancelled
        }
        
        // Add user message
        messages.append(message)
        
        let taskId = UUID().uuidString
        setState(.backgroundProcessing(taskId: taskId, status: .queued))
        configuration.onStatusChange?(.queued)
        
        let startTime = Date()
        var toolExecutions: [ResponseToolExecutionResult] = []
        var reasoningSteps: [ReasoningStep] = []
        
        do {
            // Create enhanced background request
            let request = try buildEnhancedBackgroundRequest(
                message: message,
                configuration: configuration
            )
            
            setState(.backgroundProcessing(taskId: taskId, status: .inProgress(progress: nil)))
            configuration.onStatusChange?(.inProgress(progress: nil))
            
            // Start background processing
            let initialResponse = try await provider.createResponse(request: request)
            
            // If not processing in background, return immediately
            guard initialResponse.status.isProcessing else {
                setState(.idle)
                let finalResponse = try convertToChat(initialResponse)
                
                return BackgroundTaskResult(
                    response: finalResponse,
                    taskId: taskId,
                    duration: Date().timeIntervalSince(startTime),
                    reasoning: reasoningSteps,
                    toolExecutions: toolExecutions,
                    status: initialResponse.status
                )
            }
            
            // Enhanced polling with progress tracking and cancellation support
            var pollAttempts = 0
            
            while Date().timeIntervalSince(startTime) < configuration.maxWaitTime {
                // Check cancellation
                if configuration.cancellationToken?.isCancelled == true {
                    throw ResponseAgentError.operationCancelled
                }
                
                setState(.polling(taskId: taskId, attempts: pollAttempts))
                
                try await Task.sleep(nanoseconds: UInt64(configuration.pollInterval * 1_000_000_000))
                
                let polledResponse = try await provider.retrieveResponse(id: initialResponse.id)
                
                // Extract reasoning and tool execution information
                if configuration.enableReasoning {
                    reasoningSteps.append(contentsOf: extractReasoningSteps(from: polledResponse))
                }
                
                toolExecutions.append(contentsOf: extractToolExecutions(from: polledResponse))
                
                // Update progress if available
                if configuration.enableProgressTracking {
                    let progress = estimateProgress(
                        polledResponse: polledResponse,
                        startTime: startTime,
                        maxWaitTime: configuration.maxWaitTime
                    )
                    configuration.onProgress?(progress)
                    
                    setState(.backgroundProcessing(taskId: taskId, status: .inProgress(progress: progress.percentage)))
                }
                
                // Check for completion
                if polledResponse.status == .completed {
                    setState(.backgroundProcessing(taskId: taskId, status: .completing))
                    configuration.onStatusChange?(.completing)
                    
                    setState(.idle)
                    let finalResponse = try convertToChat(polledResponse)
                    
                    return BackgroundTaskResult(
                        response: finalResponse,
                        taskId: taskId,
                        duration: Date().timeIntervalSince(startTime),
                        reasoning: reasoningSteps,
                        toolExecutions: toolExecutions,
                        status: polledResponse.status
                    )
                }
                
                if polledResponse.status == .failed || polledResponse.status == .cancelled {
                    throw ResponseAgentError.backgroundTaskFailed(polledResponse.error?.message ?? "Unknown error")
                }
                
                pollAttempts += 1
            }
            
            throw ResponseAgentError.backgroundTaskTimeout(initialResponse.id)
            
        } catch {
            setState(.error(ResponseAgentError.from(error)))
            throw error
        }
    }
    
    /// Execute text task in background with enhanced configuration
    /// - Parameters:
    ///   - text: The text message for background processing
    ///   - configuration: Configuration for background task processing
    /// - Returns: Enhanced background task result with detailed information
    public func task(
        _ text: String,
        configuration: BackgroundTaskConfiguration = .default
    ) async throws -> BackgroundTaskResult {
        return try await task(.user(text), configuration: configuration)
    }
    
    // MARK: - State Management
    
    /// Reset conversation history
    public func resetConversation() {
        messages = []
        conversationId = UUID().uuidString
        lastResponseId = nil
        
        // Re-add system instructions if present
        if let instructions = instructions {
            messages.append(.system(instructions))
        }
    }
    
    /// Set conversation messages
    /// - Parameter messages: New conversation history
    public func setMessages(_ messages: [AIInputMessage]) {
        self.messages = messages
    }
    
    /// Get current conversation messages
    /// - Returns: Array of current conversation messages
    public func getMessages() -> [AIInputMessage] {
        return messages
    }
    
    // MARK: - Private Methods
    
    /// Validate agent state before processing
    private func validateLegacyAgentState() throws {
        switch state {
        case .processing, .backgroundProcessing:
            throw ResponseAgentError.agentBusy
        case .error(let error):
            throw error
        default:
            break
        }
    }
    
    /// Validate tool conflicts between custom and built-in tools
    private func validateToolConflicts() throws {
        let customToolNames = Set(tools.map { $0.init().name })
        let builtInToolNames = Set(builtInTools.map { $0.name })
        
        let conflicts = customToolNames.intersection(builtInToolNames)
        if !conflicts.isEmpty {
            let first = conflicts.first!
            throw ResponseAgentError.toolConflict(
                customTool: first,
                builtInTool: first
            )
        }
    }
    
    /// Update agent state and notify observers
    private func setState(_ newState: ResponseAgentState) {
        state = newState
        onStateChange?(newState)
    }
    
    /// Process streaming response with enhanced state tracking
    private func processStreamingResponse(
        _ message: AIInputMessage,
        continuation: AsyncThrowingStream<ResponseLegacyChatMessage, Error>.Continuation
    ) async throws {
        
        setState(.initializing)
        
        let request = try buildResponseRequest(message: message, streaming: true)
        let stream = provider.createResponseStream(request: request)
        
        setState(.processing)
        
        var responseContent = ""
        
        for try await chunk in stream {
            // Handle different chunk types by examining properties
            if let text = chunk.delta?.outputText {
                // Text delta streaming
                responseContent += text
                setState(.streamingResponse(contentType: .text))
                
                // Create streaming message
                let responseLegacyChatMessage = ResponseLegacyChatMessage(message: .assistant(responseContent))
                responseLegacyChatMessage.isPending = true
                continuation.yield(responseLegacyChatMessage)
            }
            
            // Check for reasoning
            if chunk.delta?.reasoning != nil {
                setState(.reasoning(effort: chunk.delta?.reasoning?.effort))
            }
            
            // Handle completion
            if chunk.status == .completed {
                setState(.completing)
                break
            }
        }
        
        // Finalize response
        if !responseContent.isEmpty {
            let finalMessage = ResponseLegacyChatMessage(message: .assistant(responseContent))
            messages.append(.assistant(responseContent))
            continuation.yield(finalMessage)
        }
        
        setState(.idle)
        continuation.finish()
    }
    
    /// Process non-streaming response with enhanced state tracking
    private func processNonStreamingResponse(
        _ message: AIInputMessage,
        continuation: AsyncThrowingStream<ResponseLegacyChatMessage, Error>.Continuation
    ) async throws {
        
        setState(.initializing)
        
        let request = try buildResponseRequest(message: message, streaming: false)
        
        setState(.processing)
        let response = try await provider.createResponse(request: request)
        
        // Process any function calls in the response
        for output in response.output {
            if case .functionCall(let functionCall) = output {
                setState(.executingTool(functionCall.name, progress: nil))
                
                // Execute custom tool
                let result = try await executeCustomTool(
                    name: functionCall.name,
                    arguments: functionCall.arguments
                )
                
                // Send tool result
                let toolMessage = ResponseLegacyChatMessage(
                    message: .tool(result.response, callId: functionCall.id, name: functionCall.name),
                    metadata: result.metadata
                )
                continuation.yield(toolMessage)
            }
        }
        
        setState(.completing)
        
        // Send final response
        let finalMessage = try convertToChat(response)
        continuation.yield(finalMessage)
        
        setState(.idle)
        continuation.finish()
    }
    
    /// Build ResponseRequest for the Response API
    private func buildResponseRequest(
        message: AIInputMessage,
        streaming: Bool = false,
        background: Bool = false
    ) throws -> ResponseRequest {
        
        // Convert tools to ResponseTool format
        let responseTools: [ResponseTool] = builtInTools.map { $0.toResponseTool() } +
                                   tools.map { .function($0.jsonSchema().function!) } +
                                   mcpServers.map { .mcp(serverLabel: $0.serverLabel, serverUrl: $0.serverUrl, requireApproval: $0.requireApproval.rawValue) }
        
        // Build input from conversation messages
        let input: ResponseInput = .items(messages.map { $0.toResponseInputItem() })
        
        return ResponseRequest(
            model: model,
            input: input,
            instructions: instructions,
            tools: responseTools.isEmpty ? nil : responseTools,
            toolChoice: nil,
            metadata: ["conversation_id": conversationId],
            temperature: nil,
            topP: nil,
            maxOutputTokens: nil,
            stream: streaming,
            background: background,
            previousResponseId: lastResponseId,
            include: nil,
            store: nil,
            reasoning: nil,
            parallelToolCalls: true,
            serviceTier: nil,
            user: nil,
            truncation: nil,
            text: nil
        )
    }
    
    /// Execute custom tool using the proven 4-line pattern
    private func executeCustomTool(
        name: String,
        arguments: String
    ) async throws -> (response: String, metadata: ToolMetadata?) {
        
        // Line 1: Get tool type from registry
        guard let toolType = ToolRegistry.toolType(forName: name) else {
            throw ResponseAgentError.toolNotFound(name)
        }
        
        // Line 2: Initialize tool
        var tool = toolType.init()
        
        // Line 3: Validate and set parameters
        let argumentsData = arguments.data(using: .utf8) ?? Data()
        tool = try tool.validateAndSetParameters(argumentsData)
        
        // Line 4: Execute tool
        let result = try await tool.execute()
        
        return (response: result.content, metadata: result.metadata)
    }
    
    /// Convert ResponseObject to ResponseLegacyChatMessage
    private func convertToChat(_ response: ResponseObject) throws -> ResponseLegacyChatMessage {
        
        // Store response ID for conversation continuation
        lastResponseId = response.id
        
        // Extract text content
        let textContent = response.outputText ?? ""
        
        // Add assistant message to conversation
        if !textContent.isEmpty {
            messages.append(.assistant(textContent))
        }
        
        // Create ResponseLegacyChatMessage
        let responseLegacyChatMessage = ResponseLegacyChatMessage(
            message: .assistant(textContent),
            metadata: extractMetadata(from: response)
        )
        
        return responseLegacyChatMessage
    }
    
    /// Extract metadata from ResponseObject
    private func extractMetadata(from response: ResponseObject) -> ToolMetadata? {
        // For now, return nil until we implement proper metadata extraction
        // This can be enhanced to extract files and images from response outputs
        return nil
    }
    
    /// Build enhanced background request with configuration
    private func buildEnhancedBackgroundRequest(
        message: AIInputMessage,
        configuration: BackgroundTaskConfiguration
    ) throws -> ResponseRequest {
        
        // Convert tools to ResponseTool format
        let responseTools: [ResponseTool] = builtInTools.map { $0.toResponseTool() } +
                                   tools.map { .function($0.jsonSchema().function!) } +
                                   mcpServers.map { .mcp(serverLabel: $0.serverLabel, serverUrl: $0.serverUrl, requireApproval: $0.requireApproval.rawValue) }
        
        // Build input from conversation messages
        let input: ResponseInput = .items(messages.map { $0.toResponseInputItem() })
        
        // Include reasoning if enabled
        let include = configuration.enableReasoning ? ["reasoning"] : nil
        
        return ResponseRequest(
            model: model,
            input: input,
            instructions: instructions,
            tools: responseTools.isEmpty ? nil : responseTools,
            toolChoice: nil,
            metadata: ["conversation_id": conversationId, "task_id": UUID().uuidString],
            temperature: nil,
            topP: nil,
            maxOutputTokens: nil,
            stream: false,
            background: true,
            previousResponseId: lastResponseId,
            include: include,
            store: nil,
            reasoning: configuration.enableReasoning ? ResponseReasoning(effort: "high", summary: nil) : nil,
            parallelToolCalls: true,
            serviceTier: nil,
            user: nil,
            truncation: nil,
            text: nil
        )
    }
    
    /// Extract reasoning steps from response
    private func extractReasoningSteps(from response: ResponseObject) -> [ReasoningStep] {
        var steps: [ReasoningStep] = []
        
        if let reasoning = response.reasoning {
            let step = ReasoningStep(
                content: reasoning.summary ?? "Reasoning step",
                effort: reasoning.effort
            )
            steps.append(step)
        }
        
        return steps
    }
    
    /// Extract tool executions from response
    private func extractToolExecutions(from response: ResponseObject) -> [ResponseToolExecutionResult] {
        var executions: [ResponseToolExecutionResult] = []
        
        for output in response.output {
            switch output {
            case .functionCall(let functionCall):
                let execution = ResponseToolExecutionResult(
                    toolName: functionCall.name,
                    arguments: functionCall.arguments,
                    result: "Function called", // Simplified for now
                    duration: 0.0, // Would need timing information
                    metadata: nil
                )
                executions.append(execution)
                
            case .webSearchCall(let webSearch):
                let execution = ResponseToolExecutionResult(
                    toolName: "web_search_preview",
                    arguments: webSearch.query ?? "",
                    result: "Web search completed",
                    duration: 0.0,
                    metadata: nil
                )
                executions.append(execution)
                
            case .codeInterpreterCall(let codeInterpreter):
                let execution = ResponseToolExecutionResult(
                    toolName: "code_interpreter",
                    arguments: codeInterpreter.code ?? "",
                    result: "Code executed",
                    duration: 0.0,
                    metadata: nil
                )
                executions.append(execution)
                
            case .imageGenerationCall(let imageGen):
                let execution = ResponseToolExecutionResult(
                    toolName: "image_generation",
                    arguments: imageGen.prompt ?? "",
                    result: "Image generated",
                    duration: 0.0,
                    metadata: nil
                )
                executions.append(execution)
                
            case .mcpApprovalRequest(_):
                let execution = ResponseToolExecutionResult(
                    toolName: "mcp_approval_request",
                    arguments: "MCP approval requested",
                    result: "MCP approval requested",
                    duration: 0.0,
                    metadata: nil
                )
                executions.append(execution)
                
            default:
                break
            }
        }
        
        return executions
    }
    
    /// Estimate progress based on response data
    private func estimateProgress(
        polledResponse: ResponseObject,
        startTime: Date,
        maxWaitTime: TimeInterval
    ) -> TaskProgress {
        let elapsedTime = Date().timeIntervalSince(startTime)
        let timeProgress = elapsedTime / maxWaitTime
        
        // Simple progress estimation based on elapsed time
        // This could be enhanced with actual response content analysis
        let percentage = min(timeProgress * 100, 95.0) // Cap at 95% until completion
        
        let estimatedRemaining = maxWaitTime - elapsedTime
        
        return TaskProgress(
            percentage: percentage,
            currentStep: "Processing background task",
            estimatedTimeRemaining: estimatedRemaining > 0 ? estimatedRemaining : nil
        )
    }
}

// MARK: - ResponseAgentState

/// Enhanced state management for ResponseAgent with granular tracking
public enum ResponseAgentState: Equatable {
    case idle
    case initializing
    case processing
    case reasoning(effort: String?)
    case executingTool(String, progress: Double?)
    case streamingResponse(contentType: StreamingContentType)
    case backgroundProcessing(taskId: String, status: BackgroundTaskStatus)
    case polling(taskId: String, attempts: Int)
    case completing
    case error(ResponseAgentError)
    
    /// Types of content being streamed
    public enum StreamingContentType: Equatable {
        case text
        case multimodal
        case toolExecution
        case reasoning
    }
    
    /// Detailed background task status
    public enum BackgroundTaskStatus: Equatable {
        case queued
        case inProgress(progress: Double?)
        case reasoning
        case executingTools
        case completing
    }
    
    public var isProcessing: Bool {
        switch self {
        case .initializing, .processing, .reasoning, .executingTool, .streamingResponse,
             .backgroundProcessing, .polling, .completing:
            return true
        default:
            return false
        }
    }
    
    public var statusMessage: String {
        switch self {
        case .idle:
            return "Ready"
        case .initializing:
            return "Initializing..."
        case .processing:
            return "Processing..."
        case .reasoning(let effort):
            if let effort = effort {
                return "Reasoning (\(effort))..."
            } else {
                return "Reasoning..."
            }
        case .executingTool(let toolName, let progress):
            if let progress = progress {
                return "Using \(toolName) (\(Int(progress * 100))%)..."
            } else {
                return "Using \(toolName)..."
            }
        case .streamingResponse(let contentType):
            switch contentType {
            case .text:
                return "Streaming response..."
            case .multimodal:
                return "Streaming multimodal content..."
            case .toolExecution:
                return "Streaming tool execution..."
            case .reasoning:
                return "Streaming reasoning..."
            }
        case .backgroundProcessing(let taskId, let status):
            switch status {
            case .queued:
                return "Background task queued (\(taskId.prefix(8)))..."
            case .inProgress(let progress):
                if let progress = progress {
                    return "Background processing (\(Int(progress * 100))%)..."
                } else {
                    return "Background processing..."
                }
            case .reasoning:
                return "Background reasoning..."
            case .executingTools:
                return "Background tool execution..."
            case .completing:
                return "Completing background task..."
            }
        case .polling(let taskId, let attempts):
            return "Polling task \(taskId.prefix(8)) (attempt \(attempts))..."
        case .completing:
            return "Completing..."
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - ResponseLegacyChatMessage

/// ResponseAgent-specific message class
public class ResponseLegacyChatMessage: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let message: AIInputMessage
    public var metadata: ToolMetadata?
    public var isPending: Bool = false
    public var hidden: Bool = false
    
    public init(message: AIInputMessage, metadata: ToolMetadata? = nil, hidden: Bool = false) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
        self.metadata = metadata
        self.hidden = hidden
    }
    
    /// Returns displayable content for the message
    public var displayContent: String {
        return message.textContent
    }
    
    /// Creates a pending message for streaming
    public static func pending(message: AIInputMessage) -> ResponseLegacyChatMessage {
        let chatMessage = ResponseLegacyChatMessage(message: message)
        chatMessage.isPending = true
        return chatMessage
    }
}

extension ResponseLegacyChatMessage: Equatable {
    public static func == (lhs: ResponseLegacyChatMessage, rhs: ResponseLegacyChatMessage) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Built-in Tools Extension

extension ResponseBuiltInTool {
    var name: String {
        switch self {
        case .webSearchPreview:
            return "web_search_preview"
        case .codeInterpreter:
            return "code_interpreter"
        case .imageGeneration:
            return "image_generation"
        case .fileSearch:
            return "file_search"
        case .mcp:
            return "mcp"
        }
    }
}

// MARK: - MCP Types (Backwards Compatibility)

// These types have been moved to Sources/AISDK/MCP/MCPServerConfiguration.swift
// Typealiases are provided here for backwards compatibility.

/// MCP Server Configuration for ResponseAgent
/// - Note: This type has been moved to `AISDK.MCPServerConfiguration`.
///   This typealias is provided for backwards compatibility.
@available(*, deprecated, renamed: "AISDK.MCPServerConfiguration", message: "MCPServerConfiguration has been moved to the MCP module")
public typealias ResponseAgentMCPServerConfiguration = MCPServerConfiguration

/// MCP Approval levels for server interactions
/// - Note: This type has been moved to `AISDK.MCPApprovalLevel`.
///   This typealias is provided for backwards compatibility.
@available(*, deprecated, renamed: "AISDK.MCPApprovalLevel", message: "MCPApprovalLevel has been moved to the MCP module")
public typealias ResponseAgentMCPApprovalLevel = MCPApprovalLevel

/// MCP Tool execution result
public struct MCPToolResult {
    public let toolName: String
    public let serverLabel: String
    public let arguments: String
    public let result: String
    public let duration: TimeInterval
    public let approved: Bool
    
    public init(toolName: String, serverLabel: String, arguments: String, result: String, duration: TimeInterval, approved: Bool) {
        self.toolName = toolName
        self.serverLabel = serverLabel
        self.arguments = arguments
        self.result = result
        self.duration = duration
        self.approved = approved
    }
}
