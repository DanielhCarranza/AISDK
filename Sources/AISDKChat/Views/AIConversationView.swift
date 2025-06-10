//
//  AIConversationView.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 05/01/25.
//

import SwiftUI

struct AIConversationView: View {
    // MARK: - Properties
    @Binding var session: ChatSession
    @Environment(AIChatManager.self) private var manager
    @Environment(HealthProfile.self) private var healthProfile
    @State private var showScrollButton = false
    @Namespace private var bottomID
    @FocusState private var isInputFocused: Bool
    @State private var scrollID: String?
    @State private var scrollInterrupted = false
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(session.messages) { message in
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
                .onChange(of: session.messages) { _, _ in
                    // Only auto-scroll if not interrupted
                    if !scrollInterrupted {
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
                if showScrollButton {
                    Button {
                        withAnimation {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                            showScrollButton = false
                            scrollInterrupted = false  // Reset interruption when manually scrolling to bottom
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title)
                            .foregroundStyle(.gray)
                            .padding(8)
                    }
                    .transition(.scale.combined(with: .opacity))
                    .padding(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: -40) // Keep it above the input area
                }
            }
            
            // Input Area
            VStack(spacing: 0) {
                // Suggested Questions floating above
                if !manager.state.isProcessing {
                    SuggestedQuestionsView(
                        questions: manager.suggestedQuestions,
                        isLoading: manager.isLoadingSuggestions
                    )
                    .environment(manager)
                    .padding(.bottom, 8)
                }
                
                if case .error(let error) = manager.state {
                    Text(error.detailedDescription)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                        .multilineTextAlignment(.center)
                }
                
                if manager.state.isProcessing {
                    TypingIndicator(state: manager.state)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(red: 5 / 255, green: 7 / 255, blue: 14 / 255))
                        .cornerRadius(16)
                        .padding(.bottom, 8)
                }
                
                AIInputView(isFocused: _isInputFocused)
                    .environment(manager)
                    .environment(healthProfile)
            }
            .padding(.horizontal)
        }
        .task {
                await manager.generateSuggestedQuestions()
        }
        .onChange(of: manager.state) { oldState, newState in
            if case .idle = newState {
                Task {
                    await manager.generateSuggestedQuestions()
                }
            }
        }
        .onChange(of: scrollID) { _, _ in
            // Interrupt auto-scroll if user manually scrolls
            if manager.state.isProcessing {
                scrollInterrupted = true
            }
        }
    }
}

// MARK: - Preview
//struct AIConversationView_Previews: PreviewProvider {
//    static var previews: some View {
//        AIConversationView()
//            .environment(AIChatManager())
//            .environment(HealthProfile())
//    }
//}
