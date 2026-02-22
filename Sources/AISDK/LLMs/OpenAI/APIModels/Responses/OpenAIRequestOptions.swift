//
//  OpenAIRequestOptions.swift
//  AISDK
//
//  OpenAI-specific request options for built-in tools and features
//  Keeps OpenAI features separate from core API while maintaining provider-agnostic design
//

import Foundation

// MARK: - OpenAI Request Options

/// OpenAI-specific request options
/// Use these to configure built-in tools and OpenAI-specific features
/// while keeping the core AITextRequest provider-agnostic
public struct OpenAIRequestOptions: Sendable {
    /// Web search configuration
    public var webSearch: WebSearchConfig?

    /// File search (RAG) configuration
    public var fileSearch: FileSearchConfig?

    /// Code interpreter configuration
    public var codeInterpreter: CodeInterpreterConfig?

    /// Server-side storage setting
    /// - nil: Use OpenAI's default (privacy-first)
    /// - true: Store conversation on OpenAI servers
    /// - false: Don't store (ephemeral)
    public var store: Bool?

    /// Run as background task for long operations
    public var background: Bool?

    /// Prompt caching key for repeated requests
    public var promptCacheKey: String?

    /// Service tier selection
    public var serviceTier: ServiceTier?

    /// Reasoning configuration for o1/o3 models
    public var reasoning: ReasoningConfig?

    public init() {}

    public init(
        webSearch: WebSearchConfig? = nil,
        fileSearch: FileSearchConfig? = nil,
        codeInterpreter: CodeInterpreterConfig? = nil,
        store: Bool? = nil,
        background: Bool? = nil,
        promptCacheKey: String? = nil,
        serviceTier: ServiceTier? = nil,
        reasoning: ReasoningConfig? = nil
    ) {
        self.webSearch = webSearch
        self.fileSearch = fileSearch
        self.codeInterpreter = codeInterpreter
        self.store = store
        self.background = background
        self.promptCacheKey = promptCacheKey
        self.serviceTier = serviceTier
        self.reasoning = reasoning
    }
}

// MARK: - Web Search Configuration

/// Configuration for OpenAI's built-in web search tool
public struct WebSearchConfig: Sendable {
    /// Whether web search is enabled
    public var enabled: Bool

    /// How much context to include from search results
    public var searchContextSize: SearchContextSize

    /// Domain filters (allow/block lists)
    public var domainFilters: DomainFilters?

    /// User location for localized results
    public var userLocation: UserLocation?

    public init(
        enabled: Bool = true,
        searchContextSize: SearchContextSize = .medium,
        domainFilters: DomainFilters? = nil,
        userLocation: UserLocation? = nil
    ) {
        self.enabled = enabled
        self.searchContextSize = searchContextSize
        self.domainFilters = domainFilters
        self.userLocation = userLocation
    }
}

/// Search context size for web search results
public enum SearchContextSize: String, Codable, Sendable {
    case low
    case medium
    case high
}

/// Domain filters for web search
public struct DomainFilters: Codable, Sendable {
    public var allowedDomains: [String]?
    public var blockedDomains: [String]?

    public init(allowedDomains: [String]? = nil, blockedDomains: [String]? = nil) {
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
    }

    /// Create a filter that only allows specific domains
    public static func allow(_ domains: [String]) -> DomainFilters {
        DomainFilters(allowedDomains: domains)
    }

    /// Create a filter that blocks specific domains
    public static func block(_ domains: [String]) -> DomainFilters {
        DomainFilters(blockedDomains: domains)
    }
}

/// User location for localized search results
public struct UserLocation: Codable, Sendable {
    public let type: String
    public let country: String?
    public let region: String?
    public let city: String?
    public let timezone: String?

    public init(country: String? = nil, region: String? = nil, city: String? = nil, timezone: String? = nil) {
        self.type = "approximate"
        self.country = country
        self.region = region
        self.city = city
        self.timezone = timezone
    }
}

// MARK: - File Search Configuration

/// Configuration for OpenAI's built-in file search (RAG) tool
public struct FileSearchConfig: Sendable {
    /// Whether file search is enabled
    public var enabled: Bool

    /// Vector store IDs to search
    public var vectorStoreIds: [String]

    /// Maximum number of results per search
    public var maxNumResults: Int

    /// Ranking options for search results
    public var rankingOptions: FileSearchRankingOptions?

    /// Filters to apply to search
    public var filters: FileSearchFilters?

    public init(
        vectorStoreIds: [String],
        enabled: Bool = true,
        maxNumResults: Int = 10,
        rankingOptions: FileSearchRankingOptions? = nil,
        filters: FileSearchFilters? = nil
    ) {
        self.enabled = enabled
        self.vectorStoreIds = vectorStoreIds
        self.maxNumResults = maxNumResults
        self.rankingOptions = rankingOptions
        self.filters = filters
    }
}

