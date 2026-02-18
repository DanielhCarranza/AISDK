//
//  ModelRegistry.swift
//  AISDK
//
//  Centralized model registry for Phase 2 routing layer
//  Manages model metadata, capabilities, and provider mappings
//

import Foundation

// MARK: - ResolvedModel

/// A resolved model with routing information
///
/// Contains all information needed to route a request to a specific model,
/// including the canonical ID that can be used with provider clients.
public struct ResolvedModel: Sendable {
    /// The provider that serves this model
    public let provider: LLMProvider

    /// The model ID to use in API requests (e.g., "gpt-4o", "claude-3-opus")
    public let modelId: String

    /// The canonical registry ID (e.g., "openai/gpt-4o")
    public let canonicalId: String

    /// Model capabilities
    public let capabilities: LLMCapabilities

    /// Performance tier
    public let tier: LLMPerformanceTier?

    /// Expected latency
    public let latency: LLMLatency?

    /// Maximum input context window
    public let maxContextTokens: Int?

    /// Maximum output tokens
    public let maxOutputTokens: Int?

    /// Whether this model is currently available
    public let isAvailable: Bool

    /// Human-readable display name
    public let displayName: String
}

// MARK: - ModelRegistry

/// Centralized registry for AI models across all providers
///
/// ModelRegistry provides a unified interface for discovering and querying
/// models from multiple providers (OpenRouter, LiteLLM, direct provider clients).
/// It manages model metadata, capabilities, aliases, and supports capability-aware
/// routing decisions.
///
/// ## Features
/// - Provider registration and discovery
/// - Model lookup by ID, alias, or capabilities
/// - Capability-aware model recommendations via `resolve()`
/// - Thread-safe access via actor isolation
///
/// ## Usage
/// ```swift
/// let registry = ModelRegistry.shared
/// await registry.registerProvider(openRouterProvider)
///
/// // Resolve a model for routing
/// if let resolved = await registry.resolve(
///     category: .chat,
///     capabilities: [.vision, .tools],
///     preferredProvider: .anthropic
/// ) {
///     print("Use \(resolved.modelId) via \(resolved.provider)")
/// }
///
/// // Find a model by ID
/// if let model = await registry.model(named: "anthropic/claude-3-opus") {
///     print(model.capabilities)
/// }
/// ```
///
/// ## Design Note
/// This actor provides async-safe methods that parallel the `LLMModelRegistry` protocol.
/// The async design ensures thread safety when used from multiple concurrent contexts.
public actor ModelRegistry {
    // MARK: - Singleton

    /// Shared registry instance
    public static let shared = ModelRegistry()

    // MARK: - State

    private var providerRegistry: [LLMProvider: any LLMProviderModels] = [:]
    /// Primary index: canonical ID -> RegisteredModel (only canonical IDs)
    private var primaryIndex: [String: RegisteredModel] = [:]
    /// Lookup index: all names/aliases -> canonical ID
    private var lookupIndex: [String: String] = [:]
    /// Alias-only index: alias -> canonical ID (excludes canonical IDs and bare names)
    private var aliasIndex: [String: String] = [:]
    /// Set of providers that have models registered (includes via register(model:) calls)
    private var knownProviders: Set<LLMProvider> = []

    // MARK: - Initialization

    public init() {}

    // MARK: - Model Resolution (Primary Routing API)

    /// Resolve the best model for a request with routing information
    ///
    /// This is the primary API for the routing layer. It returns a `ResolvedModel`
    /// containing all information needed to route a request to the appropriate provider.
    ///
    /// - Parameters:
    ///   - category: The usage category (e.g., .chat, .reasoning)
    ///   - capabilities: Required capabilities the model must have
    ///   - preferredProvider: Optional preferred provider
    ///   - minimumTier: Optional minimum performance tier
    ///   - minimumContext: Optional minimum context window size
    /// - Returns: A resolved model ready for routing, or nil if no match found
    public func resolve(
        category: LLMUsageCategory,
        capabilities: LLMCapabilities,
        preferredProvider: LLMProvider? = nil,
        minimumTier: LLMPerformanceTier? = nil,
        minimumContext: Int? = nil
    ) -> ResolvedModel? {
        // Find all models matching the criteria
        let candidates = primaryIndex.values.filter { registered in
            let model = registered.model
            // Category match
            guard model.category == category else { return false }
            // Capabilities match
            guard model.hasAllCapabilities(capabilities) else { return false }
            // Must be available
            guard model.isAvailable else { return false }
            // Minimum tier filter
            if let minTier = minimumTier {
                guard let modelTier = model.tier, modelTier >= minTier else { return false }
            }
            // Minimum context filter
            if let minContext = minimumContext {
                guard let limit = model.inputTokenLimit, limit >= minContext else { return false }
            }
            return true
        }

        // Sort by preference
        let sorted = candidates.sorted { lhs, rhs in
            // Preferred provider gets priority
            if let preferred = preferredProvider {
                if lhs.provider == preferred && rhs.provider != preferred { return true }
                if rhs.provider == preferred && lhs.provider != preferred { return false }
            }

            // Then by tier (higher is better)
            if let lhsTier = lhs.model.tier, let rhsTier = rhs.model.tier {
                if lhsTier != rhsTier {
                    return lhsTier > rhsTier
                }
            } else if lhs.model.tier != nil {
                return true
            } else if rhs.model.tier != nil {
                return false
            }

            // Then by version type (stable > latest > preview > etc)
            let versionOrder: [LLMVersionType] = [.stable, .latest, .preview, .beta, .alpha, .experimental]
            let lhsOrder = versionOrder.firstIndex(of: lhs.model.versionType) ?? versionOrder.count
            let rhsOrder = versionOrder.firstIndex(of: rhs.model.versionType) ?? versionOrder.count
            return lhsOrder < rhsOrder
        }

        guard let best = sorted.first else { return nil }

        return ResolvedModel(
            provider: best.provider,
            modelId: best.model.name,
            canonicalId: best.canonicalId,
            capabilities: best.model.capabilities,
            tier: best.model.tier,
            latency: best.model.latency,
            maxContextTokens: best.model.inputTokenLimit,
            maxOutputTokens: best.model.outputTokenLimit,
            isAvailable: best.model.isAvailable,
            displayName: best.model.displayName
        )
    }

    /// Get resolved model info by name or alias
    ///
    /// Returns routing information for a specific model, useful when the caller
    /// already knows which model they want.
    public func resolvedModel(named name: String, from provider: LLMProvider? = nil) -> ResolvedModel? {
        guard let registered = lookupRegisteredModel(named: name, from: provider) else {
            return nil
        }

        return ResolvedModel(
            provider: registered.provider,
            modelId: registered.model.name,
            canonicalId: registered.canonicalId,
            capabilities: registered.model.capabilities,
            tier: registered.model.tier,
            latency: registered.model.latency,
            maxContextTokens: registered.model.inputTokenLimit,
            maxOutputTokens: registered.model.outputTokenLimit,
            isAvailable: registered.model.isAvailable,
            displayName: registered.model.displayName
        )
    }

    // MARK: - Provider Access

    /// Get all providers that have models registered
    public var registeredProviders: [LLMProvider] {
        Array(knownProviders)
    }

    /// Get all registered models (unique, deduplicated)
    public var registeredModels: [LLMModelProtocol] {
        primaryIndex.values.map { $0.model }
    }

    /// Get provider models container for a specific provider
    public func providerModels(for provider: LLMProvider) -> (any LLMProviderModels)? {
        providerRegistry[provider]
    }

    /// Register a provider with all its models
    ///
    /// Note: Re-registering a provider will first remove all existing models
    /// from that provider before adding the new ones.
    public func registerProvider(_ providerModels: any LLMProviderModels) {
        let provider = providerModels.provider

        // Remove existing models from this provider first (handles re-registration)
        removeModelsForProvider(provider)

        providerRegistry[provider] = providerModels
        knownProviders.insert(provider)

        // Index all models from this provider
        for model in providerModels.allModels {
            let canonicalId = makeCanonicalId(name: model.name, provider: provider)
            let registered = RegisteredModel(model: model, provider: provider, canonicalId: canonicalId)

            // Primary index stores unique models by canonical ID
            primaryIndex[canonicalId] = registered

            // Lookup index allows finding by canonical ID
            lookupIndex[canonicalId] = canonicalId

            // Also index by bare model name for convenience lookup (if not taken)
            let bareName = extractBareName(from: model.name)
            if lookupIndex[bareName] == nil {
                lookupIndex[bareName] = canonicalId
            }

            // Index aliases
            for alias in model.aliases {
                lookupIndex[alias] = canonicalId
                aliasIndex[alias] = canonicalId
            }
        }
    }

    // MARK: - Model Lookup

    /// Find a model by name, optionally scoped to a specific provider
    public func model(named name: String, from provider: LLMProvider? = nil) -> LLMModelProtocol? {
        lookupRegisteredModel(named: name, from: provider)?.model
    }

    /// Get the canonical model ID for any name or alias
    ///
    /// This resolves bare names, aliases, and already-canonical IDs to
    /// the canonical form used in the registry.
    public func canonicalId(forNameOrAlias name: String) -> String? {
        lookupIndex[name]
    }

    /// Get the canonical model ID for an alias only (not bare names or canonical IDs)
    public func canonicalId(forAlias alias: String) -> String? {
        aliasIndex[alias]
    }

    /// Legacy compatibility - prefer recommendedModel or resolve()
    @available(*, deprecated, renamed: "resolve(category:capabilities:)")
    public func recommendedModel(
        for category: LLMUsageCategory,
        with capabilities: LLMCapabilities
    ) -> LLMModelProtocol? {
        resolve(category: category, capabilities: capabilities)
            .map { resolved in
                primaryIndex[resolved.canonicalId]?.model
            } ?? nil
    }

    // MARK: - Extended Query Methods

    /// Find models with specific capabilities
    public func models(with capabilities: LLMCapabilities) -> [LLMModelProtocol] {
        primaryIndex.values
            .filter { $0.model.hasAllCapabilities(capabilities) }
            .map { $0.model }
    }

    /// Find models with any of the specified capabilities
    public func models(withAny capabilities: LLMCapabilities) -> [LLMModelProtocol] {
        primaryIndex.values
            .filter { $0.model.hasAnyCapability(capabilities) }
            .map { $0.model }
    }

    /// Find models in a specific category
    public func models(for category: LLMUsageCategory) -> [LLMModelProtocol] {
        primaryIndex.values
            .filter { $0.model.category == category }
            .map { $0.model }
    }

    /// Find models of a specific tier or higher
    public func models(minimumTier tier: LLMPerformanceTier) -> [LLMModelProtocol] {
        primaryIndex.values
            .filter { registered in
                guard let modelTier = registered.model.tier else { return false }
                return modelTier >= tier
            }
            .map { $0.model }
    }

    /// Find models within a token limit
    ///
    /// - Parameters:
    ///   - tokens: Minimum context window size
    ///   - includeUnknown: If true, includes models with unknown context limits
    public func models(withMinimumContext tokens: Int, includeUnknown: Bool = false) -> [LLMModelProtocol] {
        primaryIndex.values
            .filter { registered in
                guard let limit = registered.model.inputTokenLimit else {
                    return includeUnknown
                }
                return limit >= tokens
            }
            .map { $0.model }
    }

    /// Check if a model ID is registered
    public func isModelRegistered(_ modelId: String) -> Bool {
        lookupIndex[modelId] != nil
    }

    // MARK: - Model Registration

    /// Register a single model directly
    public func register(
        model: LLMModelProtocol,
        provider: LLMProvider,
        canonicalId: String? = nil
    ) {
        let id = canonicalId ?? makeCanonicalId(name: model.name, provider: provider)
        let registered = RegisteredModel(model: model, provider: provider, canonicalId: id)

        // Track this provider
        knownProviders.insert(provider)

        // Primary index stores unique models
        primaryIndex[id] = registered

        // Lookup index allows finding by canonical ID
        lookupIndex[id] = id

        // Also index by bare name if not already taken
        let bareName = extractBareName(from: model.name)
        if lookupIndex[bareName] == nil {
            lookupIndex[bareName] = id
        }

        // Index aliases
        for alias in model.aliases {
            lookupIndex[alias] = id
            aliasIndex[alias] = id
        }
    }

    /// Register an alias for an existing model
    ///
    /// - Parameters:
    ///   - alias: The alias to register
    ///   - modelId: The canonical model ID to point to
    ///   - overwrite: If true, overwrites existing alias; if false, fails silently on collision
    public func registerAlias(_ alias: String, for modelId: String, overwrite: Bool = false) {
        guard primaryIndex[modelId] != nil else { return }
        guard overwrite || lookupIndex[alias] == nil else { return }
        lookupIndex[alias] = modelId
        aliasIndex[alias] = modelId
    }

    /// Remove a model from the registry
    public func unregister(modelId: String) {
        guard primaryIndex[modelId] != nil else { return }

        // Remove from primary index
        primaryIndex.removeValue(forKey: modelId)

        // Remove all lookup entries pointing to this model
        lookupIndex = lookupIndex.filter { $0.value != modelId }

        // Remove aliases pointing to this model
        aliasIndex = aliasIndex.filter { $0.value != modelId }
    }

    /// Clear all registered models and providers
    public func clear() {
        providerRegistry.removeAll()
        primaryIndex.removeAll()
        lookupIndex.removeAll()
        aliasIndex.removeAll()
        knownProviders.removeAll()
    }

    // MARK: - Batch Operations

    /// Register multiple models at once
    public func registerAll(models: [(model: LLMModelProtocol, provider: LLMProvider)]) {
        for (model, provider) in models {
            register(model: model, provider: provider)
        }
    }

    /// Get models from multiple providers
    public func models(from providers: [LLMProvider]) -> [LLMModelProtocol] {
        primaryIndex.values
            .filter { providers.contains($0.provider) }
            .map { $0.model }
    }

    // MARK: - Statistics

    /// Get registry statistics
    public var statistics: RegistryStatistics {
        let modelsByProvider = Dictionary(grouping: primaryIndex.values) { $0.provider }
        return RegistryStatistics(
            totalModels: primaryIndex.count,
            totalAliases: aliasIndex.count,
            totalProviders: knownProviders.count,
            modelsByProvider: modelsByProvider.mapValues { $0.count }
        )
    }

    // MARK: - Private Helpers

    private func lookupRegisteredModel(named name: String, from provider: LLMProvider?) -> RegisteredModel? {
        // If provider specified, look in that provider's namespace
        if let provider = provider {
            let canonicalId = makeCanonicalId(name: name, provider: provider)
            if let registered = primaryIndex[canonicalId] {
                return registered
            }
        }

        // Try lookup index (handles canonical IDs, bare names, and aliases)
        if let canonicalId = lookupIndex[name], let registered = primaryIndex[canonicalId] {
            return registered
        }

        return nil
    }

    /// Create a canonical ID from a model name and provider
    ///
    /// Handles the case where the name already contains a provider prefix.
    private func makeCanonicalId(name: String, provider: LLMProvider) -> String {
        // If name already contains a "/", treat it as canonical
        if name.contains("/") {
            return name.lowercased()
        }
        return "\(provider.rawValue.lowercased())/\(name)"
    }

    /// Extract the bare model name from a potentially-prefixed name
    private func extractBareName(from name: String) -> String {
        if let slashIndex = name.lastIndex(of: "/") {
            return String(name[name.index(after: slashIndex)...])
        }
        return name
    }

    /// Remove all models for a given provider
    private func removeModelsForProvider(_ provider: LLMProvider) {
        let toRemove = primaryIndex.filter { $0.value.provider == provider }.map { $0.key }
        for canonicalId in toRemove {
            primaryIndex.removeValue(forKey: canonicalId)
            lookupIndex = lookupIndex.filter { $0.value != canonicalId }
            aliasIndex = aliasIndex.filter { $0.value != canonicalId }
        }
    }
}

