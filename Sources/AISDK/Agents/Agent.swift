//
//  Agent.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// A class that manages interactions with an AI language model and coordinates tool execution
/// Handles both synchronous and streaming conversations, and manages the execution of tools
public class Agent {
    // MARK: - Properties
    
    private let model: LLMModelProtocol
    public let llm: LLM
    private var tools: [Tool.Type]
    private var state: AgentState = .idle
    
    var messages: [ChatMessage] = []

    private let instructions: String?
    private var callbacks: [AgentCallbacks] = []
    
    /// Callback for state changes, useful for UI updates
    public var onStateChange: ((AgentState) -> Void)?
    
    // Add property to track accumulated metadata during streaming
    private var currentStreamMetadata: [ToolMetadata] = []
    
    // MARK: - Initialization
    
    /// Provider-centric initializer - recommended approach
    /// - Parameters:
    ///   - llm: The LLM provider to use (e.g., OpenAIProvider(), AnthropicService())
    ///   - tools: Array of available tools (default: empty)
    ///   - messages: Initial conversation history (default: empty)
    ///   - instructions: Optional system instructions for the agent's behavior
    public init(
        llm: LLM,
        tools: [Tool.Type] = [],
        messages: [ChatMessage] = [],
        instructions: String? = nil
    ) {
        self.llm = llm
        self.tools = tools
        self.messages = messages
        self.instructions = instructions
        
        // Get model from provider
        if let openAIProvider = llm as? OpenAIProvider {
            self.model = openAIProvider.model
        } else {
            // Fallback model for other providers
            self.model = OpenAIModels.gpt4o
        }
        
        // Register tools with ToolRegistry
        ToolRegistry.registerAll(tools: tools)
        
        // Add system message if instructions are provided
        if let instructions = instructions {
            let systemMessage = ChatMessage(message: .system(content: .text(instructions)))
            self.messages.append(systemMessage)
        }
    }
    
    /// Legacy initializer - maintained for backward compatibility
    /// - Parameters:
    ///   - model: The language model configuration to use
    ///   - tools: Array of available tools (default: empty)
    ///   - messages: Initial conversation history (default: empty)
    ///   - instructions: Optional system instructions for the agent's behavior
    /// - Throws: AgentError if initialization fails
    init(
        model: LLMModel,
        tools: [Tool.Type] = [],
        messages: [ChatMessage] = [], 
        instructions: String? = nil
    ) {
        self.tools = tools
        self.messages = messages
        self.instructions = instructions
        
        // Convert legacy model to protocol
        self.model = model.toProtocol()
        
        // Register tools with ToolRegistry
        ToolRegistry.registerAll(tools: tools)
        
        // Initialize appropriate LLM based on model
        self.llm = OpenAIProvider(apiKey: model.apiKey ?? " ")
        
        // Add system message if instructions are provided
        if let instructions = instructions {
            let systemMessage = ChatMessage(message: .system(content: .text(instructions)))
            self.messages.append(systemMessage)
        }
    }
    
    // Helper method to convert ChatMessages to Messages for API calls
    private func convertToAPIMessages() -> [Message] {
        return messages.map { $0.message }
    }
    
    // MARK: - Public Methods
    
    /// Sends a message to the agent and waits for a complete response
    /// This is a synchronous version that returns a single message
    /// - Parameter content: The user's message
    /// - Returns: The agent's response message
    /// - Throws: Various errors related to API calls or tool execution
    public func send(_ content: String) async throws -> ChatMessage {
        setState(.thinking)
        
        let userMessage = ChatMessage(message: .user(content: .text(content)))
        
        // Execute message received callback
        let receivedResult = await executeCallbacks { await $0.onMessageReceived(message: userMessage.message) }
        switch receivedResult {
        case .cancel:
            setState(.idle)
            throw AgentError.operationCancelled
        case .replace(let message):
            let chatMessage = ChatMessage(message: message)
            messages.append(chatMessage)
            return chatMessage
        case .continue:
            messages.append(userMessage)
        }
        
        // Create chat completion request using converted messages
        let request = ChatCompletionRequest(
            model: model.name,
            messages: convertToAPIMessages(),
            tools: tools.map { $0.jsonSchema() },
            toolChoice: (model.hasCapability(.tools) || model.hasCapability(.functionCalling)) ? .auto : nil,
            parallelToolCalls: true
        )
        
        // Execute before LLM request callback
        let beforeLLMResult = await executeCallbacks { await $0.onBeforeLLMRequest(messages: convertToAPIMessages()) }
        if case .cancel = beforeLLMResult {
            setState(.idle)
            throw AgentError.operationCancelled
        }
        
        // Get response from LLM
        let response = try await llm.sendChatCompletion(request: request)
        
        guard let choice = response.choices.first else {
            setState(.error(AgentError.invalidToolResponse))
            throw AgentError.invalidToolResponse
        }
        
        // Handle tool calls if present
        if let toolCalls = choice.message.toolCalls {
            return try await handleToolCalls(toolCalls)
        }
        
        // Add assistant's response to conversation
        if let content = choice.message.content {
            let assistantMessage = ChatMessage(message: .assistant(content: .text(content)))
            messages.append(assistantMessage)
            setState(.idle)
            return assistantMessage
        } else {
            setState(.error(AgentError.invalidToolResponse))
            throw AgentError.invalidToolResponse
        }
    }
    
