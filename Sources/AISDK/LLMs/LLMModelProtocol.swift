//
//  LLMModelProtocol.swift
//  AISDK
//
//  Created by AI Assistant on 01/24/25.
//

import Foundation

// MARK: - Universal LegacyLLM Provider Identification
public enum LLMProvider: String, CaseIterable, Sendable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google"
    case groq = "Groq"
    case together = "Together"
    case cohere = "Cohere"
    case huggingface = "HuggingFace"
    case ollama = "Ollama"
    case custom = "Custom"
    
    public var displayName: String {
        return rawValue
    }
}

// MARK: - Universal Model Capabilities
public struct LLMCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    // Input/Output Modalities
    public static let text = LLMCapabilities(rawValue: 1 << 0)
    public static let vision = LLMCapabilities(rawValue: 1 << 1)
    public static let audio = LLMCapabilities(rawValue: 1 << 2)
    public static let video = LLMCapabilities(rawValue: 1 << 3)
    public static let pdf = LLMCapabilities(rawValue: 1 << 4)
    
    // Functional Capabilities
    public static let tools = LLMCapabilities(rawValue: 1 << 5)
    public static let functionCalling = LLMCapabilities(rawValue: 1 << 6)
    public static let codeExecution = LLMCapabilities(rawValue: 1 << 7)
    public static let structuredOutputs = LLMCapabilities(rawValue: 1 << 8)
    public static let jsonMode = LLMCapabilities(rawValue: 1 << 9)
    
    // Advanced Capabilities
    public static let reasoning = LLMCapabilities(rawValue: 1 << 10)
    public static let thinking = LLMCapabilities(rawValue: 1 << 11)
    public static let search = LLMCapabilities(rawValue: 1 << 12)
    public static let webSearch = LLMCapabilities(rawValue: 1 << 13)
    public static let grounding = LLMCapabilities(rawValue: 1 << 14)
    
    // Generation Capabilities
    public static let imageGeneration = LLMCapabilities(rawValue: 1 << 15)
    public static let audioGeneration = LLMCapabilities(rawValue: 1 << 16)
    public static let videoGeneration = LLMCapabilities(rawValue: 1 << 17)
    public static let speechToText = LLMCapabilities(rawValue: 1 << 18)
    public static let textToSpeech = LLMCapabilities(rawValue: 1 << 19)
    
    // Operational Capabilities
    public static let streaming = LLMCapabilities(rawValue: 1 << 20)
    public static let realtime = LLMCapabilities(rawValue: 1 << 21)
    public static let liveAPI = LLMCapabilities(rawValue: 1 << 22)
    public static let caching = LLMCapabilities(rawValue: 1 << 23)
    public static let tuning = LLMCapabilities(rawValue: 1 << 24)
    public static let embedding = LLMCapabilities(rawValue: 1 << 25)
    
    // Special Features
    public static let moderation = LLMCapabilities(rawValue: 1 << 26)
    public static let computerUse = LLMCapabilities(rawValue: 1 << 27)
    public static let multilingual = LLMCapabilities(rawValue: 1 << 28)
    public static let longContext = LLMCapabilities(rawValue: 1 << 29)
    
    // Status Flags
    public static let deprecated = LLMCapabilities(rawValue: 1 << 30)
    
    // Convenience combinations
    public static let multimodal: LLMCapabilities = [.text, .vision]
    public static let fullMultimodal: LLMCapabilities = [.text, .vision, .audio, .video]
    public static let basicTools: LLMCapabilities = [.text, .tools, .functionCalling]
    public static let advancedReasoning: LLMCapabilities = [.text, .reasoning, .thinking, .tools]
}

// MARK: - Model Performance Tiers
public enum LLMPerformanceTier: String, CaseIterable, Comparable, Sendable {
    case nano = "nano"
    case mini = "mini"
    case small = "small"
    case medium = "medium"
    case large = "large"
    case pro = "pro"
    case ultra = "ultra"
    case flagship = "flagship"
    
    public static func < (lhs: LLMPerformanceTier, rhs: LLMPerformanceTier) -> Bool {
        let order: [LLMPerformanceTier] = [.nano, .mini, .small, .medium, .large, .pro, .ultra, .flagship]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
    
    public var displayName: String {
        switch self {
        case .nano: return "Nano"
        case .mini: return "Mini"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .pro: return "Pro"
        case .ultra: return "Ultra"
        case .flagship: return "Flagship"
        }
    }
}

// MARK: - Model Latency Categories
public enum LLMLatency: String, CaseIterable, Sendable {
    case ultraFast = "ultra_fast"
    case veryFast = "very_fast"
    case fast = "fast"
    case moderate = "moderate"
    case slow = "slow"
    
