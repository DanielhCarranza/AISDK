//
//  AITool.swift
//  AISDK
//
//  Redesigned AITool protocol with immutable, Sendable-compliant design
//  Based on Vercel AI SDK 6.x patterns for concurrent tool execution
//

import Foundation

// MARK: - AITool Protocol

/// A protocol defining an immutable, Sendable-compliant tool for AI agent execution.
///
/// `AITool` is designed for concurrent safety with the following principles:
/// - **Immutable**: Tool configuration is defined at the type level via static properties
/// - **Sendable**: Full concurrency compliance for actor-based agent execution
/// - **Type-safe**: Generic arguments and metadata with Codable conformance
/// - **Per-tool timeout**: Each tool can specify its execution timeout
///
/// ## Example Implementation
/// ```swift
/// struct WeatherTool: AITool {
///     typealias Arguments = WeatherArguments
///     typealias Metadata = EmptyMetadata
///
///     static var name: String { "get_weather" }
///     static var description: String { "Get current weather for a location" }
///     static var timeout: TimeInterval { 30.0 }
///
///     struct WeatherArguments: Codable, Sendable {
///         let location: String
///         let unit: String?
///     }
///
///     static func execute(arguments: WeatherArguments) async throws -> AIToolResult<EmptyMetadata> {
///         let weather = try await fetchWeather(location: arguments.location)
///         return AIToolResult(content: weather.description)
///     }
/// }
/// ```
///
/// ## JSON Schema Generation
/// To generate a JSON schema for LLM function calling, use:
/// ```swift
/// let schema = WeatherTool.generateSchema()
/// ```
///
/// ## Migration from Legacy Tool Protocol
/// The legacy `Tool` protocol uses `@Parameter` property wrappers and mutable instances.
/// Use `ToolAdapter` to wrap legacy tools for compatibility with `AITool`-based systems.
public protocol AITool: Sendable {
    /// The type of arguments this tool accepts
    associatedtype Arguments: Codable & Sendable

    /// The type of metadata this tool returns (use `EmptyMetadata` for none)
    associatedtype Metadata: AIToolMetadata = EmptyMetadata

    /// The unique name of this tool (used for function calling)
    static var name: String { get }

    /// A description of what this tool does (shown to the LLM)
    static var description: String { get }

    /// The execution timeout for this tool in seconds (default: 60, must be positive and finite)
    static var timeout: TimeInterval { get }

    /// Execute the tool with the provided arguments
    ///
    /// - Parameter arguments: The decoded arguments from the LLM
    /// - Returns: The tool result with content and optional metadata
    /// - Throws: If tool execution fails
    static func execute(arguments: Arguments) async throws -> AIToolResult<Metadata>

    /// Generate a JSON schema for this tool's arguments
    ///
    /// Override this method to provide a custom schema with parameter descriptions.
    /// The default implementation returns a basic accept-any schema with no properties.
    /// **Production tools should override this** to provide accurate parameter definitions.
    ///
    /// - Returns: A ToolSchema suitable for LLM function calling
    static func generateSchema() -> ToolSchema
}

// MARK: - Default Implementations

extension AITool {
    /// Default timeout of 60 seconds
    public static var timeout: TimeInterval { 60.0 }

    /// Default schema generation - returns a basic accept-any schema.
    ///
    /// **Important**: This default implementation returns an empty properties dictionary
    /// with `additionalProperties: true`, which allows any arguments. For production use,
    /// you **must** override this method to provide accurate parameter descriptions.
    public static func generateSchema() -> ToolSchema {
        // Create a basic accept-any schema - implementers should override for detailed schemas
        return ToolSchema(
            type: "function",
            function: ToolFunction(
                name: name,
                description: description,
                parameters: Parameters(
                    type: "object",
                    properties: [:],
                    required: nil,
                    additionalProperties: true
                )
            )
        )
    }
}

// MARK: - AIToolResult

/// The result of an AITool execution
///
/// Contains the string content returned to the LLM and optional metadata
/// that can be used for UI rendering or other purposes.
public struct AIToolResult<M: AIToolMetadata>: Sendable {
    /// The text content returned to the LLM
    public let content: String

    /// Optional metadata for UI rendering or other purposes
    public let metadata: M?

    /// Creates a tool result with content only
    ///
    /// - Parameter content: The text content to return
    public init(content: String) where M == EmptyMetadata {
        self.content = content
        self.metadata = nil
    }

    /// Creates a tool result with content and metadata
    ///
    /// - Parameters:
    ///   - content: The text content to return
    ///   - metadata: Additional metadata for the result
    public init(content: String, metadata: M?) {
        self.content = content
        self.metadata = metadata
    }
}

