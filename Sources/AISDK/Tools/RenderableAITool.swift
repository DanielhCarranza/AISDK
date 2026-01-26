//
//  RenderableAITool.swift
//  AISDK
//
//  Protocol for AITools that can render SwiftUI views from their metadata.
//  Enables generative UI patterns for AI-driven interfaces.
//

import SwiftUI
import Foundation

// MARK: - RenderableAITool Protocol

/// A protocol for AITools that can render SwiftUI views from their execution results.
///
/// `RenderableAITool` extends `AITool` with the ability to produce SwiftUI views
/// from tool metadata. This enables generative UI patterns where AI agents can
/// produce rich, interactive interfaces.
///
/// ## Usage
/// ```swift
/// struct WeatherTool: RenderableAITool {
///     typealias Arguments = WeatherArguments
///     typealias Metadata = WeatherMetadata
///     typealias RenderView = WeatherView
///
///     static var name: String { "get_weather" }
///     static var description: String { "Get weather for a location" }
///
///     static func execute(arguments: WeatherArguments) async throws -> AIToolResult<WeatherMetadata> {
///         let weather = try await fetchWeather(location: arguments.location)
///         return AIToolResult(
///             content: "Temperature: \(weather.temp)°",
///             metadata: WeatherMetadata(temp: weather.temp, condition: weather.condition)
///         )
///     }
///
///     @MainActor
///     static func render(metadata: WeatherMetadata) -> WeatherView {
///         WeatherView(weather: metadata)
///     }
/// }
/// ```
///
/// ## Metadata Requirements
/// The `Metadata` associated type must conform to `AIToolMetadata` and contain
/// all data needed to render the view. The metadata is passed through from
/// tool execution to the render function.
public protocol RenderableAITool: AITool {
    /// The SwiftUI View type this tool renders
    associatedtype RenderView: View

    /// Render a SwiftUI view from the tool's metadata.
    ///
    /// This method must be called on the main actor since it produces a SwiftUI View.
    ///
    /// - Parameter metadata: The metadata from tool execution
    /// - Returns: A SwiftUI view representing the tool result
    @MainActor
    static func render(metadata: Metadata) -> RenderView
}

// MARK: - Type-Erased Renderable Tool

/// Type-erased wrapper for RenderableAITool that preserves rendering capability.
///
/// Allows storing heterogeneous renderable tools while maintaining the ability
/// to render views from their metadata.
public struct AnyRenderableAITool: @unchecked Sendable {
    /// The tool's unique name
    public let name: String

    /// The tool's description
    public let description: String

    /// The tool's timeout
    public let timeout: TimeInterval

    /// The tool's JSON schema
    public let schema: ToolSchema

    /// The execute closure (type-erased)
    private let _execute: @Sendable (String) async throws -> AIToolExecutionResult

    /// The render closure (type-erased)
    private let _render: @MainActor (Data) -> AnyView

    /// Creates a type-erased wrapper for a RenderableAITool.
    ///
    /// - Parameter toolType: The RenderableAITool type to wrap
    public init<T: RenderableAITool>(_ toolType: T.Type) {
        self.name = T.name
        self.description = T.description
        self.timeout = T.timeout
        self.schema = T.generateSchema()

        self._execute = { arguments in
            try await AIToolExecutor.execute(T.self, arguments: arguments)
        }

        self._render = { @MainActor data in
            // Try to decode metadata and render
            guard let metadata = try? JSONDecoder().decode(T.Metadata.self, from: data) else {
                return AnyView(
                    Text("Failed to decode metadata")
                        .foregroundColor(.red)
                )
            }
            return AnyView(T.render(metadata: metadata))
        }
    }

    /// Execute the tool with raw JSON arguments.
    ///
    /// - Parameter arguments: JSON string containing the tool arguments
    /// - Returns: The tool execution result
    /// - Throws: AISDKErrorV2 if execution fails
    public func execute(arguments: String) async throws -> AIToolExecutionResult {
        try await _execute(arguments)
    }

