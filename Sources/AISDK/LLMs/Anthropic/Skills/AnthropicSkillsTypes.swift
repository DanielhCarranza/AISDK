import Foundation

// MARK: - Container Configuration

/// Configuration for a container that runs skills
public struct ContainerConfig: Codable, Sendable, Equatable {
    /// Optional container ID (auto-generated if not provided)
    public let id: String?

    /// Skills to enable in this container
    public let skills: [SkillConfig]

    /// Optional timeout in seconds for skill execution
    public let timeout: Int?

    /// Optional environment variables for the container
    public let environment: [String: String]?

    public init(
        id: String? = nil,
        skills: [SkillConfig],
        timeout: Int? = nil,
        environment: [String: String]? = nil
    ) {
        self.id = id
        self.skills = skills
        self.timeout = timeout
        self.environment = environment
    }
}

// MARK: - Skill Configuration

/// Type of skill provider
public enum SkillType: String, Codable, Sendable {
    /// Built-in Anthropic skill
    case anthropic = "anthropic"

    /// Custom user-defined skill
    case custom = "custom"
}

/// Configuration for a single skill
public struct SkillConfig: Codable, Sendable, Equatable {
    /// Unique skill identifier
    public let skillId: String

    /// Skill provider type
    public let type: SkillType

    /// Optional skill version
    public let version: String?

    /// Optional skill-specific configuration
    public let config: [String: AnyCodable]?

    public init(
        skillId: String,
        type: SkillType,
        version: String? = nil,
        config: [String: AnyCodable]? = nil
    ) {
        self.skillId = skillId
        self.type = type
        self.version = version
        self.config = config
    }

    private enum CodingKeys: String, CodingKey {
        case skillId = "skill_id"
        case type
        case version
        case config
    }
}

// MARK: - Built-in Anthropic Skills

/// Known built-in Anthropic skills
public enum AnthropicSkill: String, CaseIterable {
    case webSearch = "web-search"
    case codeExecution = "code-execution"
    case fileOperations = "file-operations"
    case textAnalysis = "text-analysis"

    /// Create a skill configuration for this built-in skill
    public func config(version: String? = nil) -> SkillConfig {
        SkillConfig(
            skillId: self.rawValue,
            type: .anthropic,
            version: version
        )
    }
}

// MARK: - MCP Server Configuration

/// Transport type for MCP server connection
public enum MCPTransportType: String, Codable, Sendable {
    case url = "url"
    case websocket = "websocket"
}

/// Configuration for an MCP server
public struct MCPServerConfig: Codable, Sendable, Equatable {
    /// Display name for the server
    public let name: String

    /// Transport type (currently only "url" is supported)
    public let type: MCPTransportType

    /// Server URL
    public let url: String

    /// Optional authorization token for authenticated servers
    public let authorizationToken: String?

    /// Optional tool configuration to filter available tools
    public let toolConfiguration: MCPToolConfiguration?

    public init(
        name: String,
        url: String,
        type: MCPTransportType = .url,
        authorizationToken: String? = nil,
        toolConfiguration: MCPToolConfiguration? = nil
    ) {
        self.name = name
        self.type = type
        self.url = url
        self.authorizationToken = authorizationToken
        self.toolConfiguration = toolConfiguration
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case url
        case authorizationToken = "authorization_token"
        case toolConfiguration = "tool_configuration"
    }
}

/// Tool filtering configuration for MCP servers
public struct MCPToolConfiguration: Codable, Sendable, Equatable {
    public let enabled: Bool?
    public let allowedTools: [String]?
    public let blockedTools: [String]?

    public init(
        enabled: Bool? = nil,
        allowedTools: [String]? = nil,
        blockedTools: [String]? = nil
    ) {
        self.enabled = enabled
        self.allowedTools = allowedTools
        self.blockedTools = blockedTools
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case allowedTools = "allowed_tools"
        case blockedTools = "blocked_tools"
    }
}

// MARK: - Convenience Builders

extension ContainerConfig {
    /// Create a container with web search capability
    public static func webSearch() -> ContainerConfig {
        ContainerConfig(skills: [AnthropicSkill.webSearch.config()])
    }

    /// Create a container with code execution capability
    public static func codeExecution() -> ContainerConfig {
        ContainerConfig(skills: [AnthropicSkill.codeExecution.config()])
    }

    /// Create a container with multiple built-in skills
    public static func withSkills(_ skills: [AnthropicSkill]) -> ContainerConfig {
        ContainerConfig(skills: skills.map { $0.config() })
    }
}

extension MCPServerConfig {
    /// Create an unauthenticated MCP server configuration
    public static func unauthenticated(name: String, url: String) -> MCPServerConfig {
        MCPServerConfig(name: name, url: url)
    }

    /// Create an authenticated MCP server configuration
    public static func authenticated(
        name: String,
        url: String,
        token: String
    ) -> MCPServerConfig {
        MCPServerConfig(name: name, url: url, authorizationToken: token)
    }
}
