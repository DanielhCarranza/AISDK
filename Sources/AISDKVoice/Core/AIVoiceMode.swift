//
//  SpeechStore.swift
//  HealthCompanion
//
//  Created by Apple 55 on 2/15/24.
//

import Foundation
import OpenAI
import SpeziSpeechRecognizer
import AVFAudio
import ChunkedAudioPlayer
import Combine
import SwiftUI

/// The AIVoiceMode class is responsible for generating and managing speech audio based on text input. 
/// It leverages the OpenAI API to create speech from text and handles audio playback using AVAudioPlayer. 
/// The class also includes caching mechanisms to improve performance by storing previously generated audio.
///
/// This class serves as the core engine for the conversational AI feature, managing both input (speech recognition)
/// and output (text-to-speech) as well as the conversation flow with the AI model.
enum AIMode {
    case conversation
    case questionnaire
    case observer
}

struct QuestionnaireResult: Codable {
    let timestamp: Date
    let conversation: [ChatQuery.ChatCompletionMessageParam?]
}

@Observable
public final class AIVoiceMode: NSObject, VoiceActivityDetectorDelegate {
    // Dependencies
    var aiClient = OpenAIService()
    var player = AudioPlayer()
    var speechRecognizer = SpeechRecognizer()

    private let database = Database()
    private let collection = "questionnaire_results"
    private let analyzer: Analyzer = Analyzer()

    // State variables
    var isLoading: Bool = false
    var errorMessage: String?

    // Audio playback state
    var isPlaying: Bool = false
    var isPaused: Bool = false
    var isStopped: Bool = false

    // Speech recognition state
    var isRecording: Bool = false
    var transcript: String = ""

    // Conversation state
    var userMessage: String = ""
    var aiMessage: String = ""
    var aiThinking: Bool = false
    var messages: [ChatQuery.ChatCompletionMessageParam?] = []

    // User health profile for personalized responses
    var profile: String?

    // Callback for when audio playback finishes
    private var onAudioFinished: (() -> Void)?
    // Set to store Combine cancellables
    private var cancellables = Set<AnyCancellable>()
    
    // New VAD property
    private var voiceActivityDetector: VoiceActivityDetector?
    
    // Add new state variable
    var isInitializing: Bool = true
    
    // Add state for managing transitions
    private(set) var isTransitioning: Bool = false
    
    // Add new state variable
    var isAISpeaking: Bool = false
    
    var currentWordIndex: Int = 0
    private var transcriptWords: [String] = []
    
    // Add mode property
    private var mode: AIMode = .conversation

    // Add questionnaireEnded property
    var questionnaireEnded: Bool = false
    
    // Modify the initializer
    public override init() {
        super.init()
        setup()
    }
    
    
    private func setup() {
        setupPlayerObservers()
        setupVoiceActivityDetector() // setup method for VAD
    }

    func setupAISystem(profile: String, observerMode: Bool? = nil, questionnaireMode: Bool = false) {
        isInitializing = true
        
        // Set the mode
        if questionnaireMode {
            mode = .questionnaire
        } else if observerMode == true {
            mode = .observer
        } else {
            mode = .conversation
        }
        
        // Initialize the conversation with appropriate system prompt
        var systemPrompt = switch mode {
            case .questionnaire:
                String(localized: "SYSTEM_QUESTIONNARIE")
            case .observer:
                String(localized: "SYSTEM_OBSERVER_MODE")
            case .conversation:
                String(localized: "SYSTEM_PROMPT_AI_COMPANION")
        }

        systemPrompt += "\n\n \(profile)"
        messages.append(ChatQuery.ChatCompletionMessageParam(role: .system,
                                                           content: systemPrompt))
        isInitializing = false
    }
    
    /// Sets up a callback to be called when audio playback finishes
    func setupAudioFinishedCallback(_ callback: @escaping () -> Void) {
        onAudioFinished = callback
    }
    
    /// Initiates the conversation with an initial AI message
    func startConversation(initialMessage: String) {
        aiThinking = true
        isAISpeaking = true  // Set speaking state immediately
        
        Task {
            await speak(TextToSpeechQuery(input: initialMessage))
            await MainActor.run {
                self.messages.append(ChatQuery.ChatCompletionMessageParam(role: .assistant, content: initialMessage))
                self.aiThinking = false
                // isAISpeaking will be set to false by the player observer when playback actually ends
            }
        }
    }
    
    /// Processes a user message, sends it to the AI, and handles the response
    func processUserMessage(_ message: String) {
        aiThinking = true
        isAISpeaking = true
        
        let tools = [
            ChatQuery.ChatCompletionToolParam(
                function: .init(
                    name: "end_questionnaire",
                    description: "End the questionnaire and return the results",
                    parameters: .init(
                        type: .object,
                        properties: [
                            "end_questionnaire": .init(
                                type: .boolean,
                                description: "End the questionnaire and return the results"
                            )
                        ],
                        required: ["end_questionnaire"]
                    )
                )
            )
        ]
        
        messages.append(ChatQuery.ChatCompletionMessageParam(role: .user, content: message))
        let query = ChatQuery(
            messages: self.messages.compactMap { $0 }, 
            model: "gpt-4o",
            toolChoice: .auto,
            tools: tools
        )
        
        Task {
            do {
                let result = try await aiClient.chats(query: query)
                let choice = result.choices[0].message
                
                // Check if the AI wants to use a tool
                if let toolCalls = choice.toolCalls {
                    for toolCall in toolCalls {
                        if toolCall.function.name == "end_questionnaire" {
                            // Parse the function arguments
                            if let data = toolCall.function.arguments.data(using: .utf8),
                               let json = try? JSONDecoder().decode([String: Bool].self, from: data),
                               json["end_questionnaire"] == true {
                                
                                await MainActor.run {
                                    // Handle questionnaire ending
                                    self.handleQuestionnaireEnd()
                                    
                                    // Add the tool result back to the conversation
                                    self.messages.append(.tool(.init(
                                        content: "Questionnaire ended successfully",
                                        toolCallId: toolCall.id
                                    )))
                                }
                                return
                            }
                        }
                    }
                }
                
                // Handle normal message response
                let response = choice.content?.string ?? ""
                
                await MainActor.run {
                    self.aiMessage = response
                    self.messages.append(ChatQuery.ChatCompletionMessageParam(role: .assistant, content: response))
                }

                await speak(TextToSpeechQuery(input: response))
                
                await MainActor.run {
                    self.aiThinking = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "LegacyLLM Error: \(error.localizedDescription)"
                    self.aiThinking = false
                    self.isAISpeaking = false
                }
            }
        }
    }
    