    public var displayName: String {
        switch self {
        case .ultraFast: return "Ultra Fast"
        case .veryFast: return "Very Fast"
        case .fast: return "Fast"
        case .moderate: return "Moderate"
        case .slow: return "Slow"
        }
    }
}

// MARK: - Model Version Types
public enum LLMVersionType: String, CaseIterable {
    case stable = "stable"
    case latest = "latest"
    case preview = "preview"
    case experimental = "experimental"
    case beta = "beta"
    case alpha = "alpha"
    case deprecated = "deprecated"
    
    public var isProduction: Bool {
        return self == .stable || self == .latest
    }
    
    public var displayName: String {
        switch self {
        case .stable: return "Stable"
        case .latest: return "Latest"
        case .preview: return "Preview"
        case .experimental: return "Experimental"
        case .beta: return "Beta"
        case .alpha: return "Alpha"
        case .deprecated: return "Deprecated"
        }
    }
}

// MARK: - Model Usage Categories
public enum LLMUsageCategory: String, CaseIterable {
    case chat = "chat"
    case completion = "completion"
    case reasoning = "reasoning"
    case coding = "coding"
    case embedding = "embedding"
    case moderation = "moderation"
    case imageGeneration = "image_generation"
    case audioGeneration = "audio_generation"
    case videoGeneration = "video_generation"
    case transcription = "transcription"
    case translation = "translation"
    case summarization = "summarization"
    case classification = "classification"
    case analysis = "analysis"
    case multimodal = "multimodal"
    case realtime = "realtime"
    case research = "research"
    case agents = "agents"
    