// MARK: - Supporting Types

/// Internal representation of a registered model
private struct RegisteredModel {
    let model: LLMModelProtocol
    let provider: LLMProvider
    let canonicalId: String
}

/// Statistics about the registry contents
public struct RegistryStatistics: Sendable {
    public let totalModels: Int
    public let totalAliases: Int
    public let totalProviders: Int
    public let modelsByProvider: [LLMProvider: Int]
}

// MARK: - Default Model Definitions

/// Common model definitions for built-in provider support
public enum DefaultModels {
    /// GPT-4 Turbo model definition
    public static let gpt4Turbo = LLMModelAdapter(
        name: "gpt-4-turbo",
        displayName: "GPT-4 Turbo",
        description: "OpenAI's GPT-4 Turbo with 128K context",
        provider: .openai,
        category: .chat,
        versionType: .stable,
        capabilities: [.text, .vision, .tools, .functionCalling, .jsonMode, .streaming],
        tier: .large,
        latency: .fast,
        inputTokenLimit: 128_000,
        outputTokenLimit: 4096,
        aliases: ["gpt-4-turbo-preview", "gpt-4-turbo-2024-04-09"],
        knowledgeCutoff: "2023-12"
    )

    /// GPT-4o model definition
    public static let gpt4o = LLMModelAdapter(
        name: "gpt-4o",
        displayName: "GPT-4o",
        description: "OpenAI's GPT-4o multimodal model",
        provider: .openai,
        category: .chat,
        versionType: .stable,
        capabilities: [.text, .vision, .audio, .tools, .functionCalling, .jsonMode, .streaming],
        tier: .flagship,
        latency: .fast,
        inputTokenLimit: 128_000,
        outputTokenLimit: 16384,
        aliases: ["gpt-4o-2024-08-06", "gpt-4o-2024-05-13"],
        knowledgeCutoff: "2023-10"
    )

