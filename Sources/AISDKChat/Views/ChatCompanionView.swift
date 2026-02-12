//
//  ChatCompanionView.swift
//  HealthCompanion
//
//  Created by Apple 55 on 1/21/24.
//

import SwiftUI

struct ChatCompanionView: View {
    @State var healthProfile = HealthProfile()
    @State var manager: AIChatManager
    @State private var showingChatHistory = false
    @State private var navigateToHistory = false
    
    let triggerEvent: TriggerEvent?
    let dynamicMessage: DynamicMessage?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Base background color
                Color.black
                    .ignoresSafeArea()
                
                // Updated gradient to match logo colors
                LinearGradient(gradient: Gradient(colors: [
                    Color(#colorLiteral(red: 0, green: 0.8, blue: 0.8, alpha: 0.1)), // Cyan/turquoise
                    Color(#colorLiteral(red: 0.8, green: 0, blue: 0.8, alpha: 0.1))  // Magenta/purple
                ]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                
                // Existing content
                Group {
                    if manager.isLoadingSession {
                        VStack {
                            ProgressView()
                                .controlSize(.large)
                            Text("Loading session...")
                                .foregroundColor(.secondary)
                        }
                    } else if let currentSession = manager.currentSession {
                        AIConversationView(session: Binding(
                            get: { currentSession },
                            set: { manager.currentSession = $0 }
                        ))
                        .environment(manager)
                        .environment(healthProfile)
                    } else {
                        VStack {
                            Text("No active chat session")
                                .foregroundColor(.secondary)
                            Button("Start New Chat") {
                                Task {
                                    await manager.createNewSession()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cony")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        navigateToHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: JournalView()) {
                        Text("Journal")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToHistory) {
                ChatHistoryView(isPresented: $navigateToHistory)
                    .environment(manager)
            }
            .gesture(
                DragGesture()
                    .onEnded { gesture in
                        if gesture.translation.width > 50 {
                            navigateToHistory = true
                        }
                    }
            )
        }
        .task {
            // LegacyAgent setup is now moved to init, so just load sessions
            manager.loadChatSessions()
        }
    }

    init(triggerEvent: TriggerEvent? = nil, dynamicMessage: DynamicMessage? = nil) {
        self.triggerEvent = triggerEvent
        self.dynamicMessage = dynamicMessage
        
        _manager = State(initialValue: AIChatManager(
            triggerEvent: triggerEvent,
            dynamicMessage: dynamicMessage
        ))
    }
}

#Preview {
    ChatCompanionView()
}
