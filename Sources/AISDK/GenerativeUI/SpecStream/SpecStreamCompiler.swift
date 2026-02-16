//
//  SpecStreamCompiler.swift
//  AISDK
//
//  Buffers JSONL chunks, splits by newline, applies RFC 6902 patches to UITree.
//  Fault-tolerant: malformed lines are logged and skipped.
//

import Foundation
import os.log

// MARK: - SpecStreamCompiler

/// Compiles a stream of JSONL patch chunks into incremental UITree snapshots.
///
/// The compiler buffers incoming text chunks, splits by newline to extract
/// complete JSONL lines, decodes each line as a `SpecPatchBatch`, and applies
/// the patches to build/modify a UITree incrementally.
///
/// ## Fault Tolerance
/// - Malformed JSONL lines are logged and skipped (no halt)
/// - Patches referencing nonexistent elements are skipped
/// - Invalid paths are rejected silently
///
/// ## Thread Safety
/// The compiler maintains mutable internal state (buffer, working elements, state).
/// It is NOT thread-safe — callers must synchronize access externally.
/// In practice, the GenerativeUIViewModel (MainActor) serializes calls.
///
/// ## Usage
/// ```swift
/// let compiler = SpecStreamCompiler()
///
/// for try await event in stream {
///     if case .uiPatch(let batch) = event {
///         if let tree = try? compiler.apply(batch) {
///             viewModel.scheduleUpdate(.replaceTree(tree))
///         }
///     }
/// }
/// ```
public final class SpecStreamCompiler {
    /// Current working copy of elements (mutable)
    private var workingElements: [String: UINode] = [:]

    /// Current root key
    private var workingRoot: String?

    /// Current state
    private var workingState: UIState = UIState()

    /// Buffer for incomplete JSONL lines
    private var lineBuffer: String = ""

    /// JSON decoder for patch batches
    private let decoder = JSONDecoder()

    /// Logger for diagnostics
    private let logger = Logger(subsystem: "com.aisdk", category: "SpecStreamCompiler")

    /// Number of patches applied successfully
    public private(set) var appliedPatchCount: Int = 0

    /// Number of patches skipped due to errors
    public private(set) var skippedPatchCount: Int = 0

    // MARK: - Initialization

    public init() {}

    /// Initialize with an existing tree as the starting state
    public init(tree: UITree) {
        self.workingElements = tree.nodes
        self.workingRoot = tree.rootKey
    }

    /// Initialize with an existing spec as the starting state
    public init(spec: UISpec) {
        self.workingElements = spec.elements
        self.workingRoot = spec.root
        self.workingState = spec.state
    }

    // MARK: - Batch Application

    /// Apply a batch of patches and return the resulting UITree.
    ///
    /// Each patch in the batch is applied sequentially. Invalid patches are
    /// skipped (logged) without halting. Returns a new immutable UITree
    /// snapshot reflecting all successfully applied patches.
    ///
    /// - Parameter batch: The patch batch to apply
    /// - Returns: A new UITree snapshot, or nil if no root is set yet
    public func apply(_ batch: SpecPatchBatch) -> UITree? {
        for patch in batch.patches {
            applyPatch(patch)
        }

        guard let root = workingRoot, workingElements[root] != nil else {
            return nil
        }

        return UITree(rootKey: root, nodes: workingElements)
    }

    /// Apply a batch of patches and return the resulting UISpec (includes state).
    public func applyReturningSpec(_ batch: SpecPatchBatch) -> UISpec? {
        for patch in batch.patches {
            applyPatch(patch)
        }

        guard let root = workingRoot, workingElements[root] != nil else {
            return nil
        }

        return UISpec(
            root: root,
            elements: workingElements,
            state: workingState,
            catalogVersion: batch.version
        )
    }

