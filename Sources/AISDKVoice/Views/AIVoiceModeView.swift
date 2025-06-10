//
//  BasicConversationalAIView.swift
//  HealthCompanion
//
//  Created by Apple 55 on 4/25/24.
//
// swiftlint:disable all
import AVFoundation
import Speech
import SpeziSpeechRecognizer
import SpeziLLM
import SpeziLLMOpenAI
import OpenAI
import SwiftUI

struct AIVoiceModeView: View {
    @Environment(HealthProfile.self) var healthProfile
    @Environment(\.dismiss) private var dismiss
    @State var aiVoice = AIVoiceMode()
    @State var profile: String = ""
    @State var isInitializing: Bool = true
    @State private var fadeInOut = false
    @State private var statusOpacity = 1.0
    @State private var scale: CGFloat = 1.0
    let observerMode: Bool?
    let triggerEvent: TriggerEvent?
    
    var body: some View {
        Group {
            if isInitializing {
                VStack {
                    Spacer()
                    ProgressView("Initializing AI...")
                    Spacer()
                }
            } else {
                ZStack {
                    // Main content area
                    VStack {
                        Spacer()
                        
                        if aiVoice.isAISpeaking {
                            Image("Logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 100, height: 100)
                                .scaleEffect(scale)
                                .onAppear {
                                    withAnimation(Animation.easeInOut(duration: 1.0).repeatForever()) {
                                        scale = 1.2
                                    }
                                }
                                .onDisappear {
                                    scale = 1.0
                                }
                        }
                        
                        statusText
                            .opacity(statusOpacity)
                            .animation(.easeInOut(duration: 0.3), value: statusOpacity)
                            .multilineTextAlignment(.center)
                        
                        Spacer()
                    }
                    
                    // Bottom control bar
                    VStack {
                        Spacer()
                        bottomControls
                    }
                }
            }
        }
        .navigationTitle("Your Health Companion")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let profile = await healthProfile.getHealthProfileMarkdown()
            // If there is a trigger event, append the context to the profile
            var fullProfile = profile
            if let trigger = triggerEvent {
                fullProfile += "\n\nContext: \(trigger.context)"
            }
            aiVoice.setupAISystem(profile: fullProfile, observerMode: observerMode)
            aiVoice.setupAudioFinishedCallback {
                handleAudioFinished()
            }
            
            let initialMessage = if observerMode == true {
                triggerEvent?.question ?? "How can I help you today?"
            } else {
                "Hi, how can I help you today?"
            }
            
            aiVoice.startConversation(initialMessage: initialMessage)
            isInitializing = false
        }
        
    }
    
    init(observerMode: Bool? = nil, triggerEvent: TriggerEvent? = nil) {
        self.observerMode = observerMode
        self.triggerEvent = triggerEvent
    }
    
    private var statusText: some View {
        Group {
            if aiVoice.isTransitioning {
                ProgressView()
                    .scaleEffect(0.5)
            } else if aiVoice.isRecording {
                VStack {
                    Text("Listening...")
                        .padding(.bottom, 4)
                    AnimatedTranscriptView(
                        text: aiVoice.transcript,
                        currentWordIndex: aiVoice.currentWordIndex
                    )
                }
            } else if aiVoice.aiThinking {
                VStack(spacing: 8) {
                    ProgressView("Thinking...")
                }
            } else if aiVoice.isAISpeaking {
                Text("AI Talking...")
            } else {
//                Text("Tap mic to speak")
                ProgressView()
            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.2), value: aiVoice.isTransitioning)
    }
    
    private var bottomControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 40) {
                // Play/Pause Button
                Button(action: aiVoice.togglePlayPause) {
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: aiVoice.isPlaying ? "pause.fill" : "play.fill")
                                .foregroundColor(.primary)
                        )
                }
                
                // Microphone Button
                Button(action: aiVoice.toggleSpeechRecognition) {
                    Circle()
                        .fill(aiVoice.isRecording ? Color.red.opacity(0.2) : Color(.systemGray6))
                        .frame(width: 56, height: 56)  // Slightly larger than other buttons
                        .overlay(
                            Image(systemName: aiVoice.isRecording ? "stop.circle" : "mic.fill")
                                .foregroundColor(aiVoice.isRecording ? .red : .primary)
                                .animation(.easeInOut, value: aiVoice.isRecording)
                        )
                }
                
                // End Conversation Button
                Button(action: {
                    // Stop any ongoing speech recognition if active
                    if aiVoice.isRecording {
                        aiVoice.toggleSpeechRecognition()
                    }
                    // Stop any ongoing audio playback
                    aiVoice.stop()
                    // Dismiss the view
                    dismiss()
                }) {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "xmark")
                                .foregroundColor(.red)
                        )
                }
            }
            .padding(.bottom, 8)
            
            // Progress indicator
            Rectangle()
                .frame(width: 120, height: 4)
                .foregroundColor(Color(.systemGray6))
                .cornerRadius(2)
        }
        .padding(.bottom, 32)
    }
    
    private func handleAudioFinished() {
        withAnimation(.easeInOut(duration: 0.3)) {
            statusOpacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            aiVoice.toggleSpeechRecognition()
            
            withAnimation(.easeInOut(duration: 0.3)) {
                statusOpacity = 1
            }
        }
    }
}



//#Preview {
//    BasicConversationalAIView()
//}