/// Ranking options for file search results
public struct FileSearchRankingOptions: Codable, Sendable, Equatable {
    public let ranker: String
    public let scoreThreshold: Double?

    public init(ranker: String = "default_2024_11_15", scoreThreshold: Double? = nil) {
        self.ranker = ranker
        self.scoreThreshold = scoreThreshold
    }

    enum CodingKeys: String, CodingKey {
        case ranker
        case scoreThreshold = "score_threshold"
    }
}

/// Filters for file search
public struct FileSearchFilters: Codable, Sendable {
    public let type: String
    public let filters: [FileSearchFilter]

    public struct FileSearchFilter: Codable, Sendable {
        public let type: String
        public let key: String
        public let value: String

        public init(type: String, key: String, value: String) {
            self.type = type
            self.key = key
            self.value = value
        }
    }

    public init(type: String, filters: [FileSearchFilter]) {
        self.type = type
        self.filters = filters
    }

    /// Create an AND filter
    public static func and(_ filters: [FileSearchFilter]) -> FileSearchFilters {
        FileSearchFilters(type: "and", filters: filters)
    }

    /// Create an OR filter
    public static func or(_ filters: [FileSearchFilter]) -> FileSearchFilters {
        FileSearchFilters(type: "or", filters: filters)
    }
}

// MARK: - Code Interpreter Configuration

/// Configuration for OpenAI's built-in code interpreter tool
public struct CodeInterpreterConfig: Sendable {
    /// Whether code interpreter is enabled
    public var enabled: Bool

    /// Container ID to use (for persistent state)
    public var containerId: String?

    /// File IDs to make available in the container
    public var fileIds: [String]?

    public init(
        enabled: Bool = true,
        containerId: String? = nil,
        fileIds: [String]? = nil
    ) {
        self.enabled = enabled
        self.containerId = containerId
        self.fileIds = fileIds
    }
}

// MARK: - Service Tier

/// Service tier selection for OpenAI API
public enum ServiceTier: String, Codable, Sendable {
    case auto
    case `default`
    case flex
}

// MARK: - Reasoning Configuration

/// Reasoning configuration for o1/o3 models
public struct ReasoningConfig: Codable, Sendable {
    public let effort: ReasoningEffort?
    public let summary: ReasoningSummary?

    public init(effort: ReasoningEffort? = nil, summary: ReasoningSummary? = nil) {
        self.effort = effort
        self.summary = summary
    }

    /// Reasoning effort level
    public enum ReasoningEffort: String, Codable, Sendable {
        case low
        case medium
        case high
    }

    /// Reasoning summary mode
    public enum ReasoningSummary: String, Codable, Sendable {
        case auto
        case concise
        case detailed
    }
}

// MARK: - Convenience Extensions

public extension OpenAIRequestOptions {
    /// Create options with web search enabled
    static func withWebSearch(
        searchContextSize: SearchContextSize = .medium,
        domainFilters: DomainFilters? = nil,
        userLocation: UserLocation? = nil
    ) -> OpenAIRequestOptions {
        var options = OpenAIRequestOptions()
        options.webSearch = WebSearchConfig(
            enabled: true,
            searchContextSize: searchContextSize,
            domainFilters: domainFilters,
            userLocation: userLocation
        )
        return options
    }

    /// Create options with file search enabled
    static func withFileSearch(
        vectorStoreIds: [String],
        maxNumResults: Int = 10,
        rankingOptions: FileSearchRankingOptions? = nil
    ) -> OpenAIRequestOptions {
        var options = OpenAIRequestOptions()
        options.fileSearch = FileSearchConfig(
            vectorStoreIds: vectorStoreIds,
            enabled: true,
            maxNumResults: maxNumResults,
            rankingOptions: rankingOptions
        )
        return options
    }

    /// Create options with code interpreter enabled
    static func withCodeInterpreter(
        containerId: String? = nil,
        fileIds: [String]? = nil
    ) -> OpenAIRequestOptions {
        var options = OpenAIRequestOptions()
        options.codeInterpreter = CodeInterpreterConfig(
            enabled: true,
            containerId: containerId,
            fileIds: fileIds
        )
        return options
    }

    /// Create options with reasoning configuration for o1/o3 models
    static func withReasoning(
        effort: ReasoningConfig.ReasoningEffort = .medium,
        summary: ReasoningConfig.ReasoningSummary? = .auto
    ) -> OpenAIRequestOptions {
        var options = OpenAIRequestOptions()
        options.reasoning = ReasoningConfig(effort: effort, summary: summary)
        return options
    }
}