    /// Apply a single patch operation
    private func applyPatch(_ patch: SpecPatch) {
        do {
            try patch.validate()
        } catch {
            logger.warning("Skipping invalid patch: \(error.localizedDescription)")
            skippedPatchCount += 1
            return
        }

        let path = patch.path

        // Route to the right handler based on path prefix
        if path == "/root" {
            applyRootPatch(patch)
        } else if path.hasPrefix("/elements") {
            applyElementPatch(patch)
        } else if path.hasPrefix("/state") {
            applyStatePatch(patch)
        } else {
            logger.warning("Skipping patch with unknown path prefix: \(path)")
            skippedPatchCount += 1
        }
    }

    // MARK: - Root Patches

    private func applyRootPatch(_ patch: SpecPatch) {
        switch patch.op {
        case .add, .replace:
            if let rootKey = patch.value?.stringValue {
                workingRoot = rootKey
                appliedPatchCount += 1
            } else {
                logger.warning("Root patch value must be a string")
                skippedPatchCount += 1
            }
        case .remove:
            workingRoot = nil
            appliedPatchCount += 1
        default:
            logger.warning("Unsupported operation '\(patch.op.rawValue)' on /root")
            skippedPatchCount += 1
        }
    }

    // MARK: - Element Patches

    private func applyElementPatch(_ patch: SpecPatch) {
        // Parse element key from path: /elements/key or /elements/key/prop
        let segments = pathSegments(patch.path)

        // Must have at least ["elements", "key"]
        guard segments.count >= 2 else {
            // /elements alone — could be add for entire elements dict
            if patch.op == .add || patch.op == .replace, let dict = patch.value?.dictionaryValue {
                // Bulk replace: value is a dict of element definitions
                for (key, elementValue) in dict {
                    if let node = parseUINode(key: key, from: elementValue) {
                        workingElements[key] = node
                        appliedPatchCount += 1
                    }
                }
            } else if patch.op == .remove {
                workingElements.removeAll()
                appliedPatchCount += 1
            }
            return
        }

        let elementKey = segments[1]

        switch patch.op {
        case .add:
            if let value = patch.value, let node = parseUINode(key: elementKey, from: value) {
                workingElements[elementKey] = node
                appliedPatchCount += 1
            } else {
                skippedPatchCount += 1
            }

        case .replace:
            if let value = patch.value, let node = parseUINode(key: elementKey, from: value) {
                workingElements[elementKey] = node
                appliedPatchCount += 1
            } else {
                skippedPatchCount += 1
            }

        case .remove:
            if workingElements.removeValue(forKey: elementKey) != nil {
                appliedPatchCount += 1
            } else {
                logger.info("Remove: element '\(elementKey)' not found, skipping")
                skippedPatchCount += 1
            }

        case .move:
            if let from = patch.from {
                let fromSegments = pathSegments(from)
                if fromSegments.count >= 2 {
                    let fromKey = fromSegments[1]
                    if let node = workingElements.removeValue(forKey: fromKey) {
                        let movedNode = UINode(
                            key: elementKey,
                            type: node.type,
                            propsData: node.propsData,
                            childKeys: node.childKeys,
                            hadChildrenField: node.hadChildrenField
                        )
                        workingElements[elementKey] = movedNode
                        appliedPatchCount += 1
                    } else {
                        skippedPatchCount += 1
                    }
                }
            }

        case .copy:
            if let from = patch.from {
                let fromSegments = pathSegments(from)
                if fromSegments.count >= 2 {
                    let fromKey = fromSegments[1]
                    if let node = workingElements[fromKey] {
                        let copiedNode = UINode(
                            key: elementKey,
                            type: node.type,
                            propsData: node.propsData,
                            childKeys: node.childKeys,
                            hadChildrenField: node.hadChildrenField
                        )
                        workingElements[elementKey] = copiedNode
                        appliedPatchCount += 1
                    } else {
                        skippedPatchCount += 1
                    }
                }
            }

        case .test:
            // Test operations don't modify state, just verify
            if workingElements[elementKey] != nil {
                appliedPatchCount += 1
            } else {
                logger.warning("Test failed: element '\(elementKey)' not found")
                skippedPatchCount += 1
            }
        }
    }

