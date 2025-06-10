//
//  AIChatManager.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 06/01/25.
//


import SwiftUI
import Combine
import OpenAI


class AIChatManager: Observable {
    // MARK: - Dependencies
    private var healthProfile = HealthProfile()
    
    // MARK: - Configuration
    private let triggerEvent: TriggerEvent?
    private let dynamicMessage: DynamicMessage?
    
    // MARK: - Session State
    
    /// List of all chat sessions
    var chatSessions: [ChatSession] = []

    /// List of all messages in the current session
    var messages: [ChatMessage] = []
    
    /// Currently active chat session
    var currentSession: ChatSession?
    
    /// Are we loading the list of sessions?
    var isLoading = false
    
    /// Are we loading the current session?
    var isLoadingSession = false
    
    // MARK: - AI Agent State
    
    /// Agent internal state
    var state: AgentState = .idle
    
    /// Is the AI currently streaming partial messages?
    var isStreaming: Bool = false

    /// Task to handle streaming
    private var chatTask: Task<Void, Never>?

    /// Stop generating flag
    private var stopGenerating = false
    
    /// Is the AI currently uploading images?
    var isUploading: Bool = false

    /// Suggested questions for the user
    var suggestedQuestions: [SuggestedQuestion] = []
    var isLoadingSuggestions: Bool = false
    
    // MARK: - Private Internals
    
    private let database = Database()
    private let collection = "chat_sessions"
    
    // Setup tracking - new properties
    private var isSetupComplete = false
    private var agent: Agent!
    
    private let aiClient = OpenAIService()
    private let metadataTracker = MetadataTracker()
    private let documentManager = DocumentManager()
    
    /// Temporarily holds a new session until first user message arrives
    private var unsavedSession: ChatSession?
    
    private let lastSessionKey = "lastSessionId"
    private let defaults = UserDefaults.standard
    
    // MARK: - Initialization
    
    init(
        triggerEvent: TriggerEvent? = nil,
        dynamicMessage: DynamicMessage? = nil,
        healthProfile: String? = nil
    ) {
        self.triggerEvent = triggerEvent
        self.dynamicMessage = dynamicMessage
        
        // We'll perform immediate setup but only once
        self.setup()
    }
    
