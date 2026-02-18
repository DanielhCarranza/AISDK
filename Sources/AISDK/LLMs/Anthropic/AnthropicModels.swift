//
//  AnthropicModels.swift
//  AISDK
//
//  Created by AI Assistant on 01/24/25.
//

import Foundation

// MARK: - Anthropic Provider Models
public struct AnthropicModels: LLMProviderModels {
    public let provider: LLMProvider = .anthropic

    public let allModels: [LLMModelProtocol] = [
        // Claude 4.5 Models
        LLMModelAdapter(
            name: "claude-opus-4-5-20251101",
            displayName: "Claude Opus 4.5",
            description: "Most intelligent model, preserves thinking history across turns",
            provider: .anthropic,
            category: .chat,
            capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools],
            tier: .flagship,
            latency: .moderate,
            inputTokenLimit: 200_000,
            outputTokenLimit: 64_000,
            aliases: ["claude-opus-4-5-latest", "claude-opus-4-5"],
            knowledgeCutoff: "Apr 2025"
        ),
        LLMModelAdapter(
            name: "claude-sonnet-4-5-20250929",
            displayName: "Claude Sonnet 4.5",
            description: "Best for real-world agents and coding, 1M context beta available",
            provider: .anthropic,
            category: .chat,
            capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools],
            tier: .pro,
            latency: .fast,
            inputTokenLimit: 200_000,
            outputTokenLimit: 64_000,
            aliases: ["claude-sonnet-4-5-latest", "claude-sonnet-4-5"],
            knowledgeCutoff: "Apr 2025"
        ),
        LLMModelAdapter(
            name: "claude-haiku-4-5-20251001",
            displayName: "Claude Haiku 4.5",
            description: "Hybrid model: instant responses with extended thinking capability",
            provider: .anthropic,
            category: .chat,
            capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools],
            tier: .mini,
            latency: .ultraFast,
            inputTokenLimit: 200_000,
            outputTokenLimit: 64_000,
            aliases: ["claude-haiku-4-5-latest", "claude-haiku-4-5"],
            knowledgeCutoff: "Apr 2025"
        ),

        // Claude 4.1 Models
        LLMModelAdapter(
            name: "claude-opus-4-1-20250805",
            displayName: "Claude Opus 4.1",
            description: "Most intelligent model with refined reasoning",
            provider: .anthropic,
            category: .chat,
            capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools],
            tier: .flagship,
            latency: .moderate,
            inputTokenLimit: 200_000,
            outputTokenLimit: 64_000,
            aliases: ["claude-opus-4-1-latest", "claude-opus-4-1"],
            knowledgeCutoff: "Apr 2025"
        ),

        // Claude 4 Models
        LLMModelAdapter(
            name: "claude-opus-4-20250514",
            displayName: "Claude Opus 4",
            description: "Most capable model for complex reasoning and advanced coding",
            provider: .anthropic,
            category: .chat,
            capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools],
            tier: .flagship,
            latency: .moderate,
            inputTokenLimit: 200_000,
            outputTokenLimit: 64_000,
            aliases: ["claude-opus-4-0"],
            knowledgeCutoff: "Mar 2025"
        ),
        LLMModelAdapter(
            name: "claude-sonnet-4-20250514",
            displayName: "Claude Sonnet 4",
            description: "High-performance model with exceptional reasoning and efficiency",
            provider: .anthropic,
            category: .chat,
            capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools],
            tier: .pro,
            latency: .fast,
            inputTokenLimit: 200_000,
            outputTokenLimit: 64_000,
            aliases: ["claude-sonnet-4-0"],
            knowledgeCutoff: "Mar 2025"
        ),

        // Claude 3.7 Models (Deprecated)
        LLMModelAdapter(
            name: "claude-3-7-sonnet-20250219",
            displayName: "Claude 3.7 Sonnet",
            description: "High-performance model with early extended thinking",
            provider: .anthropic,
            category: .chat,
            versionType: .deprecated,
            capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools, .deprecated],
            tier: .pro,
            latency: .fast,
            inputTokenLimit: 200_000,
            outputTokenLimit: 64_000,
            aliases: ["claude-3-7-sonnet-latest"],
            knowledgeCutoff: "Nov 2024",
            metadata: ["deprecationMessage": "Use claude-sonnet-4-5-20250929 instead"]
        ),

        // Claude 3.5 Models
        LLMModelAdapter(
            name: "claude-3-5-sonnet-20241022",
            displayName: "Claude 3.5 Sonnet v2",
            description: "Previous intelligent model (upgraded version)",
            provider: .anthropic,
            category: .chat,
            versionType: .deprecated,
            capabilities: [.text, .vision, .longContext, .multilingual, .tools, .deprecated],
            tier: .large,
            latency: .fast,
            inputTokenLimit: 200_000,
            outputTokenLimit: 8_192,
            aliases: ["claude-3-5-sonnet-latest"],
            knowledgeCutoff: "Apr 2024",
            metadata: ["deprecationMessage": "Use claude-sonnet-4-5-20250929 instead"]
        ),
        LLMModelAdapter(
            name: "claude-3-5-sonnet-20240620",
            displayName: "Claude 3.5 Sonnet",
            description: "Previous intelligent model (earlier version)",
            provider: .anthropic,
            category: .chat,
            capabilities: [.text, .vision, .longContext, .multilingual, .tools],
            tier: .large,
            latency: .fast,
            inputTokenLimit: 200_000,
            outputTokenLimit: 8_192,
            knowledgeCutoff: "Apr 2024"
        ),
        LLMModelAdapter(
            name: "claude-3-5-haiku-20241022",
            displayName: "Claude 3.5 Haiku",
            description: "Fastest model with intelligence at blazing speeds",
            provider: .anthropic,
            category: .chat,
            capabilities: [.text, .vision, .longContext, .multilingual, .tools],
            tier: .mini,
            latency: .ultraFast,
            inputTokenLimit: 200_000,
            outputTokenLimit: 8_192,
            aliases: ["claude-3-5-haiku-latest"],
            knowledgeCutoff: "July 2024"
        ),

        // Claude 3 Models (Deprecated)
        LLMModelAdapter(
            name: "claude-3-opus-20240229",
            displayName: "Claude 3 Opus",
            description: "Powerful model for complex tasks with top-level intelligence",
            provider: .anthropic,
            category: .chat,
            versionType: .deprecated,
            capabilities: [.text, .vision, .longContext, .multilingual, .tools, .deprecated],
            tier: .ultra,
            latency: .moderate,
            inputTokenLimit: 200_000,
            outputTokenLimit: 4_096,
            aliases: ["claude-3-opus-latest"],
            knowledgeCutoff: "Aug 2023",
            metadata: ["deprecationMessage": "Use claude-opus-4-5-20251101 instead"]
        ),
        LLMModelAdapter(
            name: "claude-3-sonnet-20240229",
            displayName: "Claude 3 Sonnet",
            description: "Balanced model for a wide range of tasks",
            provider: .anthropic,
            category: .chat,
            capabilities: [.text, .vision, .longContext, .multilingual, .tools],
            tier: .large,
            latency: .fast,
            inputTokenLimit: 200_000,
            outputTokenLimit: 4_096,
            knowledgeCutoff: "Aug 2023"
        ),
        LLMModelAdapter(
            name: "claude-3-haiku-20240307",
            displayName: "Claude 3 Haiku",
            description: "Fast and compact model for near-instant responsiveness",
            provider: .anthropic,
            category: .chat,
            versionType: .deprecated,
            capabilities: [.text, .vision, .longContext, .multilingual, .tools, .deprecated],
            tier: .small,
            latency: .fast,
            inputTokenLimit: 200_000,
            outputTokenLimit: 4_096,
            knowledgeCutoff: "Aug 2023",
            metadata: ["deprecationMessage": "Use claude-haiku-4-5-20251001 instead"]
        )
    ]
}