    /// Parse a UINode from a SpecValue
    private func parseUINode(key: String, from value: SpecValue) -> UINode? {
        guard let dict = value.dictionaryValue else { return nil }
        guard let type = dict["type"]?.stringValue else { return nil }

        // Extract props
        let propsData: Data
        if let propsValue = dict["props"] {
            do {
                propsData = try JSONEncoder().encode(propsValue)
            } catch {
                propsData = Data("{}".utf8)
            }
        } else {
            propsData = Data("{}".utf8)
        }

        // Extract children
        let childKeys: [String]
        let hadChildrenField: Bool
        if let children = dict["children"]?.arrayValue {
            hadChildrenField = true
            childKeys = children.compactMap { $0.stringValue }
        } else {
            hadChildrenField = false
            childKeys = []
        }

        return UINode(
            key: key,
            type: type,
            propsData: propsData,
            childKeys: childKeys,
            hadChildrenField: hadChildrenField
        )
    }

    // MARK: - State Patches

    private func applyStatePatch(_ patch: SpecPatch) {
        // Convert /state/... path to state-internal path
        let segments = pathSegments(patch.path)

        // /state alone
        if segments.count <= 1 {
            if patch.op == .add || patch.op == .replace, let dict = patch.value?.dictionaryValue {
                workingState = UIState(values: dict)
                appliedPatchCount += 1
            } else if patch.op == .remove {
                workingState = UIState()
                appliedPatchCount += 1
            }
            return
        }

        // Build internal path (strip "state" prefix for setValue)
        let internalPath = "/" + segments.dropFirst().joined(separator: "/")

        switch patch.op {
        case .add, .replace:
            if let value = patch.value {
                workingState.setValue(at: internalPath, to: value)
                appliedPatchCount += 1
            } else {
                skippedPatchCount += 1
            }

        case .remove:
            workingState.removeValue(at: internalPath)
            appliedPatchCount += 1

        default:
            logger.warning("Unsupported state operation: \(patch.op.rawValue)")
            skippedPatchCount += 1
        }
    }

    // MARK: - JSONL Processing

    /// Process a raw JSONL text chunk (may contain partial lines).
    ///
    /// Buffers incomplete lines across calls. Complete lines are decoded
    /// as `SpecPatchBatch` objects. Malformed lines are logged and skipped.
    ///
    /// - Parameter chunk: Raw text chunk from the stream
    /// - Returns: Array of successfully decoded patch batches
    public func processChunk(_ chunk: String) -> [SpecPatchBatch] {
        lineBuffer += chunk

        var batches: [SpecPatchBatch] = []

        // Split by newline, keeping the last segment as buffer if incomplete
        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineIndex])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let data = trimmed.data(using: .utf8),
               let batch = try? decoder.decode(SpecPatchBatch.self, from: data) {
                batches.append(batch)
            } else {
                logger.warning("Skipping malformed JSONL line")
                skippedPatchCount += 1
            }
        }

        return batches
    }

    // MARK: - State Access

    /// The current working state
    public var currentState: UIState { workingState }

    /// The current working root key
    public var currentRoot: String? { workingRoot }

    /// The current number of elements
    public var elementCount: Int { workingElements.count }

    /// Build a UITree snapshot from the current state (returns nil if no root)
    public var currentTree: UITree? {
        guard let root = workingRoot, workingElements[root] != nil else { return nil }
        return UITree(rootKey: root, nodes: workingElements)
    }

    /// Build a UISpec snapshot from the current state (returns nil if no root)
    public var currentSpec: UISpec? {
        guard let root = workingRoot, workingElements[root] != nil else { return nil }
        return UISpec(root: root, elements: workingElements, state: workingState)
    }

    // MARK: - Reset

    /// Reset the compiler to initial state
    public func reset() {
        workingElements.removeAll()
        workingRoot = nil
        workingState = UIState()
        lineBuffer = ""
        appliedPatchCount = 0
        skippedPatchCount = 0
    }

    // MARK: - Helpers

    /// Split a JSON Pointer path into segments
    private func pathSegments(_ path: String) -> [String] {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return trimmed.split(separator: "/").map(String.init)
    }
}
