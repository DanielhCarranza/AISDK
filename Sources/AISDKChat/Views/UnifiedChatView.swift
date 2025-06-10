//
//  UnifiedChatView.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 28/12/24.
//


import SwiftUI
import SpeziSpeechSynthesizer
import SpeziChat
import SpeziViews
import SpeziLLM
import SpeziLLMOpenAI


public struct UnifiedChatView<Session: LLMSession>: View {
    @Environment(HealthProfile.self) private var healthProfile
    // Basic chat properties
    @Binding var chat: Chat
    private let disableInput: Bool
    private let speechToText: Bool
    private let messagePlaceholder: String?
    private let messagePendingAnimation: MessagesView.TypingIndicatorDisplayMode?
    private let hideMessages: MessageView.HiddenMessages
    
    // LLM-specific properties
    @Binding private var llm: Session
    
    @State private var messageInputHeight: CGFloat = 0
    @State private var isProcessingMessage = false
    
    public var body: some View {
        ZStack {
            VStack {
                MessagesView($chat, hideMessages: hideMessages, typingIndicator: messagePendingAnimation, bottomPadding: $messageInputHeight)
                    #if !os(macOS)
                    .gesture(
                        TapGesture().onEnded {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder),
                                to: nil,
                                from: nil,
                                for: nil
                            )
                        }
                    )
                    #endif
            }
            VStack {
                Spacer()
                CompanionMessageInputView($chat, messagePlaceholder: messagePlaceholder, speechToText: speechToText)
                    .disabled(disableInput)
                    .onPreferenceChange(MessageInputViewHeightKey.self) { newValue in
                        if Thread.isMainThread {
                            MainActor.assumeIsolated {
                                messageInputHeight = newValue + 12
                            }
                        } else {
                            Task { @MainActor in
                                messageInputHeight = newValue + 12
                            }
                        }
                    }
                    .environment(healthProfile)
            }
        }
        .viewStateAlert(state: llm.state)
        .onChange(of: llm.context) { oldValue, newValue in
            guard !isProcessingMessage,
                  oldValue.count != newValue.count,
                  let lastChat = newValue.last,
                  lastChat.role == .user else {
                return
            }
            
            isProcessingMessage = true
            
            Task {
                do {
                    let stream = try await llm.generate()
                    
                    for try await token in stream {
                        llm.context.append(assistantOutput: token)
                    }
                    
                    llm.context.completeAssistantStreaming()
                    
                // Previous code here was: `catch let error as LLMError` - since we are not using the error
                // parameter in the commennted-out code (line 93), simplified it as the following
        
                } catch _ as LLMError {
//                    llm.state = .error(error: error)
                } catch {
                    llm.state = .error(error: LLMDefaultError.unknown(error))
                }
                
                isProcessingMessage = false
            }
        }
    }
    

    public init(
        session: Binding<Session>,
        chat: Binding<Chat>,
        disableInput: Bool = false,
        speechToText: Bool = true,
        messagePlaceholder: String? = nil,
        messagePendingAnimation: MessagesView.TypingIndicatorDisplayMode? = nil,
        hideMessages: MessageView.HiddenMessages = .all
    ) {
        self._llm = session
        self._chat = session.context.chat
        self.disableInput = disableInput
        self.speechToText = speechToText
        self.messagePlaceholder = messagePlaceholder
        self.hideMessages = hideMessages
        self.messagePendingAnimation = messagePendingAnimation
    }
}