    /// Setup the agent - should be called once before loading sessions
    func setup() {
        // Skip if already setup
        guard !isSetupComplete else { return }
        
        // Get appropriate system prompt based on trigger
        let systemPrompt = if let trigger = triggerEvent {
            String(localized: "SYSTEM_OBSERVER_MODE") + "\n\nContext: \(trigger.context)"
        } else {
            String(localized: "SYSTEM_PROMPT_AI_COMPANION")
        }

        // Initialize agent with selected prompt and our new health tools
        do {
            self.agent = try Agent(
                model: AgenticModels.gpt4,
                tools: [
                    SearchMedicalEvidenceTool.self,
                    LogJournalEntryTool.self,
                    GeneralSearchTool.self,
                    ManageHealthEventTool.self,
                    ManageHealthReportTool.self,
                    DisplayMedicationTool.self,
                    ThinkTool.self
                ],
                instructions: systemPrompt
            )
            
            // Add metadata tracker to agent
            self.agent.addCallbacks(metadataTracker)
            
            // Observe state changes in the agent
            agent.onStateChange = { [weak self] newState in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.state = newState
                    
                    // Generate suggestions when AI becomes idle
                    if case .idle = newState {
                        Task {
                            await self.generateSuggestedQuestions()
                        }
                    }
                }
            }
            
            // Mark setup as complete
            isSetupComplete = true
            
        } catch {
            print("❌ Failed to initialize Agent: \(error)")
            // Reset loading states in case of error
            isLoading = false
            isLoadingSession = false
        }
    }
    
    // MARK: - Session Initialization / Management
    
    /// Loads all chat sessions from the database with real-time updates
    func loadChatSessions() {
        isLoading = true
        isLoadingSession = true  // Explicitly set to ensure state consistency
        
        // If we have a dynamic message or trigger event, always create a new session first
        if dynamicMessage != nil || triggerEvent != nil {
            Task {
                await createNewSession(
                    triggerEvent: triggerEvent,
                    dynamicMessage: dynamicMessage
                )
            }
            return
        }
        
        // Fast path: First try to load the most recent session
        if let lastSessionId = defaults.string(forKey: lastSessionKey) {
            // Load the specific session first
            do {
                try database.fetchRealTimeListener(fromCollection: collection, documentId: lastSessionId) { [weak self] documentSnapshot, _, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("Error loading last session: \(error)")
                        self.loadAllSessions() // Fallback to loading all sessions
                        return
                    }
                    
                    if let documentSnapshot = documentSnapshot,
                       let session = try? documentSnapshot.data(as: ChatSession.self) {
                        var loadedSession = session
                        loadedSession.id = documentSnapshot.documentID
                        DispatchQueue.main.async {
                            // Load this session immediately if no current session
                            if self.currentSession == nil {
                                self.loadSession(loadedSession)
                            }
                            // Then load all sessions in background
                            self.loadAllSessions()
                        }
                    } else {
                        // Session not found, fall back to loading all
                        self.loadAllSessions()
                    }
                }
            } catch {
                print("Error setting up listener: \(error)")
                loadAllSessions() // Fallback to loading all sessions
            }
        } else {
            // No cached session ID, try to get most recent session
            loadMostRecentSession()
        }
    }
    
    /// Loads the most recent session only
    private func loadMostRecentSession() {
        database.fetchRealTimeListener(fromCollection: collection, orderBy: "createdAt", descending: true, limit: 1) { [weak self] _, querySnapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error loading most recent session: \(error)")
                self.loadAllSessions() // Fallback to loading all
                return
            }
            
            if let querySnapshot = querySnapshot,
               let mostRecent = querySnapshot.documents.first,
               let session = try? mostRecent.data(as: ChatSession.self) {
                var loadedSession = session
                loadedSession.id = mostRecent.documentID
                DispatchQueue.main.async {
                    // Only load if no current session and no special modes
                    if self.currentSession == nil && self.triggerEvent == nil && self.dynamicMessage == nil {
                        self.loadSession(loadedSession)
                    }
                    // Then load all sessions in background
                    self.loadAllSessions()
                }
            } else {
                // No sessions exist, create new one
                Task {
                    await self.createNewSession(
                        triggerEvent: self.triggerEvent,
                        dynamicMessage: self.dynamicMessage
                    )
                }
            }
        }
    }

    /// Loads all sessions in the background
    func loadAllSessions() {
        database.fetchRealTimeListener(fromCollection: collection, orderBy: "createdAt") { [weak self] _, querySnapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error loading chat sessions: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isLoadingSession = false
                }
                return
            }
            
            if let querySnapshot = querySnapshot {
                let sessions = querySnapshot.documents.compactMap { document -> ChatSession? in
                    do {
                        var session = try document.data(as: ChatSession.self)
                        session.id = document.documentID
                        return session
                    } catch {
                        print("Error decoding chat session: \(error)")
                        return nil
                    }
                }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Update sessions while preserving current session state
                    self.chatSessions = sessions.map { session in
                        if session.id == self.currentSession?.id {
                            return self.currentSession ?? session
                        }
                        return session
                    }
                    
                    // If we have a current session, ensure it's up to date
                    if let currentId = self.currentSession?.id,
                       let updatedSession = sessions.first(where: { $0.id == currentId }) {
                        // Update current session with latest data
                        var mergedSession = updatedSession
                        mergedSession.messages = self.currentSession?.messages ?? updatedSession.messages
                        self.currentSession = mergedSession
                        self.messages = mergedSession.messages
                    }
                    
                    self.isLoading = false
                    self.isLoadingSession = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.isLoadingSession = false
                }
            }
        }
    }
    
    /// Loads a specific chat session as the current session
    func loadSession(_ session: ChatSession) {
        isLoadingSession = true
        unsavedSession = nil  // Clear any unsaved session
        
        // Reset metadata tracker when loading new session
        metadataTracker.reset()
        
        // Cache the current session ID immediately
        if let sessionId = session.id {
            defaults.set(sessionId, forKey: lastSessionKey)
        }
        
        // Update state immediately
        self.currentSession = session
        self.messages = session.messages
        
        // Sync messages with agent
        self.agent.setMessages(session.messages)
        
        // Small delay just for UI smoothness
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isLoadingSession = false
        }
    }
    
    /// Deletes a chat session from the database
    func deleteSession(_ session: ChatSession) {
        Task {
            do {
                guard let documentId = session.id else { return }
                try await database.deleteData(fromCollection: collection, documentId: documentId)
                
                // If we're deleting the current session, create a new one
                if currentSession?.id == session.id {
                    Task {
                        await createNewSession()
                    }
                }
                
                // Remove the session from our local array
                chatSessions.removeAll(where: { $0.id == session.id })
                
            } catch {
                print("Error deleting session: \(error)")
            }
        }
    }
    
    // MARK: - Creating a New Session
    
    /// Creates a brand-new session with an optional system prompt (e.g., health context)
    /// and a default assistant message ("Hi, how can I help?").
    ///
    /// The session will only be *saved* once the first user message arrives,
    /// preventing "empty" sessions in the DB.
    func createNewSession(
        triggerEvent: TriggerEvent? = nil,
        dynamicMessage: DynamicMessage? = nil
    ) async {
        stopStreaming()
        
        // Reset metadata tracker for new session
        metadataTracker.reset()
        
        var newSession = ChatSession(title: "New Chat")
        
        // First system message - AI instructions
        let systemPrompt = if let trigger = triggerEvent {
            String(localized: "SYSTEM_OBSERVER_MODE") + "\n\nContext: \(trigger.context)"
        } else {
            String(localized: "SYSTEM_PROMPT_AI_COMPANION")
        }
        
        let systemMsg = ChatMessage(message: .system(content: .text(systemPrompt)))
        newSession.messages.append(systemMsg)
        
        // Second system message - Health Profile
        if let healthProfile = try? await healthProfile.getHealthProfileMarkdown() {
            let healthProfileMsg = ChatMessage(message: .system(content: .text(healthProfile)))
            newSession.messages.append(healthProfileMsg)
        }
        
        // Initial assistant message
        let initialMessage: String
        if let trigger = triggerEvent {
            initialMessage = trigger.question
        } else if let dynamicMsg = dynamicMessage {
            initialMessage = dynamicMsg.message
        } else {
            initialMessage = String(localized: "COMPANION_INTRO_MESSAGE")
        }
        
        let assistantMsg = ChatMessage(message: .assistant(content: .text(initialMessage)))
        newSession.messages.append(assistantMsg)
        
        // Clear any existing cached session since we're creating new
        defaults.removeObject(forKey: lastSessionKey)
        
        // Mark this as an unsaved session
        unsavedSession = newSession
        
        // Update current state and sync with agent
        await MainActor.run {
            currentSession = newSession
            messages = newSession.messages
            agent.setMessages(newSession.messages)  // Sync with agent
        }
    }
    
    // MARK: - Sending Messages
    
    // MARK: - Public Methods
    
    /// Sends a user's message to the AI and handles streaming responses.
    public func sendMessage(_ parts: [UserContent.Part], attachments: [Attachment] = [], requiredTool: String? = nil) {
        suggestedQuestions = []
        
        // Create user message with parts
        let userMessage = Message.user(content: .parts(parts))
        let chatMessage = ChatMessage(message: userMessage)

        // Add attachments to the message
        if !attachments.isEmpty {
            print("📎 Adding \(attachments.count) attachments to message")
            chatMessage.attachments = attachments
            
        }
        
        // Add user message to current session
        storeMessage(chatMessage)
        
        // Cancel any existing chat task
        stopStreaming()
        
        chatTask = Task {
            isStreaming = true
            defer { 
                isStreaming = false 
                state = .idle
            }
            
            do {                
                // Stream response, now passing the requiredTool parameter
                for try await message in agent.sendStream(chatMessage, requiredTool: requiredTool) {
                    if Task.isCancelled { break }
                    
                    await MainActor.run {
                        handleStreamedMessage(message)
                    }
                }
                
                // End streaming and store final message
                await MainActor.run {
                    if let last = currentSession?.messages.last, last.isPending {
                        var finalMessage = last
                        finalMessage.isPending = false
                        // Store the final message
                        storeMessage(finalMessage)
                        
                        // Update the message in current session
                        if var currentSession = currentSession {
                            if let lastIndex = currentSession.messages.lastIndex(where: { $0.isPending }) {
                                currentSession.messages[lastIndex] = finalMessage
                            }
                            self.currentSession = currentSession
                        }
                    }
                }
                
            } catch {
                await MainActor.run {
                    // Remove pending message on error
                    if let last = messages.last, last.isPending {
                        messages.removeLast()
                    }
                    state = .error(error.asAIError)
                }
            }
        }
    }
    
    /// Sends a user's message to the AI and handles streaming responses.
    public func sendMessage(_ text: String, requiredTool: String? = nil) {
        sendMessage([.text(text)], requiredTool: requiredTool)
    }
    
    // MARK: - Private Helpers
    
    /// Called for partial tokens
    /// DO NOT STORE anything here
    @MainActor
    private func handleStreamedMessage(_ message: ChatMessage) {
        guard var currentSession = currentSession else { return }
        
        switch message.message {
        case .assistant:
            if message.isPending {
                // Update existing pending message or add new one
                if let lastIndex = currentSession.messages.lastIndex(where: { $0.isPending }) {
                    currentSession.messages[lastIndex] = message
                } else {
                    currentSession.messages.append(message)
                }
            }
            
        case .tool:
            // Store tool messages immediately
            currentSession.messages.append(message)
            storeMessage(message)
            
        default:
            currentSession.messages.append(message)
            storeMessage(message)
        }
        
        // Update session in chat sessions array
        if let index = chatSessions.firstIndex(where: { $0.id == currentSession.id }) {
            chatSessions[index] = currentSession
        }
        
        // Update current session
        self.currentSession = currentSession
    }

    
    /// Adds a new message to the current session and updates storage
    func storeMessage(_ message: ChatMessage) {        
        // Append to local messages array if not already appended
        if !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
        }
        
        // Update current session
        if var currentSession = currentSession {
            currentSession.messages = messages
            
            
            // Check if it's a user message by examining the wrapped Message enum
            let isUserMessage = if case .user = message.message { true } else { false }
            
            // If this is an unsaved session and it's a user message, save it
            if currentSession.id == nil && isUserMessage {
                // Generate title for the new session
                Task {
                    do {
                        currentSession.title = try await generateTitle(for: currentSession)
                        
                        // Save the session with the generated title
                        database.saveData(inCollection: collection, data: currentSession) { [weak self] result in
                            guard let self = self else { return }
                            
                            switch result {
                            case .success(let docID):
                                currentSession.id = docID
                                self.currentSession = currentSession
                                // Cache the new session ID
                                self.defaults.set(docID, forKey: self.lastSessionKey)
                                self.unsavedSession = nil
                            case .failure(let error):
                                print("❌ Error saving new session: \(error)")
                            }
                        }
                    } catch {
                        print("❌ Error generating title: \(error)")
                    }
                }
            } else if currentSession.id != nil {
                // Update existing session
                updateChatSession(currentSession)
                // Ensure the session ID is cached
                defaults.set(currentSession.id, forKey: lastSessionKey)
            }
        }
    }

    func stopStreaming() {
        chatTask?.cancel()
        chatTask = nil
        isStreaming = false
        metadataTracker.reset()
    }

    
    // MARK: - Title Generation
    
    /// Generate a short, concise title for the conversation
    func generateTitle(for session: ChatSession) async throws -> String {
        let context = session.messages.map { message in
            switch message.message {
            case .user:
                return "User: \(message.displayContent)"
            case .assistant:
                return "Assistant: \(message.displayContent)"
            case .system:
                return "System: \(message.displayContent)"
            case .tool:
                return "Tool: \(message.displayContent)"
            case .developer:
                return "Developer: \(message.displayContent)"
            }
        }.joined(separator: "\n")
        
        let prompt = """
        Generate a short, concise title (max 5 words) that captures \
        the main topic of this conversation:
        
        \(context)

        Created based on the last message inquiry of the user.
        """
        
        // Create the message parameter correctly
        let message = ChatQuery.ChatCompletionMessageParam(
            role: .user,
            content: prompt
        )
        
        let query = ChatQuery(
            messages: [message].compactMap { $0 },
            model: "gpt-4o-mini"
        )
        
        let result = try await aiClient.chats(query: query)
        return result.choices.first?.message.content?.string ?? "New Chat"
    }
    
    // MARK: - Upsert (Create or Update)
    
    /// Creates or updates a `ChatSession` in Firestore; returns the updated session.
    private func upsertSession(_ session: ChatSession) async throws -> ChatSession {
        // If no doc ID, create new
        if session.id == nil {
            return try await withCheckedThrowingContinuation { continuation in
                database.saveData(inCollection: collection, data: session) { result in
                    switch result {
                    case .success(let docID):
                        var saved = session
                        saved.id = docID
                        continuation.resume(returning: saved)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        } else {
            // Otherwise, update
            return try await withCheckedThrowingContinuation { continuation in
                guard let docID = session.id else {
                    return continuation.resume(throwing: NSError(domain: "MissingDocID", code: -1))
                }
                database.saveData(inCollection: collection, data: session, documentId: docID) { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: session)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }


    /// Updates an existing chat session in the database
    private func updateChatSession(_ session: ChatSession) {
        guard let documentId = session.id else {
            print("❌ Cannot update session without ID")
            return
        }
        
        database.saveData(
            inCollection: collection,
            data: session,
            documentId: documentId
        ) { result in
            switch result {
            case .success:
                print("✅ Successfully updated chat session")
                // Update local state atomically
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // Update the session in the local array first
                    if let index = self.chatSessions.firstIndex(where: { $0.id == session.id }) {
                        self.chatSessions[index] = session
                    }
                    // Then update current session if it matches
                    if self.currentSession?.id == session.id {
                        self.currentSession = session
                        self.messages = session.messages
                    }
                }
                
            case .failure(let error):
                print("❌ Error updating chat session: \(error)")
            }
        }
    }

    
    /// Updates the title of a session
    func updateSessionTitle(_ session: ChatSession, newTitle: String) {
        var updatedSession = session
        updatedSession.title = newTitle
        updatedSession.lastModified = Date()
        
        // Use updateChatSession instead of upsertSession for consistency
        updateChatSession(updatedSession)
    }


    /// Uploads an image to Firebase Storage and returns the URL
    func uploadImage(_ data: Data) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let fileName = "\(UUID().uuidString).jpg"
            
            database.uploadFile(data: data, withFileName: fileName, mimeType: "image/jpeg") { result in
                switch result {
                case .success(let urlString):
                    if let url = URL(string: urlString) {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: NSError(domain: "Invalid URL", code: -1))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func generateSuggestedQuestions() async {
        guard !messages.isEmpty else { return }
        
        do {
            await MainActor.run { self.isLoadingSuggestions = true }
            defer { Task { @MainActor in self.isLoadingSuggestions = false } }
            
            // Get current conversation context and format it properly
            var contextMessages = currentSession?.messages.map(\.message) ?? []
            
            // Filter and reformat messages to ensure proper sequence
            var formattedMessages: [Message] = []
            var lastAssistantMessage: Message? = nil
            
            for message in contextMessages {
                switch message {
                case .tool(let content, _, let toolCallId):
                    // Only include tool message if we have a preceding assistant message with tool_calls
                    if case .assistant(_, _, let toolCalls) = lastAssistantMessage,
                       toolCalls != nil {
                        formattedMessages.append(message)
                    }
                case .assistant(_, _, let toolCalls):
                    lastAssistantMessage = message
                    formattedMessages.append(message)
                default:
                    formattedMessages.append(message)
                }
            }
            
            // Add instruction to generate questions
            let request = ChatCompletionRequest(
                model: "gpt-4o-mini",
                messages: formattedMessages + [
                    .system(content: .text("""
                        Generate 2 follow-up questions that the patient(user) might want to ask based on the conversation context.

                        Instructions:  
                        - Questions should be relevant to the last topic discussed
                        - Question the user(patient) could naturally ask to a doctor

                        Each question should be:
                        - A single short sentence (max 8 words)
                        - Relevant to the last topic discussed
                        - Something a patient would naturally ask
                        - Not repeating previous questions
                        """))
                ],
                responseFormat: .jsonSchema(
                    name: "suggested_questions",
                    description: "Follow-up questions the patient may ask",
                    schemaBuilder: SuggestedQuestions.schema()
                        .title("Suggested Questions")
                        .description("A list of relevant follow-up questions"),
                    strict: true
                )
            )
            
            // Generate questions using the LLM
            let suggestions: SuggestedQuestions = try await agent.llm.generateObject(request: request)
            
            // Update UI on main thread
            await MainActor.run {
                self.suggestedQuestions = suggestions.questions
            }
        } catch {
            print("Error generating suggestions: \(error)")
            await MainActor.run {
                self.suggestedQuestions = []
            }
        }
    }

    /// Uploads files to storage and parses their content into markdown
    /// Returns attachments with both the URL and parsed content
    func parseAndUploadFiles(_ urls: [URL]) async throws -> [Attachment] {
        return try await documentManager.parseAndUploadFiles(urls)
    }

}
