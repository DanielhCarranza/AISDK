//
//  ExperimentalResearchAgent.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 13/03/25.
//


//
//  ExperimentalResearchAgent.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// A class that manages interactions with an AI language model and coordinates tool execution
/// Handles both synchronous and streaming conversations, and manages the execution of tools
public class ExperimentalResearchAgent {
    // MARK: - Properties
    
    private let model: LLMModelProtocol
    public let llm: LLM
    private var tools: [AITool.Type]
    public var state: AgentState = .idle
    
    public var messages: [ChatMessage] = []

    private let instructions: String?
    private var callbacks: [AgentCallbacks] = []
    
    /// Callback for state changes, useful for UI updates
    public var onStateChange: ((AgentState) -> Void)?
    
    // Add property to track accumulated metadata during streaming
    private var currentStreamMetadata: [ToolMetadata] = []
    
    // Research workflow tracking
    public var isResearchInProgress: Bool = false
    public var researchCompletionToolName: String = "complete_research"
    public let researchToolNames: Set<String> = [
        "start_research",
        "search_medical_evidence",
        "read_evidence",
        "reason_evidence",
        "search_health_profile",
        "complete_research"
    ]
    
    // MARK: - Initialization
    
    /// Provider-centric initializer - recommended approach
    /// - Parameters:
    ///   - llm: The LLM provider to use (e.g., OpenAIProvider(), AnthropicService())
    ///   - tools: Array of available tools (default: empty)
    ///   - messages: Initial conversation history (default: empty)
    ///   - instructions: Optional system instructions for the agent's behavior
    public init(
        llm: LLM,
        tools: [AITool.Type] = [],
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
        
        // Register tools with AIToolRegistry
        AIToolRegistry.registerAll(tools: tools)
        
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
        tools: [AITool.Type] = [],
        messages: [ChatMessage] = [], 
        instructions: String? = nil
    ) {
        self.tools = tools
        self.messages = messages
        self.instructions = instructions
        
        // Convert legacy model to protocol
        self.model = model.toProtocol()
        
        // Register tools with AIToolRegistry
        AIToolRegistry.registerAll(tools: tools)
        
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
            toolChoice: model.hasCapability(.tools) ? .auto : nil
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
    public func sendStream(_ message: ChatMessage) -> AsyncThrowingStream<ChatMessage, Error> {
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
                
                // Start of research workflow streaming
                await streamResearchWorkflow(continuation: continuation)
            }
        }
    }
    
    /// Process the research workflow, continuing tool execution until research is complete
    private func streamResearchWorkflow(continuation: AsyncThrowingStream<ChatMessage, Error>.Continuation) async {
        // Flag to track if we need to continue the workflow
        var continueResearchWorkflow = true
        
        // Continue the research workflow until complete or cancelled
        while continueResearchWorkflow {
            setState(.thinking)
            
            // Create chat completion request using converted messages
            let request = ChatCompletionRequest(
                model: model.name,
                messages: convertToAPIMessages(),
                stream: true,
                tools: tools.map { $0.jsonSchema() },
                toolChoice: model.hasCapability(.tools) ? .auto : nil
            )
            
            // Execute before LLM request callback
            let beforeLLMResult = await executeCallbacks { await $0.onBeforeLLMRequest(messages: convertToAPIMessages()) }
            if case .cancel = beforeLLMResult {
                setState(.idle)
                continuation.finish(throwing: AgentError.operationCancelled)
                return
            }
            
            var responseContent = ""
            var currentToolCall: (id: String?, name: String?, arguments: String)?
            var toolExecuted = false
            var lastToolName: String?
            
            do {
                for try await chunk in try await llm.sendChatCompletionStream(request: request) {
                    let chunkResult = await executeCallbacks { await $0.onStreamChunk(chunk: .assistant(content: .text(chunk.choices.first?.delta.content ?? ""))) }
                    if case .cancel = chunkResult {
                        setState(.idle)
                        continuation.finish(throwing: AgentError.operationCancelled)
                        return
                    }
                    
                    for choice in chunk.choices {
                        if let toolCalls = choice.delta.toolCalls {
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
                                        // Track if this is a research workflow tool
                                        if researchToolNames.contains(name) {
                                            if name == "start_research" {
                                                isResearchInProgress = true
                                            } else if name == researchCompletionToolName {
                                                isResearchInProgress = false
                                            }
                                        }
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
                        if choice.finishReason == "tool_calls",
                           let toolCall = currentToolCall,
                           !toolCall.2.isEmpty {
                            
                            toolExecuted = true
                            lastToolName = toolCall.1
                            
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

                                print("----- :fire:  TOOL ARGUMENTS : \(toolCall.2) -----")
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
                                
                                // Check if the tool executed is complete_research, in which case we should stop the workflow
                                if toolCall.1 == researchCompletionToolName {
                                    isResearchInProgress = false
                                    continueResearchWorkflow = false
                                    
                                    setState(.responding)
                                    
                                    // Instead of just returning the tool response directly,
                                    // make a final call to generate a comprehensive report
                                    let reportPrompt = """
                                    Based on all the research conducted, please generate a comprehensive final report.
                                    
                                    Your report should include:
                                    1. An executive summary of the research question and main findings
                                    2. A structured presentation of all evidence collected
                                    3. Analysis and synthesis of the information
                                    4. Proper citations for all sources
                                    5. Any limitations or gaps in the current research
                                    6. Practical recommendations based on the evidence
                                    
                                    Format the report using markdown with clear sections, bullet points where appropriate, 
                                    and proper formatting for citations.
                                    """
                                    
                                    // Add this prompt as a hidden system message
                                    let promptMessage = ChatMessage(message: .system(content: .text(reportPrompt)))
                                    promptMessage.hidden = true
                                    messages.append(promptMessage)
                                    
                                    // Create final report request
                                    let finalReportRequest = ChatCompletionRequest(
                                        model: model.name,
                                        messages: convertToAPIMessages(),
                                        stream: true
                                    )
                                    
                                    do {
                                        // Stream the final report
                                        var finalReportContent = ""
                                        for try await chunk in try await llm.sendChatCompletionStream(request: finalReportRequest) {
                                            for choice in chunk.choices {
                                                if let content = choice.delta.content {
                                                    finalReportContent += content
                                                    if !content.isEmpty {
                                                        // Create or update streaming message
                                                        let streamingMessage = ChatMessage(message: .assistant(content: .text(finalReportContent)))
                                                        streamingMessage.isPending = true
                                                        streamingMessage.metadata = currentStreamMetadata.last
                                                        
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
                                        
                                        // Finalize the report
                                        if !finalReportContent.isEmpty {
                                            let finalReport = ChatMessage(message: .assistant(content: .text(finalReportContent)))
                                            finalReport.metadata = currentStreamMetadata.last
                                            
                                            // Replace the pending message or add a new one
                                            if let lastIndex = messages.lastIndex(where: { $0.isPending }) {
                                                messages[lastIndex] = finalReport
                                            } else {
                                                messages.append(finalReport)
                                            }
                                            continuation.yield(finalReport)
                                        }
                                    } catch {
                                        print("❌ Error generating final report: \(error.localizedDescription)")
                                        // If report generation fails, at least return the tool response
                                        if case .tool(let content, _, _) = toolResponse.message {
                                            let fallbackMessage = ChatMessage(message: .assistant(content: .text("Sorry, I couldn't generate a comprehensive report. Here's a summary of the research:\n\n\(content)")))
                                            fallbackMessage.metadata = currentStreamMetadata.last
                                            messages.append(fallbackMessage)
                                            continuation.yield(fallbackMessage)
                                        }
                                    }
                                    
                                    setState(.idle)
                                    continuation.finish()
                                    return
                                }
                                
                                // Check if tool requests direct response
                                guard let toolType = tools.first(where: { $0.init().name == toolCall.1 }),
                                      !toolType.init().returnToolResponse else {
                                    if case .tool(let content, _, _) = toolResponse.message {
                                        let responseMessage = ChatMessage(message: .assistant(content: .text(content)))
                                        responseMessage.metadata = currentStreamMetadata.last
                                        messages.append(responseMessage)
                                        continuation.yield(responseMessage)
                                    }
                                    
                                    // If we're in a research workflow, continue
                                    if isResearchInProgress && researchToolNames.contains(toolCall.1 ?? "") {
                                        // Get the next research prompt
                                        let nextPrompt = generateContinueResearchPrompt(lastToolName: toolCall.1)
                                        let promptMessage = ChatMessage(message: .system(content: .text(nextPrompt)))
                                        messages.append(promptMessage)
                                        break
                                    } else {
                                        continueResearchWorkflow = false
                                        setState(.idle)
                                        continuation.finish()
                                        return
                                    }
                                }
                                
                                // Set up for next iteration if in research workflow
                                if isResearchInProgress && researchToolNames.contains(toolCall.1 ?? "") {
                                    // Add a system prompt to continue the research workflow
                                    let continuePrompt = generateContinueResearchPrompt(lastToolName: toolCall.1)
                                    let promptMessage = ChatMessage(message: .system(content: .text(continuePrompt)))
                                    // Add as a hidden message that drives the agent but isn't visible to user
                                    promptMessage.hidden = true
                                    messages.append(promptMessage)
                                    break
                                }
                                
                                // If we're here and executed a tool but not continuing research, we'll stream a final response
                                setState(.responding)
                                
                                let finalRequest = ChatCompletionRequest(
                                    model: model.name,
                                    messages: convertToAPIMessages(),
                                    stream: true  // Enable streaming for final response
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
                                
                                // When streaming is complete, finalize the response
                                if !finalResponseContent.isEmpty {
                                    let finalMessage = ChatMessage(message: .assistant(content: .text(finalResponseContent)))
                                    finalMessage.metadata = toolResponse.metadata
                                    
                                    // Replace the pending message or add a new one
                                    if let lastIndex = messages.lastIndex(where: { $0.isPending }) {
                                        messages[lastIndex] = finalMessage
                                    } else {
                                        messages.append(finalMessage)
                                    }
                                    continuation.yield(finalMessage)
                                }
                                
                                continueResearchWorkflow = false
                                setState(.idle)
                                currentToolCall = nil
                                continuation.finish()
                                return
                                
                            } catch {
                                currentStreamMetadata = [] // Reset on error
                                setState(.error(AgentError(from: error)))
                                continuation.finish(throwing: AISDKError.streamError("Tool execution failed: \(error.localizedDescription)"))
                                return
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
                
                // If we executed a tool, we'll continue in the next iteration
                if toolExecuted && isResearchInProgress {
                    // Continue to the next iteration of the research workflow
                    continue
                }
                
                // If we got here without executing a tool, or research is not in progress
                // Only add non-empty final messages
                if !responseContent.isEmpty {
                    let finalMessage = ChatMessage(message: .assistant(content: .text(responseContent)))
                    finalMessage.isPending = false
                    finalMessage.metadata = currentStreamMetadata.last
                    
                    // Replace the pending message or add a new one
                    if let lastIndex = messages.lastIndex(where: { $0.isPending }) {
                        messages[lastIndex] = finalMessage
                    } else {
                        messages.append(finalMessage)
                    }
                    continuation.yield(finalMessage)
                }
                
                // End the workflow if we didn't execute a tool or research is not in progress
                continueResearchWorkflow = false
                setState(.idle)
                continuation.finish()
                
            } catch {
                currentStreamMetadata = [] // Reset on error
                print("❌ Streaming error: \(error.localizedDescription)")
                setState(.error(AgentError(from: error)))
                continuation.finish(throwing: error)
                return
            }
        }
    }
    
    /// Generates a prompt to continue the research workflow based on the last tool executed
    private func generateContinueResearchPrompt(lastToolName: String?) -> String {
        guard let lastToolName = lastToolName else {
            return "Continue the research process. What's the next step?"
        }
        
        switch lastToolName {
        case "start_research":
            return "Now that you've started the research, please search for medical evidence on this topic using the search_medical_evidence tool."
            
        case "search_medical_evidence":
            return "Now that you've found some evidence, use the read_evidence tool to analyze one of the sources in depth."
            
        case "read_evidence":
            return "Based on the evidence you've read, use the reason_evidence tool to analyze the findings and determine if more evidence is needed."
            
        case "reason_evidence":
            return "Based on your reasoning, either search for more evidence with search_medical_evidence, or if you have sufficient information, complete the research using complete_research."
            
        case "search_health_profile":
            return "Now that you have profile information, continue your research by searching for more evidence or completing the research if you have enough information."
            
        default:
            return "Continue the research process. What's the next step?"
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
            
            // Use AIToolRegistry instead of direct array search
            guard let toolType = AIToolRegistry.toolType(forName: function.name) else {
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
                let result = try await tool.execute()
                
                // Add tool response to messages and update metadata tracker
                let message = ChatMessage(message: .tool(content: result.content, name: function.name, toolCallId: toolCall.id))
                message.metadata = result.metadata
                messages.append(message)
                
                // Update metadata in callbacks
                for callback in callbacks {
                    if let tracker = callback as? MetadataTracker {
                        tracker.setMetadata(result.metadata, forToolCallId: toolCall.id)
                    }
                }
                
                toolResponses.append(result.content)
                
                // If tool requests direct response, return immediately
                if tool.returnToolResponse {
                    setState(.idle)
                    let finalMessage = ChatMessage(message: .assistant(content: .text(result.content)))
                    return finalMessage
                }
                
                // Add after successful tool execution
                let afterToolResult = await executeCallbacks {
                    await $0.onAfterToolExecution(name: function.name, result: result.content)
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
            messages: convertToAPIMessages()
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
        // Use AIToolRegistry instead of direct array search
        guard let toolType = AIToolRegistry.toolType(forName: name) else {
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
            let result = try await tool.execute()
            
            // Create message
            let message = ChatMessage(message: .tool(content: result.content, name: name, toolCallId: toolCallId))
            message.metadata = result.metadata
            
            // Update metadata in callbacks
            for callback in callbacks {
                if let tracker = callback as? MetadataTracker {
                    tracker.setMetadata(result.metadata, forToolCallId: toolCallId)
                }
            }
            
            // Notify callbacks
            let afterToolResult = await executeCallbacks {
                await $0.onAfterToolExecution(name: name, result: result.content)
            }
            if case .cancel = afterToolResult {
                setState(.idle)
                throw AgentError.operationCancelled
            }
            
            return (message, result.metadata)
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
