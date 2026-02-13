//
//  ComputerUseResult.swift
//  AISDK
//
//  Result type returned by consumer after executing a computer use action
//

import Foundation

/// Result returned by the consumer after executing a computer use action.
public struct ComputerUseResult: Sendable, Equatable {
    /// Base64-encoded screenshot image data (typically PNG)
    public let screenshot: String?

    /// Media type of the screenshot
    public let mediaType: ImageMediaType?

    /// Optional text output (e.g., cursor position coordinates)
    public let text: String?

    /// Whether this result represents an error
    public let isError: Bool

    public enum ImageMediaType: String, Sendable, Equatable, Codable {
        case png = "image/png"
        case jpeg = "image/jpeg"
        case gif = "image/gif"
        case webp = "image/webp"
    }

    public init(
        screenshot: String? = nil,
        mediaType: ImageMediaType? = .png,
        text: String? = nil,
        isError: Bool = false
    ) {
        self.screenshot = screenshot
        self.mediaType = mediaType
        self.text = text
        self.isError = isError
    }

    /// Convenience for a screenshot-only result
    public static func screenshot(_ base64: String, mediaType: ImageMediaType = .png) -> ComputerUseResult {
        ComputerUseResult(screenshot: base64, mediaType: mediaType)
    }

    /// Convenience for an error result
    public static func error(_ message: String) -> ComputerUseResult {
        ComputerUseResult(text: message, isError: true)
    }
}

/// Internal payload for encoding computer use results through the text-only AIMessage.tool pipeline.
///
/// The Agent encodes this as JSON in the tool message content, and provider adapters detect
/// the `__computer_use_result__` type marker to reconstruct the proper wire format.
struct ComputerUseResultPayload: Codable {
    let type: String // "__computer_use_result__"
    let screenshot: String?
    let mediaType: String?
    let text: String?
    let isError: Bool
    let callId: String?
}