    /// GPT-4o Mini model definition
    public static let gpt4oMini = LLMModelAdapter(
        name: "gpt-4o-mini",
        displayName: "GPT-4o Mini",
        description: "OpenAI's smaller, faster GPT-4o model",
        provider: .openai,
        category: .chat,
        versionType: .stable,
        capabilities: [.text, .vision, .tools, .functionCalling, .jsonMode, .streaming],
        tier: .small,
        latency: .veryFast,
        inputTokenLimit: 128_000,
        outputTokenLimit: 16384,
        aliases: ["gpt-4o-mini-2024-07-18"],
        knowledgeCutoff: "2023-10"
    )

    /// Claude 3.5 Sonnet model definition
    public static let claude35Sonnet = LLMModelAdapter(
        name: "claude-3-5-sonnet-latest",
        displayName: "Claude 3.5 Sonnet",
        description: "Anthropic's Claude 3.5 Sonnet - balanced performance",
        provider: .anthropic,
        category: .chat,
        versionType: .stable,
        capabilities: [.text, .vision, .tools, .functionCalling, .streaming, .computerUse],
        tier: .pro,
        latency: .fast,
        inputTokenLimit: 200_000,
        outputTokenLimit: 8192,
        aliases: ["claude-3-5-sonnet-20241022", "anthropic/claude-3.5-sonnet"],
        knowledgeCutoff: "2024-04"
    )

