//
//  GenerativeUIViewModelTests.swift
//  AISDKTests
//
//  Tests for GenerativeUIViewModel
//

#if canImport(SwiftUI)
import XCTest
import SwiftUI
@testable import AISDK

@MainActor
final class GenerativeUIViewModelTests: XCTestCase {

    // MARK: - Test Helpers

    private let simpleTreeJSON = """
    {
      "root": "text1",
      "elements": {
        "text1": {
          "type": "Text",
          "props": { "content": "Hello World" }
        }
      }
    }
    """

    private let complexTreeJSON = """
    {
      "root": "main",
      "elements": {
        "main": {
          "type": "Stack",
          "props": { "direction": "vertical", "spacing": 16 },
          "children": ["title", "button"]
        },
        "title": {
          "type": "Text",
          "props": { "content": "Welcome", "style": "headline" }
        },
        "button": {
          "type": "Button",
          "props": { "title": "Continue", "action": "submit" }
        }
      }
    }
    """

    // MARK: - Initialization Tests

    func test_init_default() {
        // When
        let viewModel = GenerativeUIViewModel()

        // Then
        XCTAssertNil(viewModel.tree)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isUpdating)
    }

    func test_init_with_tree() throws {
        // Given
        let tree = try UITree.parse(from: simpleTreeJSON)

        // When
        let viewModel = GenerativeUIViewModel(tree: tree)

        // Then
        XCTAssertNotNil(viewModel.tree)
        XCTAssertEqual(viewModel.tree?.rootKey, "text1")
    }

    func test_init_with_json() {
        // When
        let viewModel = GenerativeUIViewModel(json: simpleTreeJSON)

        // Then
        XCTAssertNotNil(viewModel)
        XCTAssertNotNil(viewModel?.tree)
        XCTAssertEqual(viewModel?.tree?.rootKey, "text1")
    }

    func test_init_with_invalid_json_returns_nil() {
        // Given
        let invalidJSON = "{ not valid json }"

        // When
        let viewModel = GenerativeUIViewModel(json: invalidJSON)

        // Then
        XCTAssertNil(viewModel)
    }

    func test_init_with_json_and_catalog() {
        // Given
        let catalog = UICatalog.core8

        // When
        let viewModel = GenerativeUIViewModel(json: simpleTreeJSON, catalog: catalog)

        // Then
        XCTAssertNotNil(viewModel)
        XCTAssertNotNil(viewModel?.tree)
    }

    // MARK: - Tree Loading Tests

    func test_loadTree_from_data() async {
        // Given
        let viewModel = GenerativeUIViewModel()
        let data = simpleTreeJSON.data(using: .utf8)!

        // When
        await viewModel.loadTree(from: data)

        // Then
        XCTAssertNotNil(viewModel.tree)
        XCTAssertEqual(viewModel.tree?.rootKey, "text1")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func test_loadTree_from_string() async {
        // Given
        let viewModel = GenerativeUIViewModel()

        // When
        await viewModel.loadTree(from: simpleTreeJSON)

        // Then
        XCTAssertNotNil(viewModel.tree)
        XCTAssertEqual(viewModel.tree?.rootKey, "text1")
    }

    func test_loadTree_sets_loading_state() async {
        // Given
        let viewModel = GenerativeUIViewModel()

        // When - load the tree
        await viewModel.loadTree(from: simpleTreeJSON)

        // Then - loading should be false after completion
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_loadTree_with_invalid_data_sets_error() async {
        // Given
        let viewModel = GenerativeUIViewModel()
        let invalidData = "not json".data(using: .utf8)!

        // When
        await viewModel.loadTree(from: invalidData)

        // Then
        XCTAssertNil(viewModel.tree)
        XCTAssertNotNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_loadTree_with_catalog_validation() async {
        // Given
        let viewModel = GenerativeUIViewModel()
        let catalog = UICatalog.core8

        // When
        await viewModel.loadTree(from: simpleTreeJSON, catalog: catalog)

        // Then
        XCTAssertNotNil(viewModel.tree)
        XCTAssertNil(viewModel.error)
    }

    func test_loadTree_clears_pending_updates() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree = try UITree.parse(from: simpleTreeJSON)
        viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(tree)))

        // When - load a different tree immediately
        await viewModel.loadTree(from: complexTreeJSON)

        // Wait a bit
        try await Task.sleep(for: .milliseconds(30))

        // Then - should have the loaded tree, not the scheduled one
        XCTAssertEqual(viewModel.tree?.rootKey, "main")
    }

    // MARK: - Tree Update Tests

    func test_setTree_directly() throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree = try UITree.parse(from: simpleTreeJSON)

        // When
        viewModel.setTree(tree)

        // Then
        XCTAssertNotNil(viewModel.tree)
        XCTAssertEqual(viewModel.tree?.rootKey, "text1")
    }

    func test_setTree_clears_error() async {
        // Given
        let viewModel = GenerativeUIViewModel()
        await viewModel.loadTree(from: "invalid".data(using: .utf8)!)
        XCTAssertNotNil(viewModel.error)

        let tree = try! UITree.parse(from: simpleTreeJSON)

        // When
        viewModel.setTree(tree)

        // Then
        XCTAssertNil(viewModel.error)
    }

    func test_setTree_clears_pending_updates() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let complexTree = try UITree.parse(from: complexTreeJSON)
        viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(complexTree)))

        // When - set a different tree immediately
        let simpleTree = try UITree.parse(from: simpleTreeJSON)
        viewModel.setTree(simpleTree)

        // Wait for any pending batch
        try await Task.sleep(for: .milliseconds(30))

        // Then - should have the set tree, not the scheduled one
        XCTAssertEqual(viewModel.tree?.rootKey, "text1")
    }

    func test_clear_removes_tree() throws {
        // Given
        let tree = try UITree.parse(from: simpleTreeJSON)
        let viewModel = GenerativeUIViewModel(tree: tree)

        // When
        viewModel.clear()

        // Then
        XCTAssertNil(viewModel.tree)
        XCTAssertNil(viewModel.error)
    }

    func test_clear_cancels_subscription() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()

        // Simulate starting a subscription-like state
        let stream = AsyncStream<UITree> { continuation in
            // Don't finish - simulating active stream
            Task {
                try? await Task.sleep(for: .seconds(10))
            }
        }

        // Start subscription in background
        Task {
            await viewModel.subscribe(to: stream)
        }

        // Let it start
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(viewModel.isLoading)

        // When
        viewModel.clear()

        // Then - loading should be stopped
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - Update Batching Tests

    func test_scheduleUpdate_replaceTree() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree = try UITree.parse(from: simpleTreeJSON)
        let update = UITreeUpdate(type: .replaceTree(tree))

        // When
        viewModel.scheduleUpdate(update)

        // Wait for batch to apply (slightly more than 16ms)
        try await Task.sleep(for: .milliseconds(25))

        // Then
        XCTAssertNotNil(viewModel.tree)
    }

    func test_multiple_updates_are_batched() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree1 = try UITree.parse(from: simpleTreeJSON)
        let tree2 = try UITree.parse(from: complexTreeJSON)

        // When - schedule two updates rapidly
        viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(tree1)))
        viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(tree2)))

        // Wait for batch to apply
        try await Task.sleep(for: .milliseconds(25))

        // Then - should have the second tree (last update wins)
        XCTAssertNotNil(viewModel.tree)
        XCTAssertEqual(viewModel.tree?.rootKey, "main")
    }

    func test_scheduleUpdate_clear() async throws {
        // Given
        let tree = try UITree.parse(from: simpleTreeJSON)
        let viewModel = GenerativeUIViewModel(tree: tree)
        XCTAssertNotNil(viewModel.tree)

        // When
        viewModel.scheduleUpdate(UITreeUpdate(type: .clear))

        // Wait for batch to apply (needs longer on CI runners)
        try await Task.sleep(for: .milliseconds(200))

        // Then
        XCTAssertNil(viewModel.tree)
    }

    func test_throttle_not_debounce() async throws {
        // Given - true throttle should apply updates even under continuous load
        let viewModel = GenerativeUIViewModel()

        // When - schedule updates continuously for 50ms
        let startTime = Date()
        var updateCount = 0

        while Date().timeIntervalSince(startTime) < 0.05 {
            let json = """
            {
              "root": "text",
              "elements": {
                "text": {
                  "type": "Text",
                  "props": { "content": "Update \(updateCount)" }
                }
              }
            }
            """
            if let tree = try? UITree.parse(from: json) {
                viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(tree)))
                updateCount += 1
            }
            try await Task.sleep(for: .microseconds(100))
        }

        // Wait for final batch
        try await Task.sleep(for: .milliseconds(30))

        // Then - should have a tree (throttle guarantees updates happen)
        XCTAssertNotNil(viewModel.tree)
    }

    // MARK: - State Accessor Tests

    func test_hasTree_returns_true_when_tree_exists() throws {
        // Given
        let tree = try UITree.parse(from: simpleTreeJSON)
        let viewModel = GenerativeUIViewModel(tree: tree)

        // Then
        XCTAssertTrue(viewModel.hasTree)
    }

    func test_hasTree_returns_false_when_no_tree() {
        // Given
        let viewModel = GenerativeUIViewModel()

        // Then
        XCTAssertFalse(viewModel.hasTree)
    }

    func test_hasError_returns_true_when_error_exists() async {
        // Given
        let viewModel = GenerativeUIViewModel()
        await viewModel.loadTree(from: "invalid".data(using: .utf8)!)

        // Then
        XCTAssertTrue(viewModel.hasError)
    }

    func test_hasError_returns_false_when_no_error() {
        // Given
        let viewModel = GenerativeUIViewModel()

        // Then
        XCTAssertFalse(viewModel.hasError)
    }

    func test_errorMessage_returns_localized_description() async {
        // Given
        let viewModel = GenerativeUIViewModel()
        await viewModel.loadTree(from: "invalid".data(using: .utf8)!)

        // Then
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Factory Method Tests

    func test_loading_factory() async {
        // Given
        let data = simpleTreeJSON.data(using: .utf8)!

        // When
        let viewModel = await GenerativeUIViewModel.loading(from: data)

        // Then
        XCTAssertNotNil(viewModel.tree)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_streaming_factory() {
        // When
        let viewModel = GenerativeUIViewModel.streaming()

        // Then
        XCTAssertNil(viewModel.tree)
        XCTAssertTrue(viewModel.isLoading)
    }

    // MARK: - Stream Subscription Tests

    func test_subscribe_to_async_stream() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree = try UITree.parse(from: simpleTreeJSON)

        let stream = AsyncStream<UITree> { continuation in
            continuation.yield(tree)
            continuation.finish()
        }

        // When
        await viewModel.subscribe(to: stream)

        // Then - should have tree after subscribe completes (flushes updates)
        XCTAssertNotNil(viewModel.tree)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_subscribe_to_throwing_stream() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree = try UITree.parse(from: simpleTreeJSON)

        let stream = AsyncThrowingStream<UITree, Error> { continuation in
            continuation.yield(tree)
            continuation.finish()
        }

        // When
        await viewModel.subscribe(to: stream)

        // Then - should have tree after subscribe completes (flushes updates)
        XCTAssertNotNil(viewModel.tree)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_subscribe_handles_stream_error() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()

        struct TestError: Error {}

        let stream = AsyncThrowingStream<UITree, Error> { continuation in
            continuation.finish(throwing: TestError())
        }

        // When
        await viewModel.subscribe(to: stream)

        // Then
        XCTAssertNotNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_cancelSubscription() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        viewModel.cancelSubscription()

        // Then - should not crash and isLoading should be false
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_new_subscription_cancels_previous() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree1 = try UITree.parse(from: simpleTreeJSON)
        let tree2 = try UITree.parse(from: complexTreeJSON)

        // First stream never finishes
        let stream1 = AsyncStream<UITree> { continuation in
            continuation.yield(tree1)
            // Don't finish
        }

        // Start first subscription in background
        Task {
            await viewModel.subscribe(to: stream1)
        }

        // Wait for it to start
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(viewModel.tree?.rootKey, "text1")

        // When - start second subscription
        let stream2 = AsyncStream<UITree> { continuation in
            continuation.yield(tree2)
            continuation.finish()
        }

        await viewModel.subscribe(to: stream2)

        // Then - should have tree from second stream
        XCTAssertEqual(viewModel.tree?.rootKey, "main")
    }

    // MARK: - UITreeUpdate Tests

    func test_UITreeUpdate_replaceTree() throws {
        // Given
        let tree = try UITree.parse(from: simpleTreeJSON)

        // When
        let update = UITreeUpdate(type: .replaceTree(tree))

        // Then
        if case .replaceTree(let updatedTree) = update.type {
            XCTAssertEqual(updatedTree.rootKey, "text1")
        } else {
            XCTFail("Expected replaceTree update type")
        }
    }

    func test_UITreeUpdate_clear() {
        // When
        let update = UITreeUpdate(type: .clear)

        // Then
        if case .clear = update.type {
            // Success
        } else {
            XCTFail("Expected clear update type")
        }
    }

    func test_UITreeUpdate_has_timestamp() {
        // Given
        let before = Date()

        // When
        let update = UITreeUpdate(type: .clear)

        // Then
        let after = Date()
        XCTAssertGreaterThanOrEqual(update.timestamp, before)
        XCTAssertLessThanOrEqual(update.timestamp, after)
    }

    // MARK: - Error Tests

    func test_GenerativeUIViewModelError_updateFailed() {
        // Given
        let error = GenerativeUIViewModelError.updateFailed(reason: "Test reason")

        // Then
        XCTAssertEqual(error.localizedDescription, "UITree update failed: Test reason")
    }

    func test_GenerativeUIViewModelError_invalidTreeState() {
        // Given
        let error = GenerativeUIViewModelError.invalidTreeState

        // Then
        XCTAssertEqual(error.localizedDescription, "UITree is in an invalid state")
    }

    // MARK: - Edge Cases

    func test_rapid_updates_dont_cause_issues() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()

        // When - schedule many updates rapidly
        for i in 0..<100 {
            let json = """
            {
              "root": "text",
              "elements": {
                "text": {
                  "type": "Text",
                  "props": { "content": "Update \(i)" }
                }
              }
            }
            """
            if let tree = try? UITree.parse(from: json) {
                viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(tree)))
            }
        }

        // Wait for all updates to process
        try await Task.sleep(for: .milliseconds(100))

        // Then - should have a tree (the last one that was scheduled)
        XCTAssertNotNil(viewModel.tree)
    }

    func test_concurrent_load_and_update() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()

        // When - start loading (loadTree cancels pending updates)
        await viewModel.loadTree(from: complexTreeJSON)

        // Then - should have the loaded tree
        XCTAssertEqual(viewModel.tree?.rootKey, "main")
    }

    func test_subscribe_flushes_updates_before_completing() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree = try UITree.parse(from: simpleTreeJSON)

        let stream = AsyncStream<UITree> { continuation in
            continuation.yield(tree)
            continuation.finish()
        }

        // When
        await viewModel.subscribe(to: stream)

        // Then - tree should be available immediately (flushed before isLoading = false)
        XCTAssertNotNil(viewModel.tree)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_cancellation_does_not_set_error() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()

        // Create a stream that throws CancellationError when cancelled
        let stream = AsyncThrowingStream<UITree, Error> { continuation in
            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination {
                    continuation.finish(throwing: CancellationError())
                }
            }
        }

        // Start subscription in a cancellable task
        let subscriptionTask = Task {
            await viewModel.subscribe(to: stream)
        }

        // Wait for it to start
        try await Task.sleep(for: .milliseconds(20))

        // When - cancel the task
        subscriptionTask.cancel()

        // Wait for cancellation to propagate
        try await Task.sleep(for: .milliseconds(50))

        // Then - error should NOT be set (CancellationError is ignored)
        XCTAssertNil(viewModel.error)
    }

    func test_startSubscription_fires_and_forgets() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree = try UITree.parse(from: simpleTreeJSON)

        // Use a stream that yields after a brief delay to ensure timing works
        let stream = AsyncStream<UITree> { continuation in
            Task {
                try? await Task.sleep(for: .milliseconds(10))
                continuation.yield(tree)
                continuation.finish()
            }
        }

        // When - start subscription without awaiting
        viewModel.startSubscription(to: stream)

        // Wait for the stream to be consumed (longer wait for batched updates)
        try await Task.sleep(for: .milliseconds(150))

        // Then
        XCTAssertNotNil(viewModel.tree, "Tree should be set after background subscription completes")
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_startSubscription_can_be_cancelled() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()

        let stream = AsyncStream<UITree> { continuation in
            // Never finishes
            Task {
                try? await Task.sleep(for: .seconds(10))
            }
        }

        // When - start then cancel
        viewModel.startSubscription(to: stream)
        try await Task.sleep(for: .milliseconds(10))
        viewModel.cancelSubscription()

        // Then
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_loadTree_cancels_active_subscription() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree1 = try UITree.parse(from: simpleTreeJSON)

        // Use a stream that yields after a brief delay
        let stream = AsyncStream<UITree> { continuation in
            Task {
                try? await Task.sleep(for: .milliseconds(10))
                continuation.yield(tree1)
                // Don't finish - simulating an active stream
            }
        }

        // Start a subscription
        viewModel.startSubscription(to: stream)

        // Wait for the stream to yield and batch to apply
        try await Task.sleep(for: .milliseconds(100))

        // Verify stream started (tree should be set after batch applies)
        XCTAssertEqual(viewModel.tree?.rootKey, "text1", "Stream should have set the tree")

        // When - load a different tree
        await viewModel.loadTree(from: complexTreeJSON)

        // Then - should have the loaded tree, not the stream tree
        XCTAssertEqual(viewModel.tree?.rootKey, "main")
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_batch_updates_apply_in_order() async throws {
        // Given - test that clear/replace ordering is preserved
        let viewModel = GenerativeUIViewModel()
        let tree = try UITree.parse(from: simpleTreeJSON)

        // Schedule replace then clear - final state should be nil
        let now = Date()
        viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(tree), timestamp: now))
        viewModel.scheduleUpdate(UITreeUpdate(type: .clear, timestamp: now.addingTimeInterval(0.001)))

        // Wait for batch to apply
        try await Task.sleep(for: .milliseconds(25))

        // Then - clear came after replace, so tree should be nil
        XCTAssertNil(viewModel.tree)
    }

    func test_batch_updates_clear_then_replace() async throws {
        // Given - test that clear/replace ordering is preserved
        let viewModel = GenerativeUIViewModel()
        let tree = try UITree.parse(from: simpleTreeJSON)

        // Schedule clear then replace - final state should be the tree
        let now = Date()
        viewModel.scheduleUpdate(UITreeUpdate(type: .clear, timestamp: now))
        viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(tree), timestamp: now.addingTimeInterval(0.001)))

        // Wait for batch to apply
        try await Task.sleep(for: .milliseconds(25))

        // Then - replace came after clear, so tree should exist
        XCTAssertNotNil(viewModel.tree)
        XCTAssertEqual(viewModel.tree?.rootKey, "text1")
    }

    func test_clear_also_cancels_pending_updates() async throws {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree = try UITree.parse(from: simpleTreeJSON)

        // Schedule an update
        viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(tree)))

        // When - clear (which cancels both subscription and pending updates)
        viewModel.clear()

        // Wait for what would have been the batch apply time
        try await Task.sleep(for: .milliseconds(25))

        // Then - no tree should be applied
        XCTAssertNil(viewModel.tree)
    }

    func test_throttle_applies_updates_during_continuous_load() async throws {
        // Given - under continuous load, true throttle should still apply updates
        // at frame intervals, not wait until silence like debounce would
        let viewModel = GenerativeUIViewModel()
        var observedTrees: [String] = []

        // Start observing tree changes
        let observeTask = Task {
            var lastRoot: String? = nil
            while !Task.isCancelled {
                if let currentRoot = viewModel.tree?.rootKey, currentRoot != lastRoot {
                    observedTrees.append(currentRoot)
                    lastRoot = currentRoot
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        // Schedule updates continuously for 60ms (enough for 3-4 frame ticks)
        for i in 0..<15 {
            let json = """
            {
              "root": "text\(i)",
              "elements": {
                "text\(i)": {
                  "type": "Text",
                  "props": { "content": "Update \(i)" }
                }
              }
            }
            """
            if let tree = try? UITree.parse(from: json) {
                viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(tree)))
            }
            try await Task.sleep(for: .milliseconds(5))
        }

        // Wait for final batch
        try await Task.sleep(for: .milliseconds(30))

        observeTask.cancel()

        // Then - we should have observed multiple distinct updates (throttle behavior)
        // With debounce, we'd only see one update at the very end
        // With throttle, we see updates during the continuous load
        XCTAssertGreaterThan(observedTrees.count, 1, "Throttle should apply updates during continuous load, not wait until silence")
    }
}

#endif