// MARK: - Convenience Extensions
public extension AnthropicModels {
    // MARK: - Find Helpers

    static func findModel(_ nameOrAlias: String) -> LLMModelProtocol? {
        let models = AnthropicModels()
        return models.model(named: nameOrAlias) ?? models.model(withAlias: nameOrAlias)
    }

    // Most commonly used models for easy access
    static var opus45: LLMModelProtocol { AnthropicModels.findModel("claude-opus-4-5-20251101")! }
    static var sonnet45: LLMModelProtocol { AnthropicModels.findModel("claude-sonnet-4-5-20250929")! }
    static var haiku45: LLMModelProtocol { AnthropicModels.findModel("claude-haiku-4-5-20251001")! }
    static var opus41: LLMModelProtocol { AnthropicModels.findModel("claude-opus-4-1-20250805")! }
    static var opus4: LLMModelProtocol { AnthropicModels.findModel("claude-opus-4-20250514")! }
    static var sonnet4: LLMModelProtocol { AnthropicModels.findModel("claude-sonnet-4-20250514")! }
    static var sonnet37: LLMModelProtocol { AnthropicModels.findModel("claude-3-7-sonnet-20250219")! }
    static var sonnet35Latest: LLMModelProtocol { AnthropicModels.findModel("claude-3-5-sonnet-20241022")! }
    static var haiku35: LLMModelProtocol { AnthropicModels.findModel("claude-3-5-haiku-20241022")! }
    static var opus3: LLMModelProtocol { AnthropicModels.findModel("claude-3-opus-20240229")! }
    static var sonnet3: LLMModelProtocol { AnthropicModels.findModel("claude-3-sonnet-20240229")! }
    static var haiku3: LLMModelProtocol { AnthropicModels.findModel("claude-3-haiku-20240307")! }

    // Get models by generation
    var claude4Models: [LLMModelProtocol] {
        allModels.filter { $0.name.contains("claude-opus-4") || $0.name.contains("claude-sonnet-4") || $0.name.contains("claude-haiku-4") }
    }
    var claude37Models: [LLMModelProtocol] {
        allModels.filter { $0.name.contains("claude-3-7") }
    }
    var claude35Models: [LLMModelProtocol] {
        allModels.filter { $0.name.contains("claude-3-5") }
    }
    var claude3Models: [LLMModelProtocol] {
        allModels.filter { $0.name.contains("claude-3-opus") || $0.name.contains("claude-3-sonnet") || $0.name.contains("claude-3-haiku") }
    }

    // Get models by capability
    var thinkingCapableModels: [LLMModelProtocol] { models(with: .thinking) }
    var flagshipModels: [LLMModelProtocol] { models(ofTier: .flagship) }
    var fastestModels: [LLMModelProtocol] { models(ofTier: .mini) }
    var mostCapableModels: [LLMModelProtocol] { models(ofTier: .ultra) }

    // Latest model aliases
    static var latestOpus: LLMModelProtocol { opus45 }
    static var latestSonnet: LLMModelProtocol { sonnet45 }
    static var latestHaiku: LLMModelProtocol { haiku45 }
}
