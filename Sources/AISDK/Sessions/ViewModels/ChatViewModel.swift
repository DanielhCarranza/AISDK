//
//  ChatViewModel.swift
//  AISDK
//
//  Observable ViewModel integrating Agent sessions with streaming persistence.
//

import Foundation

/// Observable ViewModel for managing a chat session with an Agent.
///
/// Handles sending messages, streaming responses, persistence, and
/// session lifecycle (resume, rewind, cancel, retry).
///
/// Usage:
/// ```swift
/// let vm = ChatViewModel(agent: myAgent, store: InMemorySessionStore(), userId: "user_1")
/// await vm.createSession()
/// await vm.send("Hello!")
/// ```
@Observable
@MainActor
public final class ChatViewModel {
    // MARK: - Published State

    /// The current session (contains messages, status, metadata)
    public private(set) var session: AISession

    /// Whether the agent is currently streaming a response
    public private(set) var isStreaming: Bool = false

    /// The most recent error (cleared on next send)
    public private(set) var error: Error?

    /// Warning about persistence failures (non-fatal)
    public private(set) var persistenceWarning: String?

    // MARK: - Dependencies

    private let agent: Agent
    private let store: any SessionStore
    private var persistenceBuffer: StreamingPersistenceBuffer?
    private var streamingTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Create a ChatViewModel for a new or existing session.
    /// - Parameters:
    ///   - agent: The agent to use for generating responses.
    ///   - store: The session store for persistence.
    ///   - session: An existing session to resume, or nil to create later.
    public init(agent: Agent, store: any SessionStore, session: AISession? = nil) {
        self.agent = agent
        self.store = store
        self.session = session ?? AISession(userId: "")
    }

    // MARK: - Session Lifecycle

    /// Create and persist a new session.
    public func createSession(userId: String, title: String? = nil) async throws {
        let newSession = AISession(userId: userId, title: title)
        session = try await store.create(newSession)
    }

    /// Load and resume an existing session.
    public func loadSession(id: String) async throws {
        guard let loaded = try await store.load(id: id) else {
            throw SessionStoreError.notFound(sessionId: id)
        }
        session = loaded
    }

    // MARK: - Sending Messages

    /// Send a user message and stream the agent's response.
    public func send(_ text: String) async {
        guard !isStreaming else { return }
        error = nil
        persistenceWarning = nil

        // Append user message
        let userMessage = AIMessage.user(text)
        session.messages.append(userMessage)
        session.lastActivityAt = Date()

        // Persist user message
        persistInBackground { store, sessionId in
            try await store.appendMessage(userMessage, toSession: sessionId)
        }

        await streamAgentResponse()
    }

    /// Resume streaming from the current session state.
    ///
    /// Used after loading an incomplete session or after cancel.
    public func resume() async {
        guard !isStreaming else { return }
        error = nil
        session.isLastMessageComplete = true
        await streamAgentResponse()
    }

    /// Rewind the session to a checkpoint and optionally re-stream.
    public func rewind(to checkpointIndex: Int) async {
        cancel()
        session.rewind(to: checkpointIndex)
        persistInBackground { store, sessionId in
            try await store.save(self.session)
        }
    }

    /// Retry the last user turn by removing all messages after the last user message.
    public func retryLastTurn() async {
        guard let lastUserIndex = session.messages.lastIndex(where: { $0.role == .user }) else { return }
        cancel()
        session.messages = Array(session.messages.prefix(lastUserIndex + 1))
        session.isLastMessageComplete = true
        await streamAgentResponse()
    }

    /// Cancel the current streaming response.
    public func cancel() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        session.isLastMessageComplete = false
    }

    // MARK: - Private Streaming

    private func streamAgentResponse() async {
        isStreaming = true
        session.isLastMessageComplete = false

        persistenceBuffer = StreamingPersistenceBuffer(
            store: store,
            sessionId: session.id
        )

        let stream = agent.streamExecute(messages: session.messages)

        streamingTask = Task { [weak self] in
            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    await self?.handleStreamEvent(event)
                }
                await self?.finishStreaming()
            } catch {
                await MainActor.run {
                    self?.error = error
                    self?.isStreaming = false
                }
            }
        }

        await streamingTask?.value
    }

    private func handleStreamEvent(_ event: AIStreamEvent) async {
        switch event {
        case .start:
            // Stream started — create placeholder assistant message
            let assistantMessage = AIMessage(role: .assistant, content: .text(""))
            session.messages.append(assistantMessage)

        case .textDelta(let delta):
            guard !session.messages.isEmpty, session.messages.last?.role == .assistant else { return }
            session.messages[session.messages.count - 1].appendText(delta)
            if let buffer = persistenceBuffer {
                await buffer.bufferDelta(session.messages[session.messages.count - 1])
            }

        case .toolCallStart(let id, let name):
            guard !session.messages.isEmpty, session.messages.last?.role == .assistant else { return }
            var calls = session.messages[session.messages.count - 1].toolCalls ?? []
            calls.append(AIMessage.ToolCall(id: id, name: name, arguments: ""))
            session.messages[session.messages.count - 1].toolCalls = calls

        case .toolCallDelta(let id, let argumentsDelta):
            guard !session.messages.isEmpty, session.messages.last?.role == .assistant,
                  var calls = session.messages[session.messages.count - 1].toolCalls,
                  let idx = calls.firstIndex(where: { $0.id == id }) else { return }
            calls[idx].arguments += argumentsDelta
            session.messages[session.messages.count - 1].toolCalls = calls

        case .toolResult(let id, let result, _):
            let toolMessage = AIMessage.tool(result, toolCallId: id)
            session.messages.append(toolMessage)
            persistInBackground { store, sessionId in
                try await store.appendMessage(toolMessage, toSession: sessionId)
            }

        case .stepFinish:
            session.lastCheckpointIndex = session.messages.count - 1
            if let buffer = persistenceBuffer {
                await buffer.flush()
            }

        case .stepStart(let stepIndex) where stepIndex > 0:
            // New step after tool results — create new assistant message
            let assistantMessage = AIMessage(role: .assistant, content: .text(""))
            session.messages.append(assistantMessage)

        case .finish:
            break // Handled in finishStreaming()

        case .error(let err):
            self.error = err

        default:
            break
        }
    }

    private func finishStreaming() async {
        // Flush any pending persistence
        if let buffer = persistenceBuffer {
            await buffer.flush()
        }
        persistenceBuffer = nil

        session.isLastMessageComplete = true
        session.lastActivityAt = Date()
        isStreaming = false

        // Persist final session state
        persistInBackground { store, sessionId in
            try await store.save(self.session)
        }
    }

    // MARK: - Background Persistence

    private func persistInBackground(_ operation: @Sendable @escaping (any SessionStore, String) async throws -> Void) {
        let store = self.store
        let sessionId = self.session.id
        Task.detached { [weak self] in
            do {
                try await operation(store, sessionId)
            } catch {
                await MainActor.run {
                    self?.persistenceWarning = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
}
