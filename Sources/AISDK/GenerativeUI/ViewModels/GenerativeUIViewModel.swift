//
//  GenerativeUIViewModel.swift
//  AISDK
//
//  Observable ViewModel for GenerativeUI with update batching
//  Implements jank prevention through 60fps update throttling
//

#if canImport(SwiftUI)
import Foundation
import SwiftUI

// MARK: - UITreeUpdate

/// Represents a pending update to the UITree
public struct UITreeUpdate: Sendable {
    /// The type of update
    public enum UpdateType: Sendable {
        /// Replace the entire tree
        case replaceTree(UITree)
        /// Clear the tree entirely
        case clear
    }

    /// The update operation to perform
    public let type: UpdateType

    /// Timestamp when the update was created
    public let timestamp: Date

    public init(type: UpdateType, timestamp: Date = Date()) {
        self.type = type
        self.timestamp = timestamp
    }
}

// MARK: - GenerativeUIViewModelError

/// Errors that can occur in GenerativeUIViewModel
public enum GenerativeUIViewModelError: Error, Sendable {
    /// The update could not be applied
    case updateFailed(reason: String)
    /// The tree is in an invalid state
    case invalidTreeState
}

extension GenerativeUIViewModelError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .updateFailed(let reason):
            return "UITree update failed: \(reason)"
        case .invalidTreeState:
            return "UITree is in an invalid state"
        }
    }
}

// MARK: - GenerativeUIViewModel

/// Observable ViewModel for managing UITree state with update batching
///
/// `GenerativeUIViewModel` provides a reactive bridge between UITree data
/// and SwiftUI views. It implements update batching to prevent UI jank
/// by throttling updates to 60fps (16ms intervals).
///
/// ## Features
/// - @Observable integration for SwiftUI binding
/// - Update batching for smooth 60fps rendering (true throttle, not debounce)
/// - Loading/error state management
/// - Stream subscription for real-time updates
/// - Thread-safe state management via MainActor
///
/// ## Basic Usage
/// ```swift
/// @MainActor
/// struct ContentView: View {
///     @State private var viewModel = GenerativeUIViewModel()
///
///     var body: some View {
///         Group {
///             if viewModel.isLoading {
///                 ProgressView()
///             } else if let tree = viewModel.tree {
///                 GenerativeUITreeView(tree: tree)
///             } else if let error = viewModel.error {
///                 Text("Error: \(error.localizedDescription)")
///             }
///         }
///         .task {
///             await viewModel.loadTree(from: jsonData)
///         }
///     }
/// }
/// ```
///
/// ## Streaming Usage
/// ```swift
/// // Subscribe to a stream of UITree updates
/// let stream = myLLMService.streamUITree()
/// await viewModel.subscribe(to: stream)
/// ```
///
/// ## Update Batching
/// Updates are throttled using a frame-based approach. When an update arrives,
/// if no frame timer is running, one is started. When the timer fires, all
/// pending updates are applied in order. This ensures updates are processed
/// at most every 16ms (60fps) regardless of how fast they arrive.
@Observable
@MainActor
public final class GenerativeUIViewModel {
    // MARK: - Public State

    /// The current UITree being rendered
    public private(set) var tree: UITree?

    /// Whether the ViewModel is currently loading
    public private(set) var isLoading: Bool = false

    /// The last error that occurred (if any)
    public private(set) var error: (any Error)?

    /// Whether an update is currently being processed
    public private(set) var isUpdating: Bool = false

    // MARK: - Private State

    /// Pending updates to be applied in the next batch
    private var pendingUpdates: [UITreeUpdate] = []

    /// Task for the batched update timer (frame throttle)
    private var updateTask: Task<Void, Never>?

    /// Whether a frame tick is currently scheduled
    private var isFrameScheduled: Bool = false

    /// Current active subscription task
    private var subscriptionTask: Task<Void, Never>?