    /// Sends a message to the agent and receives streaming responses
    /// Useful for real-time UI updates and handling tool executions
    /// - Parameter content: The user's message
    /// - Returns: An async stream of response messages
    public func sendStream(_ message: ChatMessage, requiredTool: String? = nil) -> AsyncThrowingStream<ChatMessage, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                // Reset metadata at start of new stream
                currentStreamMetadata = []
                
                // Execute message received callback
                let receivedResult = await executeCallbacks { await $0.onMessageReceived(message: message.message) }
                switch receivedResult {
                case .cancel:
                    setState(.idle)
                    continuation.finish(throwing: AgentError.operationCancelled)
                    return
                case .replace(let newMessage):
                    let chatMessage = ChatMessage(message: newMessage)
                    messages.append(chatMessage)
                    continuation.yield(chatMessage)
                    continuation.finish()
                    return
                case .continue:
                    messages.append(message)
                }
                
                setState(.thinking)
                
                // Set toolChoice based on requiredTool parameter
                let toolChoice: ToolChoice
                if let requiredTool = requiredTool, !requiredTool.isEmpty {
                    toolChoice = .function(ToolChoice.FunctionChoice(name: requiredTool))
                } else {
                    toolChoice = .auto
                }
                
                let request = ChatCompletionRequest(
                    model: model.name,
                    messages: convertToAPIMessages(),
                    stream: true,
                    tools: tools.map { $0.jsonSchema() },
                    toolChoice: toolChoice,
                    parallelToolCalls: true
                )
                
