//
//  that.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 05/01/25.
//


import SwiftUI
import Combine

/// A simple observable class that wraps an Agent to manage conversation.
public final class AIChat: Observable {
    
    // MARK: - Published Properties
    
    /// A list of conversation messages rendered in the UI
    var messages: [ChatMessage] = []
    
    /// The current state of the agent (e.g., idle, thinking, responding, executingTool, error)
    var state: AgentState = .idle
    
    /// Whether the chat is currently streaming partial responses
    var isStreaming: Bool = false
    
    // MARK: - Private Properties
    
    /// The underlying AI Agent
    private let agent: Agent
    
    // MARK: - Initialization
    
    public init() {
        // Initialize the Agent with whichever model and tools you prefer
        do {
            self.agent = try Agent(
                model: AgenticModels.gpt4,
                tools: [WeatherTool.self, CalculatorTool.self],
                instructions: String(localized: "SYSTEM_PROMPT_AI_COMPANION")
            )
        } catch {
            fatalError("Failed to initialize Agent: \(error)")
        }
        
        // Subscribe to Agent state changes
        self.agent.onStateChange = { [weak self] newState in
            DispatchQueue.main.async {
                self?.state = newState
            }
        }
        
        // an initial system or assistant message
        let welcome = Message.assistant(content: .text("Hello! How can I help you today?"))
        self.messages.append(ChatMessage(message: welcome))
    }
    
    // MARK: - Public Methods
    
    /// Sends a user's message to the AI and handles streaming responses.
    public func sendMessage(_ parts: [UserContent.Part]) {
        // Create user message with parts
        let userMessage = Message.user(content: .parts(parts))
        messages.append(ChatMessage(message: userMessage))
        
        // Start streaming
        isStreaming = true
        
        Task {
            do {
                // Invoke the streaming method on the Agent
                for try await message in agent.sendStream(ChatMessage(message: userMessage)) {
                    await MainActor.run {
                        handleIncoming(message)
                    }
                }
                
                // End streaming
                await MainActor.run {
                    self.isStreaming = false
                    self.state = .idle
                }
                
            } catch {
                await MainActor.run {
                    self.isStreaming = false
                    self.state = .error(error.asAIError)
                }
            }
        }
    }
    
    /// Sends a user's message to the AI and handles streaming responses.
    public func sendMessage(_ text: String) {
        sendMessage([.text(text)])
    }
    
    // MARK: - Private Helpers
    
    /// Process each streamed `Message` from the agent, updating our conversation array.
    @MainActor
    private func handleIncoming(_ message: ChatMessage) {
//        switch message {
//        case .assistant(let content, _, _):
//            if case .text(let text) = content {
//                // Only handle non-empty messages
//                if !text.isEmpty {
//                    if var lastMessage = messages.last,
//                        case .assistant = lastMessage.message {
//                        messages.removeLast()
//                        lastMessage = ChatMessage(message: message)
//                        messages.append(lastMessage)
//                    } else {
//                        messages.append(ChatMessage(message: message))
//                    }
//                }
//            }
//        case .tool(let content, _, _):
//            // Only add tool messages with content
//            if !content.isEmpty {
//                messages.append(ChatMessage(message: message))
//            }
//        default:
//            messages.append(ChatMessage(message: message))
//        }
    }

}