// MARK: - AIToolMetadata Protocol

/// Protocol for tool metadata types
///
/// Metadata provides additional information about tool execution results
/// that can be used for UI rendering, logging, or other purposes.
public protocol AIToolMetadata: Codable, Sendable {}

// MARK: - EmptyMetadata

/// Empty metadata type for tools that don't return metadata
///
/// Use this as the `Metadata` associated type when your tool doesn't
/// need to return any additional metadata.
public struct EmptyMetadata: AIToolMetadata, Equatable {
    public init() {}
}

// MARK: - AnyAIToolMetadata

/// Type-erased wrapper for AIToolMetadata
///
/// Provides a Sendable container for any AIToolMetadata type, with JSON encoding support.
public struct AnyAIToolMetadata: Sendable {
    /// The fully-qualified underlying metadata type name (for identification, not display)
    public let typeName: String

    /// The JSON-encoded metadata (if encodable)
    public let jsonData: Data?

    /// Description of encoding error, if any
    public let encodingError: String?

    /// Creates a type-erased metadata wrapper
    ///
    /// - Parameter metadata: The metadata to wrap
    public init<M: AIToolMetadata>(_ metadata: M) {
        // Use fully-qualified name for uniqueness across modules
        self.typeName = String(reflecting: type(of: metadata))
        do {
            self.jsonData = try JSONEncoder().encode(metadata)
            self.encodingError = nil
        } catch {
            self.jsonData = nil
            self.encodingError = error.localizedDescription
        }
    }

    /// Decode the metadata to a specific type
    ///
    /// - Parameter type: The metadata type to decode to
    /// - Returns: The decoded metadata, or nil if decoding fails
    public func decode<M: AIToolMetadata>(as type: M.Type) -> M? {
        guard let data = jsonData else { return nil }
        return try? JSONDecoder().decode(M.self, from: data)
    }
}

// MARK: - AIToolExecutionResult

/// The result of executing an AITool
///
/// Contains the content string and optional type-erased metadata.
public struct AIToolExecutionResult: Sendable {
    /// The text content returned to the LLM
    public let content: String

    /// Optional type-erased metadata
    public let metadata: AnyAIToolMetadata?

    public init(content: String, metadata: AnyAIToolMetadata? = nil) {
        self.content = content
        self.metadata = metadata
    }
}

// MARK: - AIToolExecutor

/// Executor for running AITool implementations with timeout and argument parsing
///
/// This executor handles:
/// - JSON argument parsing and validation (with snake_case key support)
/// - Timeout enforcement via the tool's static timeout
/// - Error wrapping in AISDKErrorV2 for consistent error handling
public struct AIToolExecutor: Sendable {

    /// Maximum allowed timeout in seconds (24 hours)
    private static let maxTimeout: TimeInterval = 86400

    /// Execute an AITool with raw JSON arguments
    ///
    /// - Parameters:
    ///   - toolType: The AITool type to execute
    ///   - arguments: JSON string containing the tool arguments
    /// - Returns: The tool execution result with content and optional metadata
    /// - Throws: AISDKErrorV2 for all error cases (parsing, timeout, execution)
    public static func execute<T: AITool>(
        _ toolType: T.Type,
        arguments: String
    ) async throws -> AIToolExecutionResult {
        // Normalize empty/whitespace arguments to empty JSON object
        let normalizedArgs = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString = normalizedArgs.isEmpty ? "{}" : normalizedArgs

        // Parse arguments
        guard let data = jsonString.data(using: .utf8) else {
            throw AISDKErrorV2.toolExecutionFailed(
                tool: T.name,
                reason: "Invalid UTF-8 in arguments"
            )
        }

        let decodedArgs: T.Arguments
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decodedArgs = try decoder.decode(T.Arguments.self, from: data)
        } catch {
            throw AISDKErrorV2.toolExecutionFailed(
                tool: T.name,
                reason: "Failed to decode arguments: \(error.localizedDescription)"
            )
        }

        // Validate and clamp timeout
        let timeout = validatedTimeout(T.timeout)

