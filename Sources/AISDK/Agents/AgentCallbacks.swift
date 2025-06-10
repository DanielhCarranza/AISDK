import Foundation

/// Represents the result of a callback that can modify agent behavior
public enum CallbackResult {
    /// Continue normal execution
    case `continue`
    /// Cancel the current operation
    case cancel
    /// Replace the current message/response with a new one
    case replace(Message)
}

/// Protocol defining all possible agent callbacks
public protocol AgentCallbacks: AnyObject {
    // Message Events
    func onMessageReceived(message: Message) async -> CallbackResult
    func onMessageProcessed(message: Message) async -> CallbackResult
    
    // Tool Events
    func onBeforeToolExecution(name: String, arguments: String) async -> CallbackResult
    func onAfterToolExecution(name: String, result: String) async -> CallbackResult
    func onToolError(name: String, error: Error) async -> CallbackResult
    
    // LLM Events
    func onBeforeLLMRequest(messages: [Message]) async -> CallbackResult
    func onAfterLLMResponse(response: Message) async -> CallbackResult
    func onStreamChunk(chunk: Message) async -> CallbackResult
}

/// Default implementations to make all methods optional
public extension AgentCallbacks {
    func onMessageReceived(message: Message) async -> CallbackResult { .continue }
    func onMessageProcessed(message: Message) async -> CallbackResult { .continue }
    func onBeforeToolExecution(name: String, arguments: String) async -> CallbackResult { .continue }
    func onAfterToolExecution(name: String, result: String) async -> CallbackResult { .continue }
    func onToolError(name: String, error: Error) async -> CallbackResult { .continue }
    func onBeforeLLMRequest(messages: [Message]) async -> CallbackResult { .continue }
    func onAfterLLMResponse(response: Message) async -> CallbackResult { .continue }
    func onStreamChunk(chunk: Message) async -> CallbackResult { .continue }
}

/// Callback handler that tracks metadata during streaming
public class MetadataTracker: AgentCallbacks {
    private let lock = NSLock()
    private var toolMetadata: [String: ToolMetadata] = [:]
    public private(set) var lastMetadata: ToolMetadata?
    
    public init() {}
    
    public func setMetadata(_ metadata: ToolMetadata?, forToolCallId toolCallId: String) {
        // Use withLock for async-safe locking
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    self.lock.withLock {
                        if let metadata = metadata {
                            self.toolMetadata[toolCallId] = metadata
                            self.lastMetadata = metadata
                        } else {
                            self.toolMetadata.removeValue(forKey: toolCallId)
                        }
                    }
                }
            }
        }
    }
    
    public func metadata(forToolCallId toolCallId: String) -> ToolMetadata? {
        lock.withLock {
            toolMetadata[toolCallId]
        }
    }
    
    public func reset() {
        // Use withLock instead of lock/unlock
        lock.withLock {
            toolMetadata.removeAll()
            lastMetadata = nil
        }
    }
    
    // MARK: - AgentCallbacks
    
    public func onAfterToolExecution(name: String, result: String) async -> CallbackResult {
        return .continue
    }
    
    public func onMessageProcessed(message: Message) async -> CallbackResult {
        if case .assistant = message {
            // Use withLock instead of lock/unlock
            lock.withLock {
                toolMetadata.removeAll()
            }
        }
        return .continue
    }
} 