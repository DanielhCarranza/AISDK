//
//  ResearcherAgentDemoView.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import SwiftUI
import MarkdownUI

// Preference key to communicate research mode state
struct ResearchModePreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

struct ResearcherAgentDemoView: View {
    // MARK: - Properties
    
    @State private var agent = ResearcherAgent()
    @State private var inputText = ""
    @State private var healthProfile = HealthProfile()
    @State private var chatManager = AIChatManager()
    @State private var researchMode = false
    @FocusState private var isInputFocused: Bool
    @State private var isInputVisible = true
    
    // Scrolling properties
    @State private var showScrollButton = false
    @State private var scrollID: String?
    @State private var scrollInterrupted = false
    @Namespace private var bottomID
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Research Status Card - only show when not idle
            if !agent.state.isIdle {
                researchStatusCard
                    .padding()
            }
            
            // Messages List with ScrollViewReader
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(agent.messages) { message in
                            MessageBubble(chatMessage: message)
                                .id(message.id) // Ensure stable IDs
                        }
                        // Invisible marker view at bottom
                        Color.clear
                            .frame(height: 1)
                            .id(bottomID)
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $scrollID, anchor: .bottom)
                .onAppear {
                    withAnimation {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
                .onChange(of: agent.messages) { _, _ in
                    // Only auto-scroll if not interrupted and agent is streaming
                    if !scrollInterrupted && agent.isStreaming {
                        withAnimation {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture().onChanged { value in
                        let threshold: CGFloat = 50 // Adjust as needed
                        showScrollButton = value.translation.height < -threshold
                    }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        isInputFocused = false // Dismiss keyboard on tap
                    }
                )
                
                // Scroll to bottom button
                // if showScrollButton {
                //     Button {
                //         withAnimation {
                //             proxy.scrollTo(bottomID, anchor: .bottom)
                //             showScrollButton = false
                //             scrollInterrupted = false  // Reset interruption when manually scrolling to bottom
                //         }
                //     } label: {
                //         Image(systemName: "arrow.down.circle.fill")
                //             .font(.title)
                //             .foregroundStyle(.gray)
                //             .padding(8)
                //     }
                //     .transition(.scale.combined(with: .opacity))
                //     .padding(.trailing)
                //     .frame(maxWidth: .infinity, alignment: .trailing)
                //     .offset(y: -40) // Keep it above the input area
                // }
            }
            
            // Input Area using AIInputView
            AIInputView(isFocused: _isInputFocused, isVisible: $isInputVisible)
                .environment(chatManager)
                .environment(healthProfile)
                .environment(\.researchAgent, agent)
                .onPreferenceChange(ResearchModePreferenceKey.self) { isResearchMode in
                    // Only update if the value is changing to avoid unnecessary state changes
                    if researchMode != isResearchMode {
                        researchMode = isResearchMode
                    }
                }
        }
        .onChange(of: researchMode) { oldValue, newValue in
            if newValue {
                // When research mode is activated
                print("Research mode activated")
                
                // If there was a previous research, reset it
                if !agent.state.isIdle {
                    agent.cancelResearch()
                }
            } else {
                // When research mode is deactivated
                print("Research mode deactivated")
            }
        }
        .onChange(of: scrollID) { _, _ in
            // Interrupt auto-scroll if user manually scrolls
            if agent.isStreaming {
                scrollInterrupted = true
            }
        }
        .onChange(of: agent.isStreaming) { _, newValue in
            // When streaming starts, reset scroll interruption
            if newValue {
                scrollInterrupted = false
            }
        }
    }
    
    // MARK: - Subviews
    
    /// Card showing the current research status
    private var researchStatusCard: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: agent.state.stateIcon)
                    .foregroundColor(agent.state.stateColor)
                
                Text("Research Status")
                    .font(.subheadline)
                
                Spacer()
                
                // State pill
                Text(stateLabel)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(agent.state.stateColor.opacity(0.2))
                    .foregroundColor(agent.state.stateColor)
                    .cornerRadius(12)
            }
            
            // Research details
            HStack{
                // if let topic = agent.state.topic {
                //     HStack {
                //         Text("Topic:")
                //             .fontWeight(.medium)
                //         Text(topic)
                //     }
                //     .font(.subheadline)
                // }
                
                if agent.state.elapsedTime != nil {
                    HStack {
                        Text("Time:")
                            .fontWeight(.medium)
                        Text(agent.formattedElapsedTime())
                    }
                    .font(.subheadline)
                }
                Spacer()
                if agent.state.sourceCount > 0 {
                    HStack {
                        Text("Sources:")
                            .fontWeight(.medium)
                        Text("\(agent.state.sourceCount)")
                    }
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color.black.opacity(0.2))
                .background(.ultraThinMaterial)
                .blur(radius: 3)
                .cornerRadius(25, corners: [.topLeft, .topRight])
        )
    }
    
    // MARK: - Helper Properties
    
    /// Label for the current state
    private var stateLabel: String {
        switch agent.state {
        case .idle:
            return "Ready"
        case .start:
            return "Starting"
        case .processing:
            return "Researching"
        case .completed:
            return "Completed"
        }
    }
    
    // MARK: - Actions
    
    /// Sends the current input text as a message
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        
        // Start research immediately with the input text as the topic
        if !agent.state.isResearching {
            agent.startResearch(topic: inputText)
        } else {
            // If already researching, just send as a regular message
            agent.sendMessage(inputText)
        }
        
        inputText = ""
    }
    
}


// MARK: - Preview
struct ResearcherAgentDemoView_Previews: PreviewProvider {
    static var previews: some View {
        ResearcherAgentDemoView()
    }
} 
