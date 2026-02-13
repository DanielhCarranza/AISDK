//
//  StreamingPersistenceBuffer.swift
//  AISDK
//
//  Debounced persistence buffer for streaming message updates.
//

import Foundation

/// Buffers streaming message deltas and persists them with debounce.
///
/// During streaming, text deltas arrive frequently. This buffer coalesces
/// rapid updates into periodic saves, reducing write pressure on the store.
public actor StreamingPersistenceBuffer {
    private let store: any SessionStore
    private let sessionId: String
    private let debounceInterval: Duration

    private var pendingMessage: AIMessage?
    private var debounceTask: Task<Void, Never>?

    /// Create a streaming persistence buffer.
    /// - Parameters:
    ///   - store: The session store to persist to.
    ///   - sessionId: The session to update.
    ///   - debounceInterval: Time to wait before persisting (default: 500ms).
    public init(
        store: any SessionStore,
        sessionId: String,
        debounceInterval: Duration = .milliseconds(500)
    ) {
        self.store = store
        self.sessionId = sessionId
        self.debounceInterval = debounceInterval
    }

    /// Buffer a message delta for debounced persistence.
    ///
    /// The most recent message is held and persisted after `debounceInterval`
    /// of inactivity (no new deltas). Each new call resets the timer.
    public func bufferDelta(_ message: AIMessage) {
        pendingMessage = message
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.debounceInterval ?? .milliseconds(500))
                await self?.persistPending()
            } catch {
                // Cancelled — a new delta came in or flush was called
            }
        }
    }

    /// Immediately persist any pending message.
    ///
    /// Called at step boundaries and stream completion to ensure
    /// the latest state is saved.
    public func flush() async {
        debounceTask?.cancel()
        debounceTask = nil
        await persistPending()
    }

    /// Check if there's a pending message waiting to be persisted.
    public var hasPending: Bool {
        pendingMessage != nil
    }

    // MARK: - Private

    private func persistPending() async {
        guard let message = pendingMessage else { return }
        pendingMessage = nil
        do {
            try await store.updateLastMessage(message, inSession: sessionId)
        } catch {
            // Persistence failure during streaming is non-fatal.
            // The ChatViewModel will handle final persistence.
        }
    }
}