                do {
                    var responseContent = ""
                    var currentToolCall: (id: String?, name: String?, arguments: String)?
                    
                    for try await chunk in try await llm.sendChatCompletionStream(request: request) {
                        // Add debug logging
                        // print("🔍 Received chunk with \(chunk.choices.count) choices")
                        
                        let chunkResult = await executeCallbacks { await $0.onStreamChunk(chunk: .assistant(content: .text(chunk.choices.first?.delta.content ?? ""))) }
                        if case .cancel = chunkResult {
                            setState(.idle)
                            continuation.finish(throwing: AgentError.operationCancelled)
                            return
                        }
                        
                        for choice in chunk.choices {
                            if let toolCalls = choice.delta.toolCalls {
                                // print("⚙️ Received tool calls in chunk: \(toolCalls.count)")
                                for toolCall in toolCalls {
                                    if let function = toolCall.function {
                                        // Create or update tool call data using local variables
                                        var updatedToolCall = currentToolCall ?? (toolCall.id, function.name, "")
                                        
                                        // Update the fields
                                        if let id = toolCall.id {
                                            updatedToolCall.0 = id
                                        }
                                        if let name = function.name {
                                            updatedToolCall.1 = name
                                        }
                                        if let args = function.arguments {
                                            updatedToolCall.2 = (updatedToolCall.2) + args
                                        }
                                        
                                        // Assign back to currentToolCall
                                        currentToolCall = updatedToolCall
                                        
                                        
                                    }
                                }
                            }
                            
                            // Execute tool when we get the finish reason
                            if (choice.finishReason == "tool_calls" || choice.finishReason == "stop"),
                               let toolCall = currentToolCall,
                               !toolCall.2.isEmpty {
                                // print("🛠️ Executing tool with finish reason '\(choice.finishReason ?? "none")': \(toolCall.1 ?? "unknown") with arguments: \(toolCall.2)")
                                
                                do {
                                    setState(.executingTool(toolCall.1 ?? "unknown"))
                                    
                                    // First, create and add the assistant message with tool calls
                                    let assistantMessage = ChatMessage(message: .assistant(content: .text(""), toolCalls: [
                                        ChatCompletionResponse.ToolCall(
                                            id: toolCall.0 ?? "",
                                            type: "function",
                                            function: .init(name: toolCall.1 ?? "", arguments: toolCall.2)
                                        )
                                    ]))
                                    messages.append(assistantMessage)
                                    continuation.yield(assistantMessage)

                                    // print("----- :fire:  TOOL ARGUMENTS : \(toolCall.2) -----")
                                    // Execute tool and get response with metadata
                                    let (toolResponse, metadata) = try await executeToolCall(
                                        name: toolCall.1 ?? "",
                                        arguments: toolCall.2,
                                        toolCallId: toolCall.0 ?? ""
                                    )
                                    
                                    // Accumulate metadata if present
                                    if let metadata = metadata {
                                        currentStreamMetadata.append(metadata)
                                    }
                                    
                                    // Add tool response to conversation with metadata
                                    toolResponse.metadata = metadata
                                    messages.append(toolResponse)
                                    continuation.yield(toolResponse)
                                    
                                    // Check if tool requests direct response
                                    guard let toolType = tools.first(where: { $0.init().name == toolCall.1 }),
                                          !toolType.init().returnToolResponse else {
                                        // Add an assistant message with the tool response and metadata
                                        if case .tool(let content, _, _) = toolResponse.message {
                                            let finalMessage = ChatMessage(message: .assistant(content: .text(content)))
                                            finalMessage.metadata = currentStreamMetadata.last
                                            messages.append(finalMessage)
                                            continuation.yield(finalMessage)
                                        }
                                        setState(.idle)
                                        continuation.finish()
                                        return
                                    }
                                    
                                    // Get AI's interpretation
                                    setState(.responding)
                                    
                                    let finalRequest = ChatCompletionRequest(
                                        model: model.name,
                                        messages: convertToAPIMessages(),
                                        stream: true,  // Enable streaming for final response
                                        tools: tools.map { $0.jsonSchema() },
                                        toolChoice: (model.hasCapability(.tools) || model.hasCapability(.functionCalling)) ? .auto : nil,
                                        parallelToolCalls: true
                                    )
                                    
                                    // Stream the final response
                                    var finalResponseContent = ""
                                    for try await chunk in try await llm.sendChatCompletionStream(request: finalRequest) {
                                        for choice in chunk.choices {
                                            if let content = choice.delta.content {
                                                finalResponseContent += content
                                                if !content.isEmpty {
                                                    setState(.responding)
                                                    // Create or update streaming message
                                                    let streamingMessage = ChatMessage(message: .assistant(content: .text(finalResponseContent)))
                                                    streamingMessage.isPending = true
                                                    streamingMessage.metadata = toolResponse.metadata
                                                    
                                                    // Update existing message or add new one
                                                    if let lastIndex = messages.lastIndex(where: { $0.isPending }) {
                                                        messages[lastIndex] = streamingMessage
                                                    } else {
                                                        messages.append(streamingMessage)
                                                    }
                                                    continuation.yield(streamingMessage)
                                                }
                                            }
                                        }
                                    }
                                    
                                    // When streaming is complete, attach accumulated metadata to final message
                                    if !finalResponseContent.isEmpty {
                                        let finalMessage = ChatMessage(message: .assistant(content: .text(finalResponseContent)))
                                        finalMessage.metadata = toolResponse.metadata
                                        messages.append(finalMessage)
                                    }
                                    
                                    setState(.idle)
                                    currentToolCall = nil
                                    continuation.finish()
                                    return
                                    
                                } catch {
                                    
                                    currentStreamMetadata = [] // Reset on error
                                    setState(.error(AgentError(from: error)))
                                    throw AISDKError.streamError("Tool execution failed: \(error.localizedDescription)")
                                }
                            }
                            
                            // Handle normal content streaming
                            if let content = choice.delta.content {
                                responseContent += content
                                if !content.isEmpty {
                                    setState(.responding)
                                    // Create or update streaming message
                                    let streamingMessage = ChatMessage(message: .assistant(content: .text(responseContent)))
                                    streamingMessage.isPending = true
                                    
                                    // Update existing message or add new one
                                    if let lastIndex = messages.lastIndex(where: { $0.isPending }) {
                                        messages[lastIndex] = streamingMessage
                                    } else {
                                        messages.append(streamingMessage)
                                    }
                                    continuation.yield(streamingMessage)
                                }
                            }
                        }
                    }
                    
                    // Only add non-empty final messages
                    if !responseContent.isEmpty {
                        let finalMessage = ChatMessage(message: .assistant(content: .text(responseContent)))
                        finalMessage.metadata = currentStreamMetadata.last
                        messages.append(finalMessage)
                    }
                    
                    setState(.idle)
                    continuation.finish()
                    
                } catch {
                    currentStreamMetadata = [] // Reset on error
                    print("❌ Streaming error: \(error.localizedDescription)")
                    setState(.error(AgentError(from: error)))
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Updates the agent's message history
    /// - Parameter messages: The new message history to use
    public func setMessages(_ messages: [ChatMessage]) {
        self.messages = messages
        
        // Reset metadata tracker when setting new messages
        for callback in callbacks {
            if let tracker = callback as? MetadataTracker {
                tracker.reset()
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Updates the agent's state and notifies observers
    private func setState(_ newState: AgentState) {
        state = newState
        onStateChange?(newState)
    }
    
    /// Handles the execution of one or more tool calls from the LLM
    /// - Parameter toolCalls: Array of tool calls to execute
    /// - Returns: The final response message after tool execution
    /// - Throws: Errors related to tool execution or invalid responses
    private func handleToolCalls(_ toolCalls: [ChatCompletionResponse.ToolCall]) async throws -> ChatMessage {
        var toolResponses: [String] = []
        
        // First, add the assistant's message with the tool calls
        messages.append(ChatMessage(message: .assistant(content: .text(""), toolCalls: toolCalls)))
        
        for toolCall in toolCalls {
            guard let function = toolCall.function else {
                let error = AgentError.toolExecutionFailed("Invalid tool call: missing function")
                setState(.error(error))
                throw error
            }
            
            // Use ToolRegistry instead of direct array search
            guard let toolType = ToolRegistry.toolType(forName: function.name) else {
                let error = AgentError.toolExecutionFailed("Tool not found: \(function.name)")
                setState(.error(error))
                throw error
            }
            
            // Execute before tool execution callback
            let beforeToolResult = await executeCallbacks { 
                await $0.onBeforeToolExecution(name: function.name, arguments: function.arguments)
            }
            if case .cancel = beforeToolResult {
                setState(.idle)
                throw AgentError.operationCancelled
            }
            
            setState(.executingTool(function.name))
            
            do {
                var tool = toolType.init()
                
                // Parse arguments with better error handling
                let argumentsData = function.arguments.data(using: .utf8) ?? Data()
                
                print("----- :fire: TOOL CALL INFO -----")
                print("Tool Name: \(function.name)")
                print("Raw Arguments: \(function.arguments)")
                print("Arguments Data: \(argumentsData)")
                
                // Validate and set parameters
                tool = try tool.validateAndSetParameters(argumentsData)
                
                // Log tool state after parameter setting
                print("Tool Parameters After Setting:")
                let mirror = Mirror(reflecting: tool)
                for child in mirror.children {
                    print("\(child.label ?? "unknown"): \(child.value)")
                }
                print("---------------------------")
                
                // Execute tool with logging
                let (response, metadata) = try await tool.execute()
                
                // Add tool response to messages and update metadata tracker
                let message = ChatMessage(message: .tool(content: response, name: function.name, toolCallId: toolCall.id))
                message.metadata = metadata
                messages.append(message)
                
                // Update metadata in callbacks
                for callback in callbacks {
                    if let tracker = callback as? MetadataTracker {
                        tracker.setMetadata(metadata, forToolCallId: toolCall.id)
                    }
                }
                
                toolResponses.append(response)
                
                // If tool requests direct response, return immediately
                if tool.returnToolResponse {
                    setState(.idle)
                    let finalMessage = ChatMessage(message: .assistant(content: .text(response)))
                    return finalMessage
                }
                
                // Add after successful tool execution
                let afterToolResult = await executeCallbacks {
                    await $0.onAfterToolExecution(name: function.name, result: response)
                }
                if case .cancel = afterToolResult {
                    setState(.idle)
                    throw AgentError.operationCancelled
                }
            } catch {
                let errorMessage = "Failed to execute tool \(function.name): \(error.localizedDescription)"
                let agentError = AgentError.toolExecutionFailed(errorMessage)
                setState(.error(agentError))
                throw agentError
            }
        }
        
        // Get final response after tool execution
        setState(.thinking)
        
        let finalRequest = ChatCompletionRequest(
            model: model.name,
            messages: convertToAPIMessages(),
            tools: tools.map { $0.jsonSchema() },
            toolChoice: (model.hasCapability(.tools) || model.hasCapability(.functionCalling)) ? .auto : nil,
            parallelToolCalls: true
        )
        
        do {
            let finalResponse = try await llm.sendChatCompletion(request: finalRequest)
            
            guard let choice = finalResponse.choices.first,
                  let content = choice.message.content else {
                throw AgentError.invalidToolResponse
            }
            
            let assistantMessage = ChatMessage(message: .assistant(content: .text(content)))
            messages.append(assistantMessage)
            setState(.idle)
            
            return assistantMessage
        } catch {
            throw error
        }
    }
    
    /// Executes a single tool call with the given parameters
    /// - Parameters:
    ///   - name: Name of the tool to execute
    ///   - arguments: JSON string of arguments for the tool
    ///   - toolCallId: Unique identifier for this tool call
    /// - Returns: A tuple containing the message and optional metadata
    /// - Throws: Errors if tool execution fails
    private func executeToolCall(name: String, arguments: String, toolCallId: String) async throws -> (ChatMessage, ToolMetadata?) {
        // Use ToolRegistry instead of direct array search
        guard let toolType = ToolRegistry.toolType(forName: name) else {
            let error = AgentError.toolExecutionFailed("Tool not found: \(name)")
            setState(.error(error))
            throw error
        }
        
        do {
            var tool = toolType.init()
            let argumentsData = arguments.data(using: .utf8) ?? Data()
            
            print("----- :fire: TOOL CALL INFO -----")
            print("Tool Name: \(name)")
            print("Raw Arguments: \(arguments)")
            print("Arguments Data: \(argumentsData)")
            
            // Print the tool's JSON schema
            print("Tool JSON Schema:")
            let schema = toolType.jsonSchema()
            if let schemaData = try? JSONEncoder().encode(schema),
               let schemaString = String(data: schemaData, encoding: .utf8) {
                print(schemaString)
            }
            
            // Create tool and set parameters
            tool = try tool.validateAndSetParameters(argumentsData)
            
            // Log tool state after parameter setting
            print("Tool Parameters After Setting:")
            print("---------------------------")
            
            // Execute tool with updated parameters
            let (response, metadata) = try await tool.execute()
            
            // Create message
            let message = ChatMessage(message: .tool(content: response, name: name, toolCallId: toolCallId))
            message.metadata = metadata
            
            // Update metadata in callbacks
            for callback in callbacks {
                if let tracker = callback as? MetadataTracker {
                    tracker.setMetadata(metadata, forToolCallId: toolCallId)
                }
            }
            
            // Notify callbacks
            let afterToolResult = await executeCallbacks {
                await $0.onAfterToolExecution(name: name, result: response)
            }
            if case .cancel = afterToolResult {
                setState(.idle)
                throw AgentError.operationCancelled
            }
            
            return (message, metadata)
        } catch {
            let agentError = error as? AIError ?? AgentError.toolExecutionFailed("Tool execution failed: \(error.localizedDescription)")
            setState(.error(agentError))
            throw agentError
        }
    }
    
    /// Registers a callback handler
    /// - Parameter callback: The callback handler to register
    public func addCallbacks(_ callback: AgentCallbacks) {
        callbacks.append(callback)
    }
    
    /// Removes a callback handler
    /// - Parameter callback: The callback handler to remove
    public func removeCallbacks(_ callback: AgentCallbacks) {
        callbacks.removeAll { $0 === callback }
    }
    
    /// Executes a callback operation
    /// - Parameter operation: The callback operation to execute
    /// - Returns: The result of the callback operation
    private func executeCallbacks(_ operation: (AgentCallbacks) async -> CallbackResult) async -> CallbackResult {
        for callback in callbacks {
            let result = await operation(callback)
            switch result {
            case .cancel, .replace:
                return result
            case .continue:
                continue
            }
        }
        return .continue
    }
}

