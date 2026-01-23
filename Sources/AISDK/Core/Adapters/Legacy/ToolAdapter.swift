//
//  ToolAdapter.swift
//  AISDK
//
//  Adapter that wraps the legacy Tool protocol to work with the new AIAgent system
//  Provides backward compatibility for existing @Parameter-based tools
//
//  Note: This adapter registry is designed for the new AIAgent system and complements
//  the existing ToolRegistry in Sources/AISDK/Tools/ToolRegistry.swift. While ToolRegistry
//  is used by the legacy Agent class for tool type lookup, ToolAdapterRegistry provides
//  additional functionality for schema management and result type conversion needed by
//  the new protocol-based AI system.
//

import Foundation

// MARK: - ToolAdapterError

/// Errors that can occur during tool adapter operations
public enum ToolAdapterError: Error, Sendable {
    /// Tool has an empty or invalid name
    case invalidToolName(String)

    /// Tool is already registered with this name
    case duplicateRegistration(String)

    /// Tool was not found in the registry
    case toolNotFound(String)

    /// Tool execution failed
    case executionFailed(String, Error)

    public var localizedDescription: String {
        switch self {
        case .invalidToolName(let reason):
            return "Invalid tool name: \(reason)"
        case .duplicateRegistration(let name):
            return "Tool already registered: \(name)"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .executionFailed(let name, let error):
            return "Tool execution failed (\(name)): \(error.localizedDescription)"
        }
    }
}

// MARK: - ToolAdapter

