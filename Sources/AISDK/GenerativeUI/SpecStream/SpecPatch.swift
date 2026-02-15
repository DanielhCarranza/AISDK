//
//  SpecPatch.swift
//  AISDK
//
//  RFC 6902 JSON Patch model for progressive UI rendering.
//  Represents operations that incrementally modify a UITree.
//

import Foundation

// MARK: - SpecPatch

/// An RFC 6902 JSON Patch operation for incremental UITree updates.
///
/// Each patch describes a single operation (add, remove, replace, move, copy, test)
/// targeting a specific path in the UI specification. Patches are applied sequentially
/// to build or modify the UITree incrementally.
///
/// ## Path Format
/// Paths use JSON Pointer syntax (RFC 6901):
/// - `/elements/metric` — targets the "metric" element
/// - `/state/revenue` — targets the "revenue" key in state
/// - `/root` — targets the root key
///
/// ## Allowed Path Prefixes
/// Patches can only target these top-level paths:
/// - `/elements/*` — UI element nodes
/// - `/state/*` — State dictionary values
/// - `/root` — Root element key
///
/// ## Example
/// ```json
/// { "op": "add", "path": "/elements/metric", "value": { "type": "Metric", "props": { "value": 42 } } }
/// { "op": "replace", "path": "/state/revenue", "value": 12345 }
/// { "op": "remove", "path": "/elements/oldWidget" }
/// ```
public struct SpecPatch: Sendable, Codable, Equatable {
    /// The patch operation type
    public let op: Operation

    /// JSON Pointer path (e.g., "/elements/metric", "/state/revenue")
    public let path: String

    /// Value for add/replace/test operations
    public let value: SpecValue?

    /// Source path for move/copy operations
    public let from: String?

    /// RFC 6902 operation types
    public enum Operation: String, Sendable, Codable, Equatable {
        case add
        case remove
        case replace
        case move
        case copy
        case test
    }

    public init(
        op: Operation,
        path: String,
        value: SpecValue? = nil,
        from: String? = nil
    ) {
        self.op = op
        self.path = path
        self.value = value
        self.from = from
    }

    // MARK: - Path Validation

    /// Allowed top-level path prefixes for patches
    private static let allowedPrefixes = ["/elements/", "/elements", "/state/", "/state", "/root"]

    /// Whether this patch targets an allowed path
    public var hasValidPath: Bool {
        Self.allowedPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") || path.hasPrefix($0) })
    }

    /// Validates this patch has all required fields for its operation type
    public func validate() throws {
        // Path must be non-empty and start with /
        guard path.hasPrefix("/") else {
            throw SpecPatchError.invalidPath(path, reason: "Must start with /")
        }

        guard hasValidPath else {
            throw SpecPatchError.disallowedPath(path)
        }

        switch op {
        case .add, .replace, .test:
            guard value != nil else {
                throw SpecPatchError.missingValue(op)
            }
        case .move, .copy:
            guard let from, from.hasPrefix("/") else {
                throw SpecPatchError.missingFrom(op)
            }
        case .remove:
            break
        }
    }
}

// MARK: - SpecPatchBatch

/// A batch of patches from a single JSONL line.
///
/// Each line in a SpecStream JSONL response represents one batch of patches
/// to apply atomically. The optional `version` field specifies the catalog
/// semver for compatibility checking.
public struct SpecPatchBatch: Sendable, Codable, Equatable {
    /// The patches to apply in order
    public let patches: [SpecPatch]

    /// Optional catalog semver for compatibility checking
    public let version: String?

    public init(patches: [SpecPatch], version: String? = nil) {
        self.patches = patches
        self.version = version
    }

    /// Validates all patches in the batch
    public func validate() throws {
        for patch in patches {
            try patch.validate()
        }
    }
}

// MARK: - SpecPatchError

/// Errors from SpecPatch validation
public enum SpecPatchError: Error, Sendable, LocalizedError {
    /// Path is malformed
    case invalidPath(String, reason: String)

    /// Path targets a disallowed location
    case disallowedPath(String)

    /// Operation requires a value but none was provided
    case missingValue(SpecPatch.Operation)

    /// Move/copy operation requires a from path
    case missingFrom(SpecPatch.Operation)

    /// A test operation failed
    case testFailed(path: String, expected: SpecValue, actual: SpecValue?)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path, let reason):
            return "Invalid patch path '\(path)': \(reason)"
        case .disallowedPath(let path):
            return "Patch path '\(path)' is not allowed. Must target /elements/*, /state/*, or /root"
        case .missingValue(let op):
            return "'\(op.rawValue)' operation requires a 'value' field"
        case .missingFrom(let op):
            return "'\(op.rawValue)' operation requires a 'from' field"
        case .testFailed(let path, let expected, let actual):
            return "Test failed at '\(path)': expected \(expected), got \(String(describing: actual))"
        }
    }
}