    /// The frame duration for 60fps (approximately 16.67ms)
    private static let frameDuration: Duration = .milliseconds(16)

    // MARK: - Initialization

    /// Creates a new GenerativeUIViewModel
    ///
    /// - Parameter tree: Optional initial tree to display
    public init(tree: UITree? = nil) {
        self.tree = tree
    }

    /// Creates a GenerativeUIViewModel with an initial tree from JSON
    ///
    /// - Parameters:
    ///   - json: JSON string in json-render format
    ///   - catalog: Optional catalog for validation
    /// - Returns: A configured ViewModel, or nil if parsing fails
    public convenience init?(json: String, catalog: UICatalog? = nil) {
        guard let tree = try? UITree.parse(from: json, validatingWith: catalog) else {
            return nil
        }
        self.init(tree: tree)
    }

    // MARK: - Tree Loading

    /// Load a UITree from JSON data
    ///
    /// Cancels any pending updates and active subscriptions to prevent race conditions.
    ///
    /// - Parameters:
    ///   - data: JSON data in json-render format
    ///   - catalog: Optional catalog for validation
    public func loadTree(from data: Data, catalog: UICatalog? = nil) async {
        // Cancel any existing subscription and pending updates
        cancelSubscription()
        cancelPendingUpdates()

        isLoading = true
        error = nil

        // Parse off MainActor to avoid UI hitching for large trees
        let result: Result<UITree, Error> = await Task.detached {
            do {
                let parsedTree = try UITree.parse(from: data, validatingWith: catalog)
                return .success(parsedTree)
            } catch {
                return .failure(error)
            }
        }.value

        // Apply result on MainActor
        switch result {
        case .success(let parsedTree):
            tree = parsedTree
            isLoading = false
        case .failure(let parseError):
            self.error = parseError
            isLoading = false
        }
    }

    /// Load a UITree from a JSON string
    ///
    /// Cancels any pending updates and active subscriptions to prevent race conditions.
    ///
    /// - Parameters:
    ///   - json: JSON string in json-render format
    ///   - catalog: Optional catalog for validation
    public func loadTree(from json: String, catalog: UICatalog? = nil) async {
        guard let data = json.data(using: .utf8) else {
            error = GenerativeUIViewModelError.updateFailed(reason: "Invalid UTF-8 string")
            isLoading = false
            return
        }
        await loadTree(from: data, catalog: catalog)
    }

    // MARK: - Tree Updates

    /// Set the tree directly
    ///
    /// This bypasses update batching for immediate updates.
    /// Any pending batched updates are cancelled.
    ///
    /// - Parameter tree: The new tree to display
    public func setTree(_ tree: UITree?) {
        cancelPendingUpdates()
        self.tree = tree
        self.error = nil
    }

    /// Clear the current tree and cancel any active subscriptions
    public func clear() {
        cancelSubscription()
        cancelPendingUpdates()
        tree = nil
        error = nil
    }

    /// Cancel pending batched updates
    private func cancelPendingUpdates() {
        pendingUpdates.removeAll()
        updateTask?.cancel()
        updateTask = nil
        isFrameScheduled = false
    }

