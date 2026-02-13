//
//  SessionStoreError.swift
//  AISDK
//
//  Errors that can occur during session storage operations.
//

import Foundation

/// Errors that can occur during session operations
public enum SessionStoreError: Error, Sendable, LocalizedError {
    /// Session not found
    case notFound(sessionId: String)

    /// Session already exists (create conflict)
    case alreadyExists(sessionId: String)

    /// Storage backend unavailable
    case unavailable(reason: String)

    /// Invalid session data (decode error)
    case invalidData(reason: String)

    /// Operation not supported by this store
    case unsupported(operation: String)

    /// Permission denied
    case permissionDenied(reason: String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Session not found: \(id)"
        case .alreadyExists(let id):
            return "Session already exists: \(id)"
        case .unavailable(let reason):
            return "Storage unavailable: \(reason)"
        case .invalidData(let reason):
            return "Invalid session data: \(reason)"
        case .unsupported(let operation):
            return "Unsupported operation: \(operation)"
        case .permissionDenied(let reason):
            return "Permission denied: \(reason)"
        }
    }
}