    /// Claude 3 Opus model definition
    public static let claude3Opus = LLMModelAdapter(
        name: "claude-3-opus-latest",
        displayName: "Claude 3 Opus",
        description: "Anthropic's Claude 3 Opus - highest capability",
        provider: .anthropic,
        category: .chat,
        versionType: .stable,
        capabilities: [.text, .vision, .tools, .functionCalling, .streaming],
        tier: .flagship,
        latency: .moderate,
        inputTokenLimit: 200_000,
        outputTokenLimit: 4096,
        aliases: ["claude-3-opus-20240229", "anthropic/claude-3-opus"],
        knowledgeCutoff: "2023-08"
    )

    /// Claude 3 Haiku model definition
    public static let claude3Haiku = LLMModelAdapter(
        name: "claude-3-haiku-20240307",
        displayName: "Claude 3 Haiku",
        description: "Anthropic's Claude 3 Haiku - fastest and most compact",
        provider: .anthropic,
        category: .chat,
        versionType: .stable,
        capabilities: [.text, .vision, .tools, .functionCalling, .streaming],
        tier: .small,
        latency: .ultraFast,
        inputTokenLimit: 200_000,
        outputTokenLimit: 4096,
        aliases: ["claude-3-haiku", "anthropic/claude-3-haiku"],
        knowledgeCutoff: "2023-08"
    )

