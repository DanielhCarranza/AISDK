//
//  ComputerUseConfig.swift
//  AISDK
//
//  Configuration for computer use built-in tool
//

import Foundation

public extension BuiltInTool {
    /// Configuration for the computer use built-in tool.
    ///
    /// Both Anthropic and OpenAI require display dimensions. Provider-specific
    /// fields are optional and ignored by providers that don't support them.
    struct ComputerUseConfig: Sendable, Equatable, Hashable, Codable {
        /// Display width in pixels (required by both providers)
        public let displayWidth: Int

        /// Display height in pixels (required by both providers)
        public let displayHeight: Int

        /// Environment type (OpenAI-specific: "browser", "mac", "windows", "ubuntu", "linux")
        public let environment: ComputerUseEnvironment?

        /// X11 display number (Anthropic-specific)
        public let displayNumber: Int?

        /// Enable zoom action (Anthropic computer_20251124 only)
        public let enableZoom: Bool?

        public init(
            displayWidth: Int = 1024,
            displayHeight: Int = 768,
            environment: ComputerUseEnvironment? = nil,
            displayNumber: Int? = nil,
            enableZoom: Bool? = nil
        ) {
            self.displayWidth = displayWidth
            self.displayHeight = displayHeight
            self.environment = environment
            self.displayNumber = displayNumber
            self.enableZoom = enableZoom
        }
    }

    /// Environment type for computer use (OpenAI-specific).
    enum ComputerUseEnvironment: String, Sendable, Equatable, Hashable, Codable {
        case browser
        case mac
        case windows
        case ubuntu
        case linux
    }
}
