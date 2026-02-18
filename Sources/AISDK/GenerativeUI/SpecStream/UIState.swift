//
//  UIState.swift
//  AISDK
//
//  Separated state dictionary for generative UI specs.
//  Supports $path resolution with namespace isolation.
//

import Foundation

// MARK: - UIState

/// Separated state dictionary for generative UI specifications.
///
/// State values are referenced from element props via `$path` expressions.
/// The state is organized into two isolated namespaces:
/// - `/state/*` — LLM-generated state (set via patches)
/// - `/app/*` — Developer-injected application data (set via callback)
///
/// `$path` expressions in LLM-generated specs are restricted to the `/state/*`
/// namespace. Paths targeting `/app/*` from LLM specs are rejected.
///
/// ## Example
/// ```json
/// {
///   "state": { "metrics": { "revenue": 12345 } },
///   "elements": {
///     "metric": {
///       "type": "Metric",
///       "props": { "value": { "$path": "/state/metrics/revenue" } }
///     }
///   }
/// }
/// ```
public struct UIState: Sendable, Equatable {
    /// State values stored as nested SpecValue dictionary
    private var storage: [String: SpecValue]

    /// The namespace for LLM-generated state
    public static let stateNamespace = "state"

    /// The namespace for developer-injected app data
    public static let appNamespace = "app"

    // MARK: - Initialization

    public init() {
        self.storage = [:]
    }

    public init(values: [String: SpecValue]) {
        self.storage = values
    }

    // MARK: - State Access

    /// Get a value at the given key
    public subscript(key: String) -> SpecValue? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    /// All top-level keys
    public var keys: [String] { Array(storage.keys) }

    /// Whether the state is empty
    public var isEmpty: Bool { storage.isEmpty }

    // MARK: - $path Resolution

    /// Resolve a `$path` expression against the state.
    ///
    /// Paths use JSON Pointer syntax with namespace prefixes:
    /// - `/state/metrics/revenue` — resolves in LLM state namespace
    /// - `/app/userName` — resolves in app namespace (developer-injected)
    ///
    /// - Parameter path: JSON Pointer path (e.g., "/state/metrics/revenue")
    /// - Returns: The resolved value, or nil if not found
    public func resolve(path: String) -> SpecValue? {
        // Strip leading /
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let segments = trimmed.split(separator: "/").map(String.init)

        guard !segments.isEmpty else { return nil }

        // Walk the segments through the storage
        var current: SpecValue? = SpecValue(storage)

        for segment in segments {
            guard let dict = current?.dictionaryValue else { return nil }
            current = dict[segment]
        }

        return current
    }

    /// Resolve a `$path` expression, restricted to the `/state/*` namespace.
    ///
    /// This is the safe resolver for LLM-generated specs. It rejects paths
    /// targeting the `/app/*` namespace to prevent data exfiltration.
    ///
    /// - Parameter path: JSON Pointer path (must start with /state/)
    /// - Returns: The resolved value, or nil if not found or path is disallowed
    public func resolveSafe(path: String) -> SpecValue? {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path

        // Only allow /state/* paths from LLM-generated specs
        guard trimmed.hasPrefix(Self.stateNamespace + "/") || trimmed == Self.stateNamespace else {
            return nil
        }

        return resolve(path: path)
    }

    /// Resolve a `$cond` conditional expression.
    ///
    /// Format: `{ "$cond": "/state/flag", "then": X, "else": Y }`
    /// Resolves the path, checks if truthy, returns `then` or `else` value.
    ///
    /// - Parameter cond: Dictionary with `$cond`, `then`, and `else` keys
    /// - Returns: The resolved value based on the condition
    public func resolveConditional(_ cond: [String: SpecValue]) -> SpecValue? {
        guard let pathValue = cond["$cond"]?.stringValue else { return nil }

        let resolved = resolveSafe(path: pathValue)
        let isTruthy = isTruthyValue(resolved)

        return isTruthy ? cond["then"] : cond["else"]
    }

    /// Check if a SpecValue is "truthy" (non-nil, non-false, non-zero, non-empty)
    private func isTruthyValue(_ value: SpecValue?) -> Bool {
        guard let value, !value.isNull else { return false }

        if let bool = value.boolValue { return bool }
        if let int = value.intValue { return int != 0 }
        if let str = value.stringValue { return !str.isEmpty }

        // Arrays, dicts, and other non-nil values are truthy
        return true
    }

    // MARK: - Mutation

    /// Set a value at a JSON Pointer path.
    ///
    /// Creates intermediate dictionaries as needed.
    ///
    /// - Parameters:
    ///   - path: JSON Pointer path (e.g., "/state/metrics/revenue")
    ///   - value: The value to set
    public mutating func setValue(at path: String, to value: SpecValue) {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let segments = trimmed.split(separator: "/").map(String.init)

        guard !segments.isEmpty else { return }

        if segments.count == 1 {
            storage[segments[0]] = value
            return
        }

        // For nested paths, build through the storage
        // Get or create the top-level entry
        var topDict = storage[segments[0]]?.dictionaryValue ?? [:]
        setNestedValue(in: &topDict, segments: Array(segments.dropFirst()), value: value)
        storage[segments[0]] = SpecValue(topDict)
    }

    /// Recursively set a value in a nested dictionary
    private func setNestedValue(
        in dict: inout [String: SpecValue],
        segments: [String],
        value: SpecValue
    ) {
        guard !segments.isEmpty else { return }

        if segments.count == 1 {
            dict[segments[0]] = value
            return
        }

        var nested = dict[segments[0]]?.dictionaryValue ?? [:]
        setNestedValue(in: &nested, segments: Array(segments.dropFirst()), value: value)
        dict[segments[0]] = SpecValue(nested)
    }

    /// Remove a value at a JSON Pointer path
    public mutating func removeValue(at path: String) {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let segments = trimmed.split(separator: "/").map(String.init)

        guard !segments.isEmpty else { return }

        if segments.count == 1 {
            storage.removeValue(forKey: segments[0])
            return
        }

        // For nested paths, rebuild through the storage
        var topDict = storage[segments[0]]?.dictionaryValue ?? [:]
        removeNestedValue(in: &topDict, segments: Array(segments.dropFirst()))
        storage[segments[0]] = SpecValue(topDict)
    }

    /// Recursively remove a value from a nested dictionary
    private func removeNestedValue(
        in dict: inout [String: SpecValue],
        segments: [String]
    ) {
        guard !segments.isEmpty else { return }

        if segments.count == 1 {
            dict.removeValue(forKey: segments[0])
            return
        }

        var nested = dict[segments[0]]?.dictionaryValue ?? [:]
        removeNestedValue(in: &nested, segments: Array(segments.dropFirst()))
        dict[segments[0]] = SpecValue(nested)
    }

    // MARK: - Equatable

    public static func == (lhs: UIState, rhs: UIState) -> Bool {
        lhs.storage == rhs.storage
    }
}