        // Execute with timeout
        let result: AIToolResult<T.Metadata>
        do {
            result = try await withThrowingTaskGroup(of: AIToolResult<T.Metadata>.self) { group in
                group.addTask {
                    try await T.execute(arguments: decodedArgs)
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw AISDKErrorV2.toolTimeout(
                        tool: T.name,
                        after: timeout
                    )
                }

                // Return first completed, cancel the other
                guard let taskResult = try await group.next() else {
                    // Group was cancelled before producing any result
                    throw AISDKErrorV2.cancelled()
                }
                group.cancelAll()
                return taskResult
            }
        } catch let error as AISDKErrorV2 {
            // Re-throw SDK errors as-is
            throw error
        } catch is CancellationError {
            throw AISDKErrorV2.cancelled()
        } catch {
            // Wrap non-SDK errors in toolExecutionFailed for PHI-safe error handling
            throw AISDKErrorV2.toolExecutionFailed(
                tool: T.name,
                reason: "Execution failed: \(error.localizedDescription)"
            )
        }

        // Wrap metadata if present
        let wrappedMetadata: AnyAIToolMetadata?
        if let metadata = result.metadata {
            wrappedMetadata = AnyAIToolMetadata(metadata)
        } else {
            wrappedMetadata = nil
        }

        return AIToolExecutionResult(content: result.content, metadata: wrappedMetadata)
    }

    /// Validate and clamp timeout to safe bounds
    private static func validatedTimeout(_ timeout: TimeInterval) -> TimeInterval {
        guard timeout.isFinite && timeout > 0 else {
            // Invalid timeout, use default
            return 60.0
        }
        return min(timeout, maxTimeout)
    }
}

// MARK: - Type-Erased AITool Wrapper

/// Type-erased wrapper for AITool, enabling heterogeneous tool collections
///
/// This wrapper allows storing different AITool types in arrays or dictionaries
/// while preserving their execution capabilities.
///
/// Note: Marked `@unchecked Sendable` because `ToolSchema` is not yet Sendable.
/// The schema is immutable after initialization, making this safe in practice.
public struct AnyAITool: @unchecked Sendable {
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

    /// Creates a type-erased wrapper for an AITool
    ///
    /// - Parameter toolType: The AITool type to wrap
    public init<T: AITool>(_ toolType: T.Type) {
        self.name = T.name
        self.description = T.description
        self.timeout = T.timeout
        self.schema = T.generateSchema()
        self._execute = { arguments in
            try await AIToolExecutor.execute(T.self, arguments: arguments)
        }
    }

    /// Execute the tool with raw JSON arguments
    ///
    /// - Parameter arguments: JSON string containing the tool arguments
    /// - Returns: The tool execution result
    /// - Throws: AISDKErrorV2 if execution fails
    public func execute(arguments: String) async throws -> AIToolExecutionResult {
        try await _execute(arguments)
    }
}

// MARK: - AIToolRegistry

/// Registry for managing AITool types by name
///
/// Provides lookup and execution capabilities for a collection of tools.
public final class AIToolRegistry: @unchecked Sendable {
    /// Thread-safe storage for tools
    private var tools: [String: AnyAITool] = [:]
    private let lock = NSLock()

    /// Creates an empty tool registry
    public init() {}

    /// Creates a tool registry with the provided tools
    ///
    /// - Parameter tools: Array of AITool types to register
    public init<each T: AITool>(tools: repeat (each T).Type) {
        repeat register((each tools))
    }

    /// Register a tool type
    ///
    /// - Parameter toolType: The AITool type to register
    /// - Note: Overwrites any existing tool with the same name
    public func register<T: AITool>(_ toolType: T.Type) {
        let wrapped = AnyAITool(toolType)
        lock.lock()
        tools[T.name] = wrapped
        lock.unlock()
    }

    /// Look up a tool by name
    ///
    /// - Parameter name: The tool name to look up
    /// - Returns: The wrapped tool, or nil if not found
    public func tool(named name: String) -> AnyAITool? {
        lock.lock()
        defer { lock.unlock() }
        return tools[name]
    }

    /// Get all registered tool names (sorted for deterministic ordering)
    public var registeredNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return tools.keys.sorted()
    }

    /// Get all registered tools as schemas (sorted by name for deterministic ordering)
    public var schemas: [ToolSchema] {
        lock.lock()
        defer { lock.unlock() }
        return tools.keys.sorted().compactMap { tools[$0]?.schema }
    }

    /// Execute a tool by name
    ///
    /// - Parameters:
    ///   - name: The tool name
    ///   - arguments: JSON string containing arguments
    /// - Returns: The tool execution result
    /// - Throws: AISDKErrorV2.toolNotFound if tool doesn't exist, or other AISDKErrorV2 for execution errors
    public func execute(
        name: String,
        arguments: String
    ) async throws -> AIToolExecutionResult {
        guard let tool = tool(named: name) else {
            throw AISDKErrorV2.toolNotFound(name)
        }
        return try await tool.execute(arguments: arguments)
    }
}
