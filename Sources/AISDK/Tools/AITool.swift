//
//  AITool.swift
//  AISDK
//
//  Unified, instance-based tool protocol with @Parameter/@AIParameter support.
//

import Foundation

// MARK: - AITool Protocol

/// Enhanced tool protocol with validation and parameter binding.
public protocol AITool: Sendable {
    /// Tool identifier
    var name: String { get }

    /// Human-readable description
    var description: String { get }

    /// Whether to return result directly to the user without model mediation
    var returnToolResponse: Bool { get }

    /// Initialize tool with default parameter values
    init()

    /// Generate JSON schema for parameters
    static func jsonSchema() -> ToolSchema

    /// Validate parameters before execution
    static func validate(arguments: [String: Any]) throws

    /// Bind parameters to the tool instance
    mutating func setParameters(from arguments: [String: Any]) throws

    /// Validate and bind parameters from JSON data
    mutating func validateAndSetParameters(_ argumentsData: Data) throws -> Self

    /// Execute the tool
    func execute() async throws -> AIToolResult
}

// MARK: - AIToolResult

public struct AIToolResult: Sendable {
    public let content: String
    public let metadata: ToolMetadata?
    public let artifacts: [ToolArtifact]?

    public init(
        content: String,
        metadata: ToolMetadata? = nil,
        artifacts: [ToolArtifact]? = nil
    ) {
        self.content = content
        self.metadata = metadata
        self.artifacts = artifacts
    }
}

// MARK: - AIToolExecutionResult

/// Type-erased execution result for registry execution.
public struct AIToolExecutionResult: Sendable {
    public let content: String
    public let metadata: ToolMetadata?
    public let artifacts: [ToolArtifact]?

    public init(content: String, metadata: ToolMetadata? = nil, artifacts: [ToolArtifact]? = nil) {
        self.content = content
        self.metadata = metadata
        self.artifacts = artifacts
    }
}

// MARK: - AIToolRegistry

/// Thread-safe registry for tool management.
public final class AIToolRegistry: @unchecked Sendable {
    private var tools: [String: AITool.Type] = [:]
    private let lock = NSLock()

    public static let shared = AIToolRegistry()

    public init() {}

    public func register(_ toolType: AITool.Type) {
        let name = toolType.init().name.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!name.isEmpty, "Tool name must not be empty")
        lock.lock()
        tools[name] = toolType
        lock.unlock()
    }

    public func registerAll(tools: [AITool.Type]) {
        tools.forEach { register($0) }
    }

    public func toolType(forName name: String) -> AITool.Type? {
        lock.lock()
        defer { lock.unlock() }
        return tools[name]
    }

    public var registeredNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return tools.keys.sorted()
    }

    public var schemas: [ToolSchema] {
        lock.lock()
        defer { lock.unlock() }
        return tools.keys.sorted().compactMap { tools[$0]?.jsonSchema() }
    }

    public func execute(name: String, arguments: String) async throws -> AIToolExecutionResult {
        guard let toolType = toolType(forName: name) else {
            throw AISDKErrorV2.toolNotFound(name)
        }

        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveJSON = trimmed.isEmpty ? "{}" : trimmed

        guard let data = effectiveJSON.data(using: .utf8) else {
            throw ToolError.invalidParameters("Invalid JSON string encoding")
        }

        var tool = toolType.init()
        let configured = try tool.validateAndSetParameters(data)
        let result = try await configured.execute()

        return AIToolExecutionResult(
            content: result.content,
            metadata: result.metadata,
            artifacts: result.artifacts
        )
    }

    // MARK: - Static conveniences (shared registry)

    public static func register(tool: AITool.Type) {
        shared.register(tool)
    }

    public static func registerAll(tools: [AITool.Type]) {
        shared.registerAll(tools: tools)
    }

    public static func toolType(forName name: String) -> AITool.Type? {
        shared.toolType(forName: name)
    }

    public static var registeredNames: [String] {
        shared.registeredNames
    }
}
