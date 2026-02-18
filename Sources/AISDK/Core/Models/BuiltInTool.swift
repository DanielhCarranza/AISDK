import Foundation

/// Provider-agnostic built-in tool that providers execute server-side.
///
/// Not all providers support all tools. Unsupported tools throw
/// `ProviderError.invalidRequest` with a descriptive message.
///
/// Support matrix:
/// | Tool              | OpenAI (Responses) | Gemini | Anthropic |
/// |-------------------|--------------------|--------|-----------|
/// | `.webSearch`      | web_search         | google_search | web_search_20250305 |
/// | `.codeExecution`  | code_interpreter   | code_execution | code_execution_20250825 |
/// | `.fileSearch`     | file_search        | -      | -         |
/// | `.imageGeneration`| image_generation   | -      | -         |
/// | `.urlContext`     | -                  | url_context | -     |
/// | `.computerUse`   | computer_use_prev  | -           | computer_20250124  |
public enum BuiltInTool: Sendable, Equatable, Hashable {
    /// Web search grounding.
    case webSearch(WebSearchConfig)

    /// Web search with default configuration.
    case webSearchDefault

    /// Server-side code execution.
    case codeExecution(CodeExecutionConfig)

    /// Code execution with default configuration.
    case codeExecutionDefault

    /// File/vector search (OpenAI only).
    case fileSearch(FileSearchConfig)

    /// Image generation (OpenAI only).
    case imageGeneration(ImageGenerationConfig)

    /// Image generation with default configuration (OpenAI only).
    case imageGenerationDefault

    /// URL context fetching (Gemini only).
    case urlContext

    /// Computer use with explicit configuration (OpenAI Responses, Anthropic).
    case computerUse(ComputerUseConfig)

    /// Computer use with default configuration (1024x768).
    case computerUseDefault

    /// The canonical tool kind, for deduplication.
    public var kind: String {
        switch self {
        case .webSearch, .webSearchDefault:
            return "webSearch"
        case .codeExecution, .codeExecutionDefault:
            return "codeExecution"
        case .fileSearch:
            return "fileSearch"
        case .imageGeneration, .imageGenerationDefault:
            return "imageGeneration"
        case .urlContext:
            return "urlContext"
        case .computerUse, .computerUseDefault:
            return "computerUse"
        }
    }
}

// MARK: - Configuration Types

public extension BuiltInTool {
    struct WebSearchConfig: Sendable, Equatable, Hashable, Codable {
        /// Maximum search calls per turn (Anthropic only).
        public var maxUses: Int?
        /// Search context size: "low", "medium", "high" (OpenAI only).
        public var searchContextSize: String?
        /// Restrict results to these domains (OpenAI, Anthropic).
        public var allowedDomains: [String]?
        /// Exclude results from these domains (Anthropic only).
        public var blockedDomains: [String]?
        /// Approximate user location for localized results.
        public var userLocation: UserLocation?

        public init(
            maxUses: Int? = nil,
            searchContextSize: String? = nil,
            allowedDomains: [String]? = nil,
            blockedDomains: [String]? = nil,
            userLocation: UserLocation? = nil
        ) {
            self.maxUses = maxUses
            self.searchContextSize = searchContextSize
            self.allowedDomains = allowedDomains
            self.blockedDomains = blockedDomains
            self.userLocation = userLocation
        }
    }

    struct UserLocation: Sendable, Equatable, Hashable, Codable {
        public var city: String?
        public var region: String?
        public var country: String?
        public var timezone: String?

        public init(city: String? = nil, region: String? = nil, country: String? = nil, timezone: String? = nil) {
            self.city = city
            self.region = region
            self.country = country
            self.timezone = timezone
        }
    }

    struct CodeExecutionConfig: Sendable, Equatable, Hashable, Codable {
        /// Explicit container ID (OpenAI only).
        public var containerId: String?
        /// File IDs to make available (OpenAI only).
        public var fileIds: [String]?

        public init(containerId: String? = nil, fileIds: [String]? = nil) {
            self.containerId = containerId
            self.fileIds = fileIds
        }
    }

    struct FileSearchConfig: Sendable, Equatable, Hashable, Codable {
        /// Vector store IDs to search (required).
        public var vectorStoreIds: [String]
        /// Maximum number of results.
        public var maxNumResults: Int?
        /// Minimum relevance score threshold (0.0-1.0).
        public var scoreThreshold: Double?

        public init(vectorStoreIds: [String], maxNumResults: Int? = nil, scoreThreshold: Double? = nil) {
            self.vectorStoreIds = vectorStoreIds
            self.maxNumResults = maxNumResults
            self.scoreThreshold = scoreThreshold
        }
    }

    struct ImageGenerationConfig: Sendable, Equatable, Hashable, Codable {
        /// Quality: "low", "medium", "high", "auto".
        public var quality: String?
        /// Size: "1024x1024", "1024x1536", "1536x1024", "auto".
        public var size: String?
        /// Background: "transparent", "opaque", "auto".
        public var background: String?
        /// Output format: "png", "webp", "jpeg".
        public var outputFormat: String?
        /// Partial images for streaming (0-3).
        public var partialImages: Int?

        public init(
            quality: String? = nil,
            size: String? = nil,
            background: String? = nil,
            outputFormat: String? = nil,
            partialImages: Int? = nil
        ) {
            self.quality = quality
            self.size = size
            self.background = background
            self.outputFormat = outputFormat
            self.partialImages = partialImages
        }
    }
}