/// Adapter that wraps an existing Tool implementation to work with the new AI agent system.
/// This enables gradual migration from the legacy `@Parameter`-based tools to the new unified interface.
///
/// Usage:
/// ```swift
/// // Wrap a legacy tool type
/// let adapter = try ToolAdapter(toolType: WeatherTool.self)
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

    /// The tool's name (validated non-empty at initialization)
    public let name: String

    /// The tool's description
    public let toolDescription: String

    /// Whether this tool returns a response that should be shown to the user (cached)
    public let returnToolResponse: Bool

    // MARK: - Initialization

    /// Creates an adapter wrapping a legacy Tool type
    /// - Parameter toolType: The Tool.Type to wrap
    /// - Throws: ToolAdapterError.invalidToolName if the tool has an empty name
    public init(toolType: Tool.Type) throws {
        self.toolType = toolType
        self.schema = toolType.jsonSchema()

        // Validate tool has a proper name
        guard let function = schema.function, !function.name.isEmpty else {
            throw ToolAdapterError.invalidToolName("Tool schema must have a non-empty function name")
        }

        self.name = function.name
        self.toolDescription = function.description ?? ""

        // Cache returnToolResponse to avoid repeated instantiation
        self.returnToolResponse = toolType.init().returnToolResponse
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
        // Handle empty data as empty object
        let effectiveData: Data
        if argumentsData.isEmpty {
            effectiveData = "{}".data(using: .utf8)!
        } else {
            effectiveData = argumentsData
        }

        var tool = toolType.init()
        let validatedTool = try tool.validateAndSetParameters(effectiveData)

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
        // Treat empty/whitespace-only strings as empty object
        let trimmed = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveJSON = trimmed.isEmpty ? "{}" : trimmed

        guard let data = effectiveJSON.data(using: .utf8) else {
            throw ToolError.invalidParameters("Invalid JSON string encoding")
        }
        return try await execute(argumentsData: data)
    }

    /// Execute the tool and return result with tool call ID
    /// - Parameters:
    ///   - toolCallId: The ID of the tool call (for correlation)
    ///   - arguments: Dictionary of argument names to values
    /// - Returns: AIToolResultData for use with the agent system
    public func executeWithId(toolCallId: String, arguments: [String: Any]) async throws -> AIToolResultData {
        let result = try await execute(arguments: arguments)
        return result.toAIToolResultData(toolCallId: toolCallId)
    }

    /// Execute the tool and return result with tool call ID
    /// - Parameters:
    ///   - toolCallId: The ID of the tool call (for correlation)
    ///   - argumentsJSON: JSON string containing the arguments
    /// - Returns: AIToolResultData for use with the agent system
    public func executeWithId(toolCallId: String, argumentsJSON: String) async throws -> AIToolResultData {
        let result = try await execute(argumentsJSON: argumentsJSON)
        return result.toAIToolResultData(toolCallId: toolCallId)
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

/// Registry for managing tool adapters.
///
/// This registry is designed for the new AIAgent system and provides schema management
/// and result type conversion. It complements the existing ToolRegistry which is used
/// by the legacy Agent class.
public final class ToolAdapterRegistry: @unchecked Sendable {
    // MARK: - Properties

    /// Shared singleton instance
    public static let shared = ToolAdapterRegistry()

    /// Map of tool name to adapter
    private var adapters: [String: ToolAdapter] = [:]

    /// Lock for thread-safe access
    private let lock = NSLock()

    // MARK: - Initialization

    /// Creates a new empty registry (for testing or isolated use)
    public init() {}

    // MARK: - Registration

    /// Register a tool type with the registry
    /// - Parameters:
    ///   - toolType: The Tool.Type to register
    ///   - allowOverwrite: If false (default), throws on duplicate registration
    /// - Throws: ToolAdapterError if the tool has an invalid name or is already registered
    public func register(toolType: Tool.Type, allowOverwrite: Bool = false) throws {
        let adapter = try ToolAdapter(toolType: toolType)

        lock.lock()
        defer { lock.unlock() }

        if !allowOverwrite && adapters[adapter.name] != nil {
            throw ToolAdapterError.duplicateRegistration(adapter.name)
        }

        adapters[adapter.name] = adapter
    }

    /// Register multiple tool types at once
    /// - Parameters:
    ///   - toolTypes: Array of Tool.Type to register
    ///   - allowOverwrite: If false (default), throws on duplicate registration
    /// - Throws: ToolAdapterError if any tool has an invalid name or is already registered
    public func registerAll(toolTypes: [Tool.Type], allowOverwrite: Bool = false) throws {
        for toolType in toolTypes {
            try register(toolType: toolType, allowOverwrite: allowOverwrite)
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

    /// Get all registered adapters (sorted by name for deterministic order)
    /// - Returns: Array of all registered adapters sorted by name
    public func allAdapters() -> [ToolAdapter] {
        lock.lock()
        defer { lock.unlock() }
        return adapters.values.sorted { $0.name < $1.name }
    }

    /// Get all registered tool schemas (sorted by name for deterministic order)
    /// - Returns: Array of ToolSchema for all registered tools sorted by name
    public func allSchemas() -> [ToolSchema] {
        lock.lock()
        defer { lock.unlock() }
        return adapters.values.sorted { $0.name < $1.name }.map { $0.schema }
    }

    /// Remove a tool adapter by name
    /// - Parameter name: The name of the tool to remove
    /// - Returns: True if a tool was removed, false if not found
    @discardableResult
    public func unregister(name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return adapters.removeValue(forKey: name) != nil
    }

    /// Remove all registered adapters
    public func unregisterAll() {
        lock.lock()
        defer { lock.unlock() }
        adapters.removeAll()
    }

    /// Check if a tool is registered
    /// - Parameter name: The name of the tool
    /// - Returns: True if the tool is registered
    public func isRegistered(name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return adapters[name] != nil
    }

    /// Get the count of registered tools
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return adapters.count
    }
}

// MARK: - Convenience Extensions

public extension ToolAdapter {
    /// Create adapters from an array of tool types
    /// - Parameter toolTypes: Array of Tool.Type to wrap
    /// - Returns: Array of ToolAdapter instances
    /// - Throws: ToolAdapterError if any tool has an invalid name
    static func from(_ toolTypes: [Tool.Type]) throws -> [ToolAdapter] {
        try toolTypes.map { try ToolAdapter(toolType: $0) }
    }

    /// Create a tool schema array from tool types
    /// - Parameter toolTypes: Array of Tool.Type
    /// - Returns: Array of ToolSchema for use with LLM requests
    static func schemas(from toolTypes: [Tool.Type]) -> [ToolSchema] {
        toolTypes.map { $0.jsonSchema() }
    }
}

// MARK: - ToolExecutor

/// Executes tools by name using the adapter registry.
///
/// Provides a convenient way to execute tools from LLM responses with proper
/// error handling and result correlation.
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
    /// - Throws: ToolAdapterError if the tool is not found or execution fails
    public func execute(toolName name: String, arguments: [String: Any]) async throws -> AdaptedToolResult {
        guard let adapter = registry.adapter(forName: name) else {
            throw ToolAdapterError.toolNotFound(name)
        }
        return try await adapter.execute(arguments: arguments)
    }

    /// Execute a tool by name with JSON data
    /// - Parameters:
    ///   - name: The name of the tool to execute
    ///   - argumentsData: JSON data containing the arguments
    /// - Returns: The tool execution result
    /// - Throws: ToolAdapterError if the tool is not found or execution fails
    public func execute(toolName name: String, argumentsData: Data) async throws -> AdaptedToolResult {
        guard let adapter = registry.adapter(forName: name) else {
            throw ToolAdapterError.toolNotFound(name)
        }
        return try await adapter.execute(argumentsData: argumentsData)
    }

    /// Execute a tool by name with a JSON string
    /// - Parameters:
    ///   - name: The name of the tool to execute
    ///   - argumentsJSON: JSON string containing the arguments
    /// - Returns: The tool execution result
    /// - Throws: ToolAdapterError if the tool is not found or execution fails
    public func execute(toolName name: String, argumentsJSON: String) async throws -> AdaptedToolResult {
        guard let adapter = registry.adapter(forName: name) else {
            throw ToolAdapterError.toolNotFound(name)
        }
        return try await adapter.execute(argumentsJSON: argumentsJSON)
    }

    /// Execute a tool call from an LLM response
    /// - Parameter toolCall: The tool call result from the LLM
    /// - Returns: The tool execution result (use with toolCall.id for correlation)
    /// - Throws: ToolAdapterError if the tool is not found or execution fails
    public func execute(toolCall: AIToolCallResult) async throws -> AdaptedToolResult {
        return try await execute(toolName: toolCall.name, argumentsJSON: toolCall.arguments)
    }

    /// Execute a tool call and return AIToolResultData with correlation ID
    /// - Parameter toolCall: The tool call result from the LLM
    /// - Returns: AIToolResultData ready for use in agent responses
    /// - Throws: ToolAdapterError if the tool is not found or execution fails
    public func executeWithCorrelation(toolCall: AIToolCallResult) async throws -> AIToolResultData {
        guard let adapter = registry.adapter(forName: toolCall.name) else {
            throw ToolAdapterError.toolNotFound(toolCall.name)
        }
        return try await adapter.executeWithId(toolCallId: toolCall.id, argumentsJSON: toolCall.arguments)
    }
}

// MARK: - ToolError Extension

public extension ToolError {
    /// Error when a tool is not found in the registry
    static func toolNotFound(_ name: String) -> ToolError {
        .executionFailed("Tool not found: \(name)")
    }
}