    // Add this new function to handle questionnaire ending
    private func handleQuestionnaireEnd() {
        // Here you would implement the logic for what happens when the questionnaire ends
        // For example:
        // - Save the conversation history
        // - Generate a summary or report

        // Speak a thank you message
//        let thankYouMessage = "Thank you for your patience. I will analyze the results and get back to you shortly with your personalized health plans"
//        await speak(TextToSpeechQuery(input: thankYouMessage))
        
        // Example implementation:
        self.aiThinking = false
        self.isAISpeaking = false
        self.stopSpeechRecognition()

        let questionnaireResults = QuestionnaireResult(timestamp: Date(), conversation: self.messages)

        // Save the questionnaire results to the database
        database.saveData(inCollection: collection, data: questionnaireResults) { result in
            switch result {
            case .success:
                print("Questionnaire results saved successfully")
            case .failure(let error):
                print("Failed to save questionnaire results: \(error)")
            }
        }

        // You might want to trigger some callback
        self.analyzer.analyzeCompletition()

        questionnaireEnded = true


    }
    
    /// Converts text to speech and plays it
    @MainActor
    func speak(_ query: TextToSpeechQuery) async {
        let input = query.input
        guard !input.isEmpty else {
            errorMessage = "Input text is empty."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // Configure audio session for playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

            let stream = aiClient.textToSpeech(query: query)
            
            // Start streaming audio
            isPlaying = true
            player.start(stream, type: query.format.fileType)

        } catch {
            errorMessage = "An error occurred: \(error.localizedDescription)"
            isLoading = false
        }

        isLoading = false
    }
    
    /// Toggles between play and pause states for audio playback
    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else {
            player.resume()
        }
    }
    
    /// Stops audio playback
    func stop() {
        player.stop()
    }
    
    /// Toggles speech recognition on/off with VAD
    func toggleSpeechRecognition() {
        if isRecording {
            stopSpeechRecognition()
        } else {
            startSpeechRecognition()
        }
    }
    
    /// Starts the speech recognition process with VAD
    private func startSpeechRecognition() {
        isRecording = true
        transcript = ""
        currentWordIndex = 0
        transcriptWords = []
        voiceActivityDetector?.startMonitoring()
        
        Task {
            do {
                for try await result in speechRecognizer.start() {
                    await MainActor.run {
                        self.transcript = result.bestTranscription.formattedString
                        // Update words array and current index
                        let newWords = result.bestTranscription.formattedString.split(separator: " ").map(String.init)
                        if newWords.count > transcriptWords.count {
                            self.currentWordIndex = newWords.count - 1
                        }
                        self.transcriptWords = newWords
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Speech recognition error: \(error.localizedDescription)"
                    self.isRecording = false
                    voiceActivityDetector?.stopMonitoring()
                }
            }
        }
    }
    
    /// Stops speech recognition and VAD monitoring, then processes the transcribed message
    private func stopSpeechRecognition() {
        speechRecognizer.stop()
        isRecording = false
        voiceActivityDetector?.stopMonitoring()
        
        // Only process the message if transcript is not empty
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTranscript.isEmpty {
            processUserMessage(trimmedTranscript)
        }
    }
    
    /// Sets up observers for the audio player's state and errors
    private func setupPlayerObservers() {
        player.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                
                switch state {
                case .completed:
                    self.isPlaying = false
                    self.isPaused = false
                    self.isAISpeaking = false
                    // Call callback immediately
                    self.onAudioFinished?()
                case .playing:
                    self.isPlaying = true
                    self.isPaused = false
                    self.isAISpeaking = true
                case .paused:
                    self.isPlaying = false
                    self.isPaused = true
                    // Don't change isAISpeaking state on pause
                case .initial, .failed:
                    self.isPlaying = false
                    self.isPaused = false
                    self.isAISpeaking = false
                }
            }
            .store(in: &cancellables)
    }
    
    /// Sets up the VoiceActivityDetector and assigns the delegate
    private func setupVoiceActivityDetector() {
        voiceActivityDetector = VoiceActivityDetector(
            silenceThreshold: -65.0,
            silenceDuration: 6.5  // Adjusted for better response time
        )
        voiceActivityDetector?.delegate = self
    }
    
    // MARK: - VoiceActivityDetectorDelegate Methods
    
    func voiceActivityDetectorDidDetectSilence(_ detector: VoiceActivityDetector) {
        Task { @MainActor in
            if isRecording && !transcript.isEmpty {
                stopSpeechRecognition()
            }
        }
    }
    
    func voiceActivityDetectorDidDetectAudio(_ detector: VoiceActivityDetector) {
        // Audio has been detected, can perform any necessary actions
        // For example, reset timers if manually handled (Not needed in this implementation)
    }
}
