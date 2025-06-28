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
        // Claude 4 Models
        LLMModelAdapter(name: "claude-opus-4-20250514", displayName: "Claude Opus 4", description: "Our most capable and intelligent model yet. Claude Opus 4 sets new standards in complex reasoning and advanced coding", provider: .anthropic, category: .chat, capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools], tier: .flagship, latency: .moderate, inputTokenLimit: 200_000, outputTokenLimit: 32_000, aliases: ["claude-opus-4-0"], knowledgeCutoff: "Mar 2025"),
        
        LLMModelAdapter(name: "claude-sonnet-4-20250514", displayName: "Claude Sonnet 4", description: "Our high-performance model with exceptional reasoning and efficiency", provider: .anthropic, category: .chat, capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools], tier: .pro, latency: .fast, inputTokenLimit: 200_000, outputTokenLimit: 64_000, aliases: ["claude-sonnet-4-0"], knowledgeCutoff: "Mar 2025"),
        
        // Claude 3.7 Models
        LLMModelAdapter(name: "claude-3-7-sonnet-20250219", displayName: "Claude 3.7 Sonnet", description: "High-performance model with early extended thinking", provider: .anthropic, category: .chat, capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools], tier: .pro, latency: .fast, inputTokenLimit: 200_000, outputTokenLimit: 64_000, aliases: ["claude-3-7-sonnet-latest"], knowledgeCutoff: "Nov 2024"),
        
        // Claude 3.5 Models
        LLMModelAdapter(name: "claude-3-5-sonnet-20241022", displayName: "Claude 3.5 Sonnet v2", description: "Our previous intelligent model (upgraded version)", provider: .anthropic, category: .chat, capabilities: [.text, .vision, .longContext, .multilingual, .tools], tier: .large, latency: .fast, inputTokenLimit: 200_000, outputTokenLimit: 8_192, aliases: ["claude-3-5-sonnet-latest"], knowledgeCutoff: "Apr 2024"),
        
        LLMModelAdapter(name: "claude-3-5-sonnet-20240620", displayName: "Claude 3.5 Sonnet", description: "Our previous intelligent model (previous version)", provider: .anthropic, category: .chat, capabilities: [.text, .vision, .longContext, .multilingual, .tools], tier: .large, latency: .fast, inputTokenLimit: 200_000, outputTokenLimit: 8_192, knowledgeCutoff: "Apr 2024"),
        
        LLMModelAdapter(name: "claude-3-5-haiku-20241022", displayName: "Claude 3.5 Haiku", description: "Our fastest model with intelligence at blazing speeds", provider: .anthropic, category: .chat, capabilities: [.text, .vision, .longContext, .multilingual, .tools], tier: .mini, latency: .ultraFast, inputTokenLimit: 200_000, outputTokenLimit: 8_192, aliases: ["claude-3-5-haiku-latest"], knowledgeCutoff: "July 2024"),
        
        // Claude 3 Models
        LLMModelAdapter(name: "claude-3-opus-20240229", displayName: "Claude 3 Opus", description: "Powerful model for complex tasks with top-level intelligence, fluency, and understanding", provider: .anthropic, category: .chat, capabilities: [.text, .vision, .longContext, .multilingual, .tools], tier: .ultra, latency: .moderate, inputTokenLimit: 200_000, outputTokenLimit: 4_096, aliases: ["claude-3-opus-latest"], knowledgeCutoff: "Aug 2023"),
        
        LLMModelAdapter(name: "claude-3-sonnet-20240229", displayName: "Claude 3 Sonnet", description: "Balanced model for a wide range of tasks", provider: .anthropic, category: .chat, capabilities: [.text, .vision, .longContext, .multilingual, .tools], tier: .large, latency: .fast, inputTokenLimit: 200_000, outputTokenLimit: 4_096, knowledgeCutoff: "Aug 2023"),
        
        LLMModelAdapter(name: "claude-3-haiku-20240307", displayName: "Claude 3 Haiku", description: "Fast and compact model for near-instant responsiveness with quick and accurate targeted performance", provider: .anthropic, category: .chat, capabilities: [.text, .vision, .longContext, .multilingual, .tools], tier: .small, latency: .fast, inputTokenLimit: 200_000, outputTokenLimit: 4_096, knowledgeCutoff: "Aug 2023")
    ]
}

// MARK: - Convenience Extensions
public extension AnthropicModels {
    // Most commonly used models for easy access
    static var opus4: LLMModelProtocol { AnthropicModels().model(named: "claude-opus-4-20250514")! }
    static var sonnet4: LLMModelProtocol { AnthropicModels().model(named: "claude-sonnet-4-20250514")! }
    static var sonnet37: LLMModelProtocol { AnthropicModels().model(named: "claude-3-7-sonnet-20250219")! }
    static var sonnet35Latest: LLMModelProtocol { AnthropicModels().model(named: "claude-3-5-sonnet-20241022")! }
    static var haiku35: LLMModelProtocol { AnthropicModels().model(named: "claude-3-5-haiku-20241022")! }
    static var opus3: LLMModelProtocol { AnthropicModels().model(named: "claude-3-opus-20240229")! }
    static var sonnet3: LLMModelProtocol { AnthropicModels().model(named: "claude-3-sonnet-20240229")! }
    static var haiku3: LLMModelProtocol { AnthropicModels().model(named: "claude-3-haiku-20240307")! }
    
    // Get models by generation
    var claude4Models: [LLMModelProtocol] { 
        allModels.filter { $0.name.contains("claude-opus-4") || $0.name.contains("claude-sonnet-4") }
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
    static var latestOpus: LLMModelProtocol { opus4 }
    static var latestSonnet: LLMModelProtocol { sonnet4 }
    static var latestHaiku: LLMModelProtocol { haiku35 }
} 