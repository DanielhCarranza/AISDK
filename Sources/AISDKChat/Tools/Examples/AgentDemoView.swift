//
//  AgentDemoView.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import MarkdownUI
import SwiftUI

struct AgentDemoView: View {
    // MARK: - Properties
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var state: AgentState = .idle
    @State private var isStreaming: Bool = false
    
    private let agent: Agent
    private let metadataTracker = MetadataTracker()
    
    // MARK: - Init
    
    init() {
        // Initialize agent with demo tools
        do {
            self.agent = try Agent(
                model: AgenticModels.o3mini,
                tools: [WeatherToolUI.self, 
                CalculatorTool.self, 
                TimezoneTool.self, 
                ResearchTool.self, 
                LogJournalEntryTool.self, 
                DisplayMedicationTool.self]
            )
        } catch {
            fatalError("Failed to initialize agent: \(error)")
        }
        
        // Add metadata tracker
        self.agent.addCallbacks(metadataTracker)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack {
            // Messages List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(chatMessage: message)
                    }
                }
                .padding()
            }
            
            // Input Area
            VStack(spacing: 8) {
                if case .error(let error) = state {
                    Text(error.detailedDescription)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                        .multilineTextAlignment(.center)
                }
                
                if state.isProcessing {
                    TypingIndicator(state: state)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(red: 5 / 255, green: 7 / 255, blue: 14 / 255))
                        .cornerRadius(16)
                }
                
                HStack {
                    TextField("Type a message...", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(state.isProcessing)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(inputText.isEmpty || state.isProcessing)
                }
            }
            .padding()
        }
        .onAppear {
            // Add initial system message
            messages.append(ChatMessage(message: .assistant(content: .text("""
                Hello! I can help you with:
                - Weather information
                - Basic calculations
                - Timezone conversions
                - Medical research searches
                
                Try asking about any of these topics!
                """))))
        }
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        let userMessage = ChatMessage(message: .user(content: .text(inputText)))
        messages.append(userMessage)
        inputText = ""
        
        // Set state to thinking immediately
        state = .thinking
        
        agent.onStateChange = { state in
            DispatchQueue.main.async {
                self.state = state
            }
        }
        
        Task {
            do {
                isStreaming = true
                
                for try await message in agent.sendStream(userMessage) {
                    await MainActor.run {
                        // Update messages based on streaming response
                        if let lastMessage = messages.last,
                           case .assistant = lastMessage.message,
                           lastMessage.isPending {
                            // Update existing pending message
                            messages[messages.count - 1] = message
                        } else {
                            // Add new message
                            let streamingMessage = message
                            streamingMessage.isPending = true
                            messages.append(streamingMessage)
                        }
                    }
                }
                
                await MainActor.run {
                    // Mark last message as complete
                    if let lastIndex = messages.lastIndex(where: { $0.isPending }) {
                        messages[lastIndex].isPending = false
                    }
                    
                    isStreaming = false
                    self.state = .idle
                    // Clean up metadata after streaming is complete
                    metadataTracker.reset()
                }
            } catch {
                print("❌ Error in sendMessage: \(error.localizedDescription)")
                await MainActor.run {
                    isStreaming = false
                    self.state = .error(error.asAIError)
                }
            }
        }
    }
}

// MARK: - Supporting Views



// MARK: - Preview
struct AgentDemoView_Previews: PreviewProvider {
    static var previews: some View {
        AgentDemoView()
    }
}