    public var displayName: String {
        return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Core Capability Protocol
public protocol LLMCapable {
    var capabilities: LLMCapabilities { get }
    
    func hasCapability(_ capability: LLMCapabilities) -> Bool
    func hasAllCapabilities(_ capabilities: LLMCapabilities) -> Bool
    func hasAnyCapability(_ capabilities: LLMCapabilities) -> Bool
}

public extension LLMCapable {
    func hasCapability(_ capability: LLMCapabilities) -> Bool {
        return capabilities.contains(capability)
    }
    
    func hasAllCapabilities(_ capabilities: LLMCapabilities) -> Bool {
        return self.capabilities.contains(capabilities)
    }
    
    func hasAnyCapability(_ capabilities: LLMCapabilities) -> Bool {
        return !self.capabilities.intersection(capabilities).isEmpty
    }
}

// MARK: - Model Identification Protocol
public protocol LLMModelIdentifiable {
    var name: String { get }
    var displayName: String { get }
    var description: String { get }
    var provider: LLMProvider { get }
    var category: LLMUsageCategory { get }
    var versionType: LLMVersionType { get }
}

public extension LLMModelIdentifiable {
    var displayName: String {
        return name
    }
    
    var fullName: String {
        return "\(provider.displayName) \(displayName)"
    }
    
    var isProduction: Bool {
        return versionType.isProduction
    }
}

// MARK: - Model Performance Protocol
public protocol LLMModelPerformance {
    var tier: LLMPerformanceTier? { get }
    var latency: LLMLatency? { get }
    var inputTokenLimit: Int? { get }
    var outputTokenLimit: Int? { get }
    var contextWindow: Int? { get }
    var maxRequestsPerMinute: Int? { get }
    var maxTokensPerMinute: Int? { get }
}

public extension LLMModelPerformance {
    var contextWindow: Int? {
        return inputTokenLimit
    }
    
    var hasUnlimitedContext: Bool {
        return inputTokenLimit == nil || inputTokenLimit == 0
    }
    
    var isHighPerformance: Bool {
        return tier?.rawValue == "pro" || tier?.rawValue == "ultra" || tier?.rawValue == "flagship"
    }
    
    var isFastLatency: Bool {
        return latency == .ultraFast || latency == .veryFast || latency == .fast
    }
}

// MARK: - Model Pricing Protocol
public protocol LLMModelPricing {
    var inputTokenPrice: Double? { get }  // Price per million tokens
    var outputTokenPrice: Double? { get } // Price per million tokens
    var currency: String { get }
    var pricingNotes: String? { get }
}

public extension LLMModelPricing {
    var currency: String {
        return "USD"
    }
    
    var hasPricing: Bool {
        return inputTokenPrice != nil || outputTokenPrice != nil
    }
    
    func estimatedCost(inputTokens: Int, outputTokens: Int) -> Double? {
        guard let inputPrice = inputTokenPrice, let outputPrice = outputTokenPrice else {
            return nil
        }
        
        let inputCost = (Double(inputTokens) / 1_000_000) * inputPrice
        let outputCost = (Double(outputTokens) / 1_000_000) * outputPrice
        
        return inputCost + outputCost
    }
}

// MARK: - Main LegacyLLM Model Protocol
public protocol LLMModelProtocol: LLMCapable, LLMModelIdentifiable, LLMModelPerformance {
    var id: String { get }
    var aliases: [String] { get }
    var knowledgeCutoff: String? { get }
    var specialization: String? { get }
    var releaseDate: Date? { get }
    var deprecationDate: Date? { get }
    var metadata: [String: Any] { get }
}

public extension LLMModelProtocol {
    var id: String {
        return name
    }
    
    var aliases: [String] {
        return []
    }
    
    var metadata: [String: Any] {
        return [:]
    }
    
    var isDeprecated: Bool {
        return hasCapability(.deprecated) || versionType == .deprecated
    }
    
    var isAvailable: Bool {
        return !isDeprecated && (deprecationDate == nil || deprecationDate! > Date())
    }
    
    var supportsStreaming: Bool {
        return hasCapability(.streaming)
    }
    
    var supportsTools: Bool {
        return hasCapability(.tools) || hasCapability(.functionCalling)
    }
    
    var isMultimodal: Bool {
        return hasAnyCapability(.multimodal)
    }
    
    var supportedModalities: [String] {
        var modalities: [String] = []
        if hasCapability(.text) { modalities.append("text") }
        if hasCapability(.vision) { modalities.append("vision") }
        if hasCapability(.audio) { modalities.append("audio") }
        if hasCapability(.video) { modalities.append("video") }
        if hasCapability(.pdf) { modalities.append("pdf") }
        return modalities
    }
}

// MARK: - Provider Models Management Protocol
public protocol LLMProviderModels {
    var provider: LLMProvider { get }
    var allModels: [LLMModelProtocol] { get }
    var featuredModels: [LLMModelProtocol] { get }
    var stableModels: [LLMModelProtocol] { get }
    
    func models(for category: LLMUsageCategory) -> [LLMModelProtocol]
    func models(with capabilities: LLMCapabilities) -> [LLMModelProtocol]
    func models(ofTier tier: LLMPerformanceTier) -> [LLMModelProtocol]
    func models(ofType versionType: LLMVersionType) -> [LLMModelProtocol]
    func model(named name: String) -> LLMModelProtocol?
    func model(withAlias alias: String) -> LLMModelProtocol?
}

public extension LLMProviderModels {
    var featuredModels: [LLMModelProtocol] {
        return stableModels.filter { $0.tier != nil && $0.tier! >= .large }
    }
    
    var stableModels: [LLMModelProtocol] {
        return allModels.filter { $0.versionType == .stable || $0.versionType == .latest }
    }
    
    func models(for category: LLMUsageCategory) -> [LLMModelProtocol] {
        return allModels.filter { $0.category == category }
    }
    
    func models(with capabilities: LLMCapabilities) -> [LLMModelProtocol] {
        return allModels.filter { $0.hasAllCapabilities(capabilities) }
    }
    
    func models(ofTier tier: LLMPerformanceTier) -> [LLMModelProtocol] {
        return allModels.filter { $0.tier == tier }
    }
    
    func models(ofType versionType: LLMVersionType) -> [LLMModelProtocol] {
        return allModels.filter { $0.versionType == versionType }
    }
    
    func model(named name: String) -> LLMModelProtocol? {
        return allModels.first { $0.name == name || $0.displayName == name }
    }
    
    func model(withAlias alias: String) -> LLMModelProtocol? {
        return allModels.first { $0.aliases.contains(alias) }
    }
    
    var chatModels: [LLMModelProtocol] {
        return models(for: .chat)
    }
    
    var reasoningModels: [LLMModelProtocol] {
        return models(with: .reasoning)
    }
    
    var multimodalModels: [LLMModelProtocol] {
        return models(with: .multimodal)
    }
    
    var embeddingModels: [LLMModelProtocol] {
        return models(for: .embedding)
    }
    
    var imageGenerationModels: [LLMModelProtocol] {
        return models(with: .imageGeneration)
    }
    
    var realtimeModels: [LLMModelProtocol] {
        return models(with: [.realtime, .liveAPI])
    }
}

// MARK: - Universal Model Registry Protocol
public protocol LLMModelRegistry {
    var providers: [LLMProvider] { get }
    var allModels: [LLMModelProtocol] { get }
    
    func providerModels(for provider: LLMProvider) -> LLMProviderModels?
    func registerProvider(_ providerModels: LLMProviderModels)
    func model(named name: String, from provider: LLMProvider?) -> LLMModelProtocol?
    func recommendedModel(for category: LLMUsageCategory, with capabilities: LLMCapabilities) -> LLMModelProtocol?
}

// MARK: - Model Compatibility Bridge
public struct LLMModelAdapter: LLMModelProtocol {
    // Required LLMModelIdentifiable
    public let name: String
    public let displayName: String
    public let description: String
    public let provider: LLMProvider
    public let category: LLMUsageCategory
    public let versionType: LLMVersionType
    
    // Required LLMCapable
    public let capabilities: LLMCapabilities
    
    // Required LLMModelPerformance
    public let tier: LLMPerformanceTier?
    public let latency: LLMLatency?
    public let inputTokenLimit: Int?
    public let outputTokenLimit: Int?
    public let maxRequestsPerMinute: Int?
    public let maxTokensPerMinute: Int?
    
    // Optional LLMModelProtocol
    public let id: String
    public let aliases: [String]
    public let knowledgeCutoff: String?
    public let specialization: String?
    public let releaseDate: Date?
    public let deprecationDate: Date?
    public let metadata: [String: Any]
    
    public init(
        name: String,
        displayName: String? = nil,
        description: String,
        provider: LLMProvider,
        category: LLMUsageCategory,
        versionType: LLMVersionType = .stable,
        capabilities: LLMCapabilities,
        tier: LLMPerformanceTier? = nil,
        latency: LLMLatency? = nil,
        inputTokenLimit: Int? = nil,
        outputTokenLimit: Int? = nil,
        maxRequestsPerMinute: Int? = nil,
        maxTokensPerMinute: Int? = nil,
        id: String? = nil,
        aliases: [String] = [],
        knowledgeCutoff: String? = nil,
        specialization: String? = nil,
        releaseDate: Date? = nil,
        deprecationDate: Date? = nil,
        metadata: [String: Any] = [:]
    ) {
        self.name = name
        self.displayName = displayName ?? name
        self.description = description
        self.provider = provider
        self.category = category
        self.versionType = versionType
        self.capabilities = capabilities
        self.tier = tier
        self.latency = latency
        self.inputTokenLimit = inputTokenLimit
        self.outputTokenLimit = outputTokenLimit
        self.maxRequestsPerMinute = maxRequestsPerMinute
        self.maxTokensPerMinute = maxTokensPerMinute
        self.id = id ?? name
        self.aliases = aliases
        self.knowledgeCutoff = knowledgeCutoff
        self.specialization = specialization
        self.releaseDate = releaseDate
        self.deprecationDate = deprecationDate
        self.metadata = metadata
    }
}

// MARK: - Legacy AgenticModels Bridge
extension LLMModel {
    func toProtocol() -> LLMModelAdapter {
        // Convert old Modality to new LLMCapabilities
        var capabilities: LLMCapabilities = []
        for modality in modalities {
            switch modality {
            case .text: capabilities.insert(.text)
            case .vision: capabilities.insert(.vision)
            case .audio: capabilities.insert(.audio)
            case .video: capabilities.insert(.video)
            }
        }
        
        // Add tool capabilities based on mode
        if let mode = mode {
            switch mode {
            case .parallelTools: capabilities.insert([.tools, .functionCalling])
            case .tools: capabilities.insert(.tools)
            case .json: capabilities.insert(.jsonMode)
            }
        }
        
        // Determine provider from name patterns
        let provider: LLMProvider
        if name.contains("gpt") || name.contains("o1") || name.contains("o4") {
            provider = .openai
        } else if name.contains("claude") {
            provider = .anthropic
        } else if name.contains("gemini") {
            provider = .google
        } else if name.contains("llama") || name.contains("mixtral") {
            provider = .groq
        } else {
            provider = .custom
        }
        
        return LLMModelAdapter(
            name: name,
            description: "Legacy model from AgenticModels",
            provider: provider,
            category: .chat,
            capabilities: capabilities,
            metadata: ["legacy": true, "apiKey": apiKey as Any, "mode": mode?.rawValue as Any]
        )
    }
} 