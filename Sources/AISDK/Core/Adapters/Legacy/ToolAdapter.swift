//
//  ToolAdapter.swift
//  AISDK
//
//  Adapter that wraps the legacy Tool protocol to work with the new AIAgent system
//  Provides backward compatibility for existing @Parameter-based tools
//

import Foundation

// MARK: - ToolAdapter

/// Adapter that wraps an existing Tool implementation to work with the new AI agent system.
/// This enables gradual migration from the legacy `@Parameter`-based tools to the new unified interface.
///
/// Usage:
/// ```swift
/// // Wrap a legacy tool type
/// let adapter = ToolAdapter(toolType: WeatherTool.self)
///
/// // Execute the tool with arguments
/// let result = try await adapter.execute(arguments: ["location": "San Francisco"])
///
/// // Get the schema for use with LLM requests
/// let schema = adapter.schema
/// ```
public final class ToolAdapter: @unchecked Sendable {
    // MARK: - Properties

    /// The type of the wrapped legacy Tool
    private let toolType: Tool.Type

    /// The JSON schema for this tool
    public let schema: ToolSchema

    /// The tool's name
    public var name: String { schema.function?.name ?? "" }

    /// The tool's description
    public var toolDescription: String { schema.function?.description ?? "" }

    /// Whether this tool returns a response that should be shown to the user
    public var returnToolResponse: Bool {
        toolType.init().returnToolResponse
    }

    // MARK: - Initialization

    /// Creates an adapter wrapping a legacy Tool type
    /// - Parameter toolType: The Tool.Type to wrap
    public init(toolType: Tool.Type) {
        self.toolType = toolType
        self.schema = toolType.jsonSchema()
    }

    // MARK: - Execution

    /// Execute the tool with the given arguments
    /// - Parameter arguments: Dictionary of argument names to values
    /// - Returns: The tool execution result
    /// - Throws: ToolError if execution fails
    public func execute(arguments: [String: Any]) async throws -> AdaptedToolResult {
        var tool = toolType.init()
        try tool.setParameters(from: arguments)

        let (content, metadata) = try await tool.execute()

        return AdaptedToolResult(
            content: content,
            metadata: metadata,
            toolName: name
        )
    }

    /// Execute the tool with JSON data arguments
    /// - Parameter argumentsData: JSON data containing the arguments
    /// - Returns: The tool execution result
    /// - Throws: ToolError if execution fails
    public func execute(argumentsData: Data) async throws -> AdaptedToolResult {
        var tool = toolType.init()
        let validatedTool = try tool.validateAndSetParameters(argumentsData)

        let (content, metadata) = try await validatedTool.execute()

        return AdaptedToolResult(
            content: content,
            metadata: metadata,
            toolName: name
        )
    }

    /// Execute the tool with a JSON string
    /// - Parameter argumentsJSON: JSON string containing the arguments
    /// - Returns: The tool execution result
    /// - Throws: ToolError if execution fails
    public func execute(argumentsJSON: String) async throws -> AdaptedToolResult {
        guard let data = argumentsJSON.data(using: .utf8) else {
            throw ToolError.invalidParameters("Invalid JSON string encoding")
        }
        return try await execute(argumentsData: data)
    }
}

// MARK: - AdaptedToolResult

/// Result of a tool execution via the adapter
public struct AdaptedToolResult: Sendable {
    /// The text content result
    public let content: String

    /// Optional metadata from the tool execution
    public let metadata: ToolMetadata?

    /// The name of the tool that was executed
    public let toolName: String

    public init(content: String, metadata: ToolMetadata?, toolName: String) {
        self.content = content
        self.metadata = metadata
        self.toolName = toolName
    }

    /// Convert to AIToolResultData for use with the agent system
    /// - Parameter toolCallId: The ID of the tool call this result is for
    /// - Returns: An AIToolResultData instance
    public func toAIToolResultData(toolCallId: String) -> AIToolResultData {
        AIToolResultData(
            id: toolCallId,
            result: content,
            metadata: metadata
        )
    }
}

// MARK: - ToolAdapterRegistry

/// Registry for managing tool adapters
public final class ToolAdapterRegistry: @unchecked Sendable {
    // MARK: - Properties

    /// Shared singleton instance
    public static let shared = ToolAdapterRegistry()

    /// Map of tool name to adapter
    private var adapters: [String: ToolAdapter] = [:]

    /// Lock for thread-safe access
    private let lock = NSLock()

    // MARK: - Initialization

    private init() {}

    // MARK: - Registration

    /// Register a tool type with the registry
    /// - Parameter toolType: The Tool.Type to register
    public func register(toolType: Tool.Type) {
        let adapter = ToolAdapter(toolType: toolType)
        lock.lock()
        defer { lock.unlock() }
        adapters[adapter.name] = adapter
    }

