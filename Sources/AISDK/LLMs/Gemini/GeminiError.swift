//
//  GeminiError.swift
//
//
//  Created by Lou Zell on 10/24/24.
//

import Foundation

public enum GeminiError: Error, Sendable, LocalizedError {
    // Existing cases
    case reachedRetryLimit

    // File upload errors
    case uploadFailed(reason: String)
    case uploadInitiationFailed(String)
    case chunkUploadFailed(chunkIndex: Int, reason: String)

    // File processing errors
    case fileProcessingFailed(String)
    case processingTimeout

    // File state errors
    case fileNotFound(String)
    case fileExpired(String)
    case invalidFileState(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .reachedRetryLimit:
            return "Reached Gemini polling retry limit"

        // Upload errors
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .uploadInitiationFailed(let reason):
            return "Failed to initiate upload session: \(reason)"
        case .chunkUploadFailed(let index, let reason):
            return "Chunk \(index) upload failed: \(reason)"

        // Processing errors
        case .fileProcessingFailed(let reason):
            return "File processing failed: \(reason)"
        case .processingTimeout:
            return "File processing timed out while waiting for ACTIVE state"

        // State errors
        case .fileNotFound(let name):
            return "File not found: \(name)"
        case .fileExpired(let name):
            return "File has expired (48-hour retention limit): \(name)"
        case .invalidFileState(let expected, let actual):
            return "Invalid file state: expected \(expected), got \(actual)"
        }
    }
}