    /// Gemini 1.5 Pro model definition
    public static let gemini15Pro = LLMModelAdapter(
        name: "gemini-1.5-pro",
        displayName: "Gemini 1.5 Pro",
        description: "Google's Gemini 1.5 Pro with 1M context",
        provider: .google,
        category: .chat,
        versionType: .stable,
        capabilities: [.text, .vision, .audio, .video, .tools, .functionCalling, .jsonMode, .streaming, .longContext],
        tier: .pro,
        latency: .fast,
        inputTokenLimit: 1_000_000,
        outputTokenLimit: 8192,
        aliases: ["gemini-1.5-pro-latest", "google/gemini-1.5-pro"],
        knowledgeCutoff: "2024-01"
    )

    /// Gemini 1.5 Flash model definition
    public static let gemini15Flash = LLMModelAdapter(
        name: "gemini-1.5-flash",
        displayName: "Gemini 1.5 Flash",
        description: "Google's Gemini 1.5 Flash - fast and efficient",
        provider: .google,
        category: .chat,
        versionType: .stable,
        capabilities: [.text, .vision, .audio, .video, .tools, .functionCalling, .jsonMode, .streaming, .longContext],
        tier: .medium,
        latency: .veryFast,
        inputTokenLimit: 1_000_000,
        outputTokenLimit: 8192,
        aliases: ["gemini-1.5-flash-latest", "google/gemini-1.5-flash"],
        knowledgeCutoff: "2024-01"
    )

    /// All default models
    public static let all: [LLMModelAdapter] = [
        gpt4Turbo,
        gpt4o,
        gpt4oMini,
        claude35Sonnet,
        claude3Opus,
        claude3Haiku,
        gemini15Pro,
        gemini15Flash
    ]
}

// MARK: - ModelRegistry Convenience Extensions

public extension ModelRegistry {
    /// Register all default models
    func registerDefaults() {
        for model in DefaultModels.all {
            register(model: model, provider: model.provider)
        }
    }
}