    /// Schedule an update with throttling
    ///
    /// Updates are throttled (not debounced) for smooth 60fps rendering.
    /// If no frame is scheduled, one is started. Updates arriving while
    /// a frame is pending are batched and applied on the next tick.
    ///
    /// - Parameter update: The update to schedule
    public func scheduleUpdate(_ update: UITreeUpdate) {
        pendingUpdates.append(update)

        // True throttle: only start a frame timer if one isn't running
        guard !isFrameScheduled else { return }
        isFrameScheduled = true

        updateTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.frameDuration)
            } catch {
                return // Cancelled
            }

            guard let self = self else { return }
            await self.processBatchedUpdates()
        }
    }

    /// Process all pending updates in timestamp order
    private func processBatchedUpdates() {
        isFrameScheduled = false

        guard !pendingUpdates.isEmpty else { return }

        isUpdating = true

        // Sort by timestamp and apply in order to preserve semantics
        let sortedUpdates = pendingUpdates.sorted { $0.timestamp < $1.timestamp }

        for update in sortedUpdates {
            applyUpdate(update)
        }

        pendingUpdates.removeAll()
        isUpdating = false
    }

    /// Apply a single update
    private func applyUpdate(_ update: UITreeUpdate) {
        switch update.type {
        case .replaceTree(let newTree):
            tree = newTree
            error = nil

        case .clear:
            tree = nil
        }
    }

    /// Force-apply all pending updates immediately
    private func flushPendingUpdates() {
        updateTask?.cancel()
        processBatchedUpdates()
    }

    // MARK: - Stream Subscription

    /// Subscribe to an async stream of UITree updates
    ///
    /// This method processes a stream of UITree objects, applying each
    /// one as an update. Updates are batched for smooth rendering.
    /// Calling this cancels any previous subscription.
    ///
    /// The stream is processed directly for proper structured cancellation.
    /// Cancellation (including SwiftUI `.task` cancellation) will stop the
    /// subscription cleanly without setting an error state.
    ///
    /// - Parameter stream: An async stream of UITree objects
    ///
    /// ## Example
    /// ```swift
    /// let treeStream = myService.streamGeneratedUI()
    /// await viewModel.subscribe(to: treeStream)
    /// ```
    public func subscribe(to stream: AsyncThrowingStream<UITree, Error>) async {
        // Cancel any pending updates (but not subscription - we might be the subscription)
        cancelPendingUpdates()

        isLoading = true
        error = nil

        do {
            for try await newTree in stream {
                guard !Task.isCancelled else { break }
                scheduleUpdate(UITreeUpdate(type: .replaceTree(newTree)))
            }
        } catch {
            // Ignore CancellationError - it's not a real error, just normal cancellation
            if !(error is CancellationError) && !Task.isCancelled {
                self.error = error
            }
        }

        // Flush pending updates before changing loading state
        flushPendingUpdates()
        isLoading = false
    }

    /// Subscribe to an async stream of UITree updates (non-throwing)
    ///
    /// - Parameter stream: An async stream of UITree objects
    public func subscribe(to stream: AsyncStream<UITree>) async {
        cancelPendingUpdates()

        isLoading = true
        error = nil

        for await newTree in stream {
            guard !Task.isCancelled else { break }
            scheduleUpdate(UITreeUpdate(type: .replaceTree(newTree)))
        }

        // Flush pending updates before changing loading state
        flushPendingUpdates()
        isLoading = false
    }

    /// Start a subscription in the background (fire-and-forget)
    ///
    /// Use this when you need to start a subscription without awaiting completion.
    /// The subscription can be cancelled later via `cancelSubscription()`.
    ///
    /// - Parameter stream: An async stream of UITree objects
    public func startSubscription(to stream: AsyncThrowingStream<UITree, Error>) {
        cancelSubscription()
        subscriptionTask = Task { [weak self] in
            await self?.subscribe(to: stream)
        }
    }

    /// Start a subscription in the background (fire-and-forget)
    ///
    /// Use this when you need to start a subscription without awaiting completion.
    /// The subscription can be cancelled later via `cancelSubscription()`.
    ///
    /// - Parameter stream: An async stream of UITree objects
    public func startSubscription(to stream: AsyncStream<UITree>) {
        cancelSubscription()
        subscriptionTask = Task { [weak self] in
            await self?.subscribe(to: stream)
        }
    }

    // MARK: - Mixed AIStreamEvent Subscription

    /// Subscribe to a mixed text+UI stream from an agent.
    ///
    /// Routes `.textDelta` events to the `onText` callback and `.uiPatch` events
    /// to the internal `SpecStreamCompiler` for incremental UITree building.
    /// Uses the existing 60fps batching for tree updates.
    ///
    /// - Parameters:
    ///   - stream: A mixed stream of `AIStreamEvent` values
    ///   - compiler: The compiler to use for patch application (default: new instance)
    ///   - onText: Callback for text delta events (called on MainActor)
    ///
    /// ## Example
    /// ```swift
    /// let eventStream = agent.streamExecute(messages: messages)
    /// await viewModel.subscribe(
    ///     toEvents: eventStream,
    ///     onText: { text in textBuffer += text }
    /// )
    /// ```
    public func subscribe(
        toEvents stream: AsyncThrowingStream<AIStreamEvent, Error>,
        compiler: SpecStreamCompiler = SpecStreamCompiler(),
        onText: @escaping @MainActor (String) -> Void = { _ in }
    ) async {
        cancelPendingUpdates()

        isLoading = true
        error = nil

        do {
            for try await event in stream {
                guard !Task.isCancelled else { break }

                switch event {
                case .textDelta(let text):
                    onText(text)

                case .uiPatch(let batch):
                    if let newTree = compiler.apply(batch) {
                        scheduleUpdate(UITreeUpdate(type: .replaceTree(newTree)))
                    }

                default:
                    // Other events (toolCall, usage, etc.) are passed through
                    break
                }
            }
        } catch {
            if !(error is CancellationError) && !Task.isCancelled {
                self.error = error
            }
        }

        // Flush pending updates before changing loading state
        flushPendingUpdates()
        isLoading = false
    }

    /// Start a mixed event stream subscription in the background
    public func startSubscription(
        toEvents stream: AsyncThrowingStream<AIStreamEvent, Error>,
        compiler: SpecStreamCompiler = SpecStreamCompiler(),
        onText: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        cancelSubscription()
        subscriptionTask = Task { [weak self] in
            await self?.subscribe(toEvents: stream, compiler: compiler, onText: onText)
        }
    }

    /// Cancel the current stream subscription
    ///
    /// Note: This does NOT cancel pending batched updates. Use `clear()` if you
    /// want to cancel both the subscription and any pending updates.
    public func cancelSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        isLoading = false
    }

    // MARK: - Bidirectional State

    /// Handler called when interactive components emit state changes
    public var onStateChange: UIStateChangeHandler?

    /// Handle a state change from an interactive component.
    ///
    /// Updates the internal UIState and notifies the registered handler.
    /// The handler can forward the event to the agent for reactive responses.
    ///
    /// - Parameter event: The state change event from the component
    public func handleStateChange(_ event: UIStateChangeEvent) {
        // Notify the registered handler
        onStateChange?(event)
    }

    // MARK: - State Accessors

    /// Whether the ViewModel has a tree to display
    public var hasTree: Bool {
        tree != nil
    }

    /// Whether the ViewModel is in an error state
    public var hasError: Bool {
        error != nil
    }

    /// A display-friendly error message
    public var errorMessage: String? {
        error?.localizedDescription
    }
}

// MARK: - Convenience Factory Methods

extension GenerativeUIViewModel {
    /// Creates a ViewModel with a tree loaded from JSON
    ///
    /// - Parameters:
    ///   - data: JSON data in json-render format
    ///   - catalog: Optional catalog for validation
    /// - Returns: A ViewModel, with error set if parsing fails
    public static func loading(
        from data: Data,
        catalog: UICatalog? = nil
    ) async -> GenerativeUIViewModel {
        let viewModel = GenerativeUIViewModel()
        await viewModel.loadTree(from: data, catalog: catalog)
        return viewModel
    }

    /// Creates a ViewModel pre-configured for a streaming use case
    ///
    /// - Returns: A ViewModel in loading state, ready for stream subscription
    public static func streaming() -> GenerativeUIViewModel {
        let viewModel = GenerativeUIViewModel()
        viewModel.isLoading = true
        return viewModel
    }
}

#endif