    /// Register multiple tool types at once
    /// - Parameter toolTypes: Array of Tool.Type to register
    public func registerAll(toolTypes: [Tool.Type]) {
        for toolType in toolTypes {
            register(toolType: toolType)
        }
    }

    /// Get an adapter by tool name
    /// - Parameter name: The name of the tool
    /// - Returns: The ToolAdapter if registered, nil otherwise
    public func adapter(forName name: String) -> ToolAdapter? {
        lock.lock()
        defer { lock.unlock() }
        return adapters[name]
    }

    /// Get all registered adapters
    /// - Returns: Array of all registered adapters
    public func allAdapters() -> [ToolAdapter] {
        lock.lock()
        defer { lock.unlock() }
        return Array(adapters.values)
    }

    /// Get all registered tool schemas
    /// - Returns: Array of ToolSchema for all registered tools
    public func allSchemas() -> [ToolSchema] {
        lock.lock()
        defer { lock.unlock() }
        return adapters.values.map { $0.schema }
    }

    /// Remove a tool adapter by name
    /// - Parameter name: The name of the tool to remove
    public func unregister(name: String) {
        lock.lock()
        defer { lock.unlock() }
        adapters.removeValue(forKey: name)
    }

    /// Remove all registered adapters
    public func unregisterAll() {
        lock.lock()
        defer { lock.unlock() }
        adapters.removeAll()
    }
}

// MARK: - Convenience Extensions

public extension ToolAdapter {
    /// Create adapters from an array of tool types
    /// - Parameter toolTypes: Array of Tool.Type to wrap
    /// - Returns: Array of ToolAdapter instances
    static func from(_ toolTypes: [Tool.Type]) -> [ToolAdapter] {
        toolTypes.map { ToolAdapter(toolType: $0) }
    }

    /// Create a tool schema array from tool types
    /// - Parameter toolTypes: Array of Tool.Type
    /// - Returns: Array of ToolSchema for use with LLM requests
    static func schemas(from toolTypes: [Tool.Type]) -> [ToolSchema] {
        toolTypes.map { $0.jsonSchema() }
    }
}

// MARK: - ToolExecutor

/// Executes tools by name using the adapter registry
public final class ToolExecutor: @unchecked Sendable {
    // MARK: - Properties

    /// The registry to use for tool lookup
    private let registry: ToolAdapterRegistry

    // MARK: - Initialization

    /// Creates a tool executor with the shared registry
    public init() {
        self.registry = ToolAdapterRegistry.shared
    }

    /// Creates a tool executor with a custom registry
    /// - Parameter registry: The registry to use for tool lookup
    public init(registry: ToolAdapterRegistry) {
        self.registry = registry
    }

    // MARK: - Execution

    /// Execute a tool by name with arguments
    /// - Parameters:
    ///   - name: The name of the tool to execute
    ///   - arguments: Dictionary of argument names to values
    /// - Returns: The tool execution result
    /// - Throws: ToolError if the tool is not found or execution fails
    public func execute(toolName name: String, arguments: [String: Any]) async throws -> AdaptedToolResult {
        guard let adapter = registry.adapter(forName: name) else {
            throw ToolError.toolNotFound(name)
        }
        return try await adapter.execute(arguments: arguments)
    }

    /// Execute a tool by name with JSON data
    /// - Parameters:
    ///   - name: The name of the tool to execute
    ///   - argumentsData: JSON data containing the arguments
    /// - Returns: The tool execution result
    /// - Throws: ToolError if the tool is not found or execution fails
    public func execute(toolName name: String, argumentsData: Data) async throws -> AdaptedToolResult {
        guard let adapter = registry.adapter(forName: name) else {
            throw ToolError.toolNotFound(name)
        }
        return try await adapter.execute(argumentsData: argumentsData)
    }

    /// Execute a tool by name with a JSON string
    /// - Parameters:
    ///   - name: The name of the tool to execute
    ///   - argumentsJSON: JSON string containing the arguments
    /// - Returns: The tool execution result
    /// - Throws: ToolError if the tool is not found or execution fails
    public func execute(toolName name: String, argumentsJSON: String) async throws -> AdaptedToolResult {
        guard let adapter = registry.adapter(forName: name) else {
            throw ToolError.toolNotFound(name)
        }
        return try await adapter.execute(argumentsJSON: argumentsJSON)
    }

    /// Execute a tool call result (from LLM response)
    /// - Parameter toolCall: The tool call result from the LLM
    /// - Returns: The tool execution result
    /// - Throws: ToolError if the tool is not found or execution fails
    public func execute(toolCall: AIToolCallResult) async throws -> AdaptedToolResult {
        return try await execute(toolName: toolCall.name, argumentsJSON: toolCall.arguments)
    }
}

// MARK: - ToolError Extension

public extension ToolError {
    /// Error when a tool is not found in the registry
    static func toolNotFound(_ name: String) -> ToolError {
        .invalidParameters("Tool not found: \(name)")
    }
}