    /// Render a view from metadata JSON data.
    ///
    /// - Parameter metadataData: JSON-encoded metadata
    /// - Returns: A type-erased SwiftUI view
    @MainActor
    public func render(metadataData: Data) -> AnyView {
        _render(metadataData)
    }

    /// Render a view from type-erased metadata.
    ///
    /// - Parameter metadata: The AnyAIToolMetadata from execution
    /// - Returns: A type-erased SwiftUI view, or nil if metadata can't be rendered
    @MainActor
    public func render(metadata: AnyAIToolMetadata) -> AnyView? {
        guard let data = metadata.jsonData else {
            return nil
        }
        return _render(data)
    }
}

// MARK: - RenderableToolRegistry

/// Registry for managing RenderableAITool types with rendering capabilities.
///
/// Extends AIToolRegistry functionality with the ability to render views
/// from tool execution results.
public final class RenderableToolRegistry: @unchecked Sendable {
    /// Thread-safe storage for tools
    private var tools: [String: AnyRenderableAITool] = [:]
    private let lock = NSLock()

    /// Creates an empty renderable tool registry
    public init() {}

    /// Register a renderable tool type.
    ///
    /// - Parameter toolType: The RenderableAITool type to register
    /// - Note: Overwrites any existing tool with the same name
    public func register<T: RenderableAITool>(_ toolType: T.Type) {
        let name = T.name.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!name.isEmpty, "Tool name must not be empty")
        let wrapped = AnyRenderableAITool(toolType)
        lock.lock()
        tools[name] = wrapped
        lock.unlock()
    }

    /// Look up a renderable tool by name.
    ///
    /// - Parameter name: The tool name to look up
    /// - Returns: The wrapped tool, or nil if not found
    public func tool(named name: String) -> AnyRenderableAITool? {
        lock.lock()
        defer { lock.unlock() }
        return tools[name]
    }

    /// Get all registered tool names (sorted for deterministic ordering).
    public var registeredNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return tools.keys.sorted()
    }

    /// Get all registered tools as schemas (sorted by name).
    public var schemas: [ToolSchema] {
        lock.lock()
        defer { lock.unlock() }
        return tools.keys.sorted().compactMap { tools[$0]?.schema }
    }

    /// Execute a tool by name.
    ///
    /// - Parameters:
    ///   - name: The tool name
    ///   - arguments: JSON string containing arguments
    /// - Returns: The tool execution result
    /// - Throws: AISDKErrorV2.toolNotFound if tool doesn't exist
    public func execute(
        name: String,
        arguments: String
    ) async throws -> AIToolExecutionResult {
        guard let tool = tool(named: name) else {
            throw AISDKErrorV2.toolNotFound(name)
        }
        return try await tool.execute(arguments: arguments)
    }

    /// Render a view for a tool by name using metadata.
    ///
    /// - Parameters:
    ///   - name: The tool name
    ///   - metadata: The execution metadata
    /// - Returns: A type-erased SwiftUI view, or nil if tool not found or rendering fails
    @MainActor
    public func render(name: String, metadata: AnyAIToolMetadata) -> AnyView? {
        guard let tool = tool(named: name) else {
            return nil
        }
        return tool.render(metadata: metadata)
    }
}

// MARK: - Empty Render View

/// A placeholder view for tools that don't have custom rendering.
///
/// Returns the tool result content as plain text.
public struct EmptyRenderView: View {
    public let content: String

    public init(content: String) {
        self.content = content
    }

    public var body: some View {
        Text(content)
            .font(.body)
            .foregroundColor(.primary)
    }
}

// MARK: - Default RenderableAITool Extension

/// Default implementation for AITools that want basic rendering.
///
/// Tools can opt-in to rendering by implementing `RenderableAITool` and
/// providing a custom `render(metadata:)` method.
extension AITool {
    /// Default render implementation that returns the content as text.
    ///
    /// Override this in your RenderableAITool implementation to provide
    /// custom rendering for your tool's metadata.
    @MainActor
    public static func defaultRender(content: String) -> some View {
        EmptyRenderView(content: content)
    }
}
