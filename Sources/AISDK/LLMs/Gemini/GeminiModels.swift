//
//  GeminiModels.swift
//  AISDK
//
//  Created by AI Assistant on 01/24/25.
//

import Foundation

// MARK: - Google Gemini Provider Models
public struct GeminiModels: LLMProviderModels {
    public let provider: LLMProvider = .google
    
    public let allModels: [LLMModelProtocol] = [
        // Gemini 2.5 Models
        LLMModelAdapter(name: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", description: "Our most powerful thinking model with maximum response accuracy and state-of-the-art performance", provider: .google, category: .chat, capabilities: [.text, .vision, .audio, .video, .pdf, .thinking, .tools, .codeExecution, .webSearch, .grounding, .structuredOutputs, .caching], tier: .flagship, latency: .moderate, inputTokenLimit: 1_048_576, outputTokenLimit: 65_536, knowledgeCutoff: "January 2025", specialization: "Advanced reasoning and multimodal"),
        
        LLMModelAdapter(name: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", description: "Our best model in terms of price-performance, offering well-rounded capabilities", provider: .google, category: .chat, capabilities: [.text, .vision, .audio, .video, .thinking, .tools, .codeExecution, .webSearch, .grounding, .structuredOutputs, .caching], tier: .large, latency: .fast, inputTokenLimit: 1_048_576, outputTokenLimit: 65_536, knowledgeCutoff: "January 2025"),
        
        LLMModelAdapter(name: "gemini-2.5-flash-lite-preview-06-17", displayName: "Gemini 2.5 Flash Lite", description: "A Gemini 2.5 Flash model optimized for cost efficiency and low latency", provider: .google, category: .chat, versionType: .preview, capabilities: [.text, .vision, .audio, .video, .thinking, .tools, .codeExecution, .webSearch, .grounding, .structuredOutputs, .caching], tier: .mini, latency: .veryFast, inputTokenLimit: 1_000_000, outputTokenLimit: 64_000, knowledgeCutoff: "January 2025", specialization: "Cost efficiency and high throughput"),
        
        LLMModelAdapter(name: "gemini-2.5-flash-preview-native-audio-dialog", displayName: "Gemini 2.5 Flash Native Audio", description: "Native audio dialog model for interactive conversational experiences", provider: .google, category: .multimodal, versionType: .preview, capabilities: [.text, .audio, .video, .audioGeneration, .tools, .webSearch, .thinking], tier: .large, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 8_000, knowledgeCutoff: "January 2025", specialization: "Native audio dialog"),
        
        LLMModelAdapter(name: "gemini-2.5-flash-exp-native-audio-thinking-dialog", displayName: "Gemini 2.5 Flash Experimental Audio", description: "Experimental native audio dialog model with thinking capabilities", provider: .google, category: .multimodal, versionType: .experimental, capabilities: [.text, .audio, .video, .audioGeneration, .tools, .webSearch, .thinking], tier: .large, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 8_000, knowledgeCutoff: "January 2025", specialization: "Native audio dialog with thinking"),
        
        LLMModelAdapter(name: "gemini-2.5-flash-preview-tts", displayName: "Gemini 2.5 Flash TTS", description: "Price-performant text-to-speech model for structured workflows", provider: .google, category: .audioGeneration, versionType: .preview, capabilities: [.text, .textToSpeech], tier: .medium, latency: .fast, inputTokenLimit: 8_000, outputTokenLimit: 16_000, specialization: "Text-to-speech"),
        
        LLMModelAdapter(name: "gemini-2.5-pro-preview-tts", displayName: "Gemini 2.5 Pro TTS", description: "Most powerful text-to-speech model for high-quality audio generation", provider: .google, category: .audioGeneration, versionType: .preview, capabilities: [.text, .textToSpeech], tier: .pro, latency: .moderate, inputTokenLimit: 8_000, outputTokenLimit: 16_000, specialization: "Text-to-speech"),
        
        LLMModelAdapter(name: "gemini-live-2.5-flash-preview", displayName: "Gemini Live 2.5 Flash", description: "Low-latency bidirectional voice and video interactions", provider: .google, category: .realtime, versionType: .preview, capabilities: [.text, .audio, .video, .audioGeneration, .tools, .codeExecution, .webSearch, .structuredOutputs, .liveAPI, .thinking], tier: .large, latency: .fast, inputTokenLimit: 1_048_576, outputTokenLimit: 8_192, knowledgeCutoff: "January 2025", specialization: "Live API"),
        
        // Gemini 2.0 Models
        LLMModelAdapter(name: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash", description: "Next generation features, speed, and realtime streaming", provider: .google, category: .chat, versionType: .latest, capabilities: [.text, .vision, .audio, .video, .tools, .codeExecution, .webSearch, .grounding, .structuredOutputs, .caching, .liveAPI], tier: .large, latency: .fast, inputTokenLimit: 1_048_576, outputTokenLimit: 8_192, knowledgeCutoff: "August 2024"),
        
        LLMModelAdapter(name: "gemini-2.0-flash-001", displayName: "Gemini 2.0 Flash (001)", description: "Stable version of Gemini 2.0 Flash", provider: .google, category: .chat, capabilities: [.text, .vision, .audio, .video, .tools, .codeExecution, .webSearch, .grounding, .structuredOutputs, .caching, .liveAPI], tier: .large, latency: .fast, inputTokenLimit: 1_048_576, outputTokenLimit: 8_192, knowledgeCutoff: "August 2024"),
        
        LLMModelAdapter(name: "gemini-2.0-flash-exp", displayName: "Gemini 2.0 Flash Experimental", description: "Experimental version of Gemini 2.0 Flash", provider: .google, category: .chat, versionType: .experimental, capabilities: [.text, .vision, .audio, .video, .tools, .codeExecution, .webSearch, .grounding, .structuredOutputs, .caching, .thinking], tier: .large, latency: .fast, inputTokenLimit: 1_048_576, outputTokenLimit: 8_192, knowledgeCutoff: "August 2024"),
        
        LLMModelAdapter(name: "gemini-2.0-flash-preview-image-generation", displayName: "Gemini 2.0 Flash Image Gen", description: "Conversational image generation and editing", provider: .google, category: .imageGeneration, versionType: .preview, capabilities: [.text, .vision, .audio, .video, .imageGeneration, .structuredOutputs, .caching], tier: .large, latency: .fast, inputTokenLimit: 32_000, outputTokenLimit: 8_192, knowledgeCutoff: "August 2024", specialization: "Image generation"),
        
        LLMModelAdapter(name: "gemini-2.0-flash-lite", displayName: "Gemini 2.0 Flash Lite", description: "Cost efficiency and low latency", provider: .google, category: .chat, versionType: .latest, capabilities: [.text, .vision, .audio, .video, .tools, .structuredOutputs, .caching], tier: .mini, latency: .veryFast, inputTokenLimit: 1_048_576, outputTokenLimit: 8_192, knowledgeCutoff: "August 2024"),
        
        LLMModelAdapter(name: "gemini-2.0-flash-lite-001", displayName: "Gemini 2.0 Flash Lite (001)", description: "Stable cost-efficient model", provider: .google, category: .chat, capabilities: [.text, .vision, .audio, .video, .tools, .structuredOutputs, .caching], tier: .mini, latency: .veryFast, inputTokenLimit: 1_048_576, outputTokenLimit: 8_192, knowledgeCutoff: "August 2024"),
        
        LLMModelAdapter(name: "gemini-2.0-flash-live-001", displayName: "Gemini 2.0 Flash Live", description: "Low-latency bidirectional voice and video interactions", provider: .google, category: .realtime, versionType: .preview, capabilities: [.text, .audio, .video, .audioGeneration, .tools, .codeExecution, .webSearch, .grounding, .structuredOutputs, .liveAPI], tier: .large, latency: .fast, inputTokenLimit: 1_048_576, outputTokenLimit: 8_192, knowledgeCutoff: "August 2024", specialization: "Live API"),
        
        // Gemini 1.5 Models
        LLMModelAdapter(name: "gemini-1.5-flash", displayName: "Gemini 1.5 Flash", description: "Fast and versatile performance across a diverse variety of tasks", provider: .google, category: .chat, capabilities: [.text, .vision, .audio, .video, .tools, .codeExecution, .structuredOutputs, .caching, .tuning], tier: .medium, latency: .fast, inputTokenLimit: 1_048_576, outputTokenLimit: 8_192),
        
        LLMModelAdapter(name: "gemini-1.5-flash-8b", displayName: "Gemini 1.5 Flash 8B", description: "High volume and lower intelligence tasks", provider: .google, category: .chat, capabilities: [.text, .vision, .audio, .video, .tools, .codeExecution, .structuredOutputs, .caching, .tuning], tier: .small, latency: .veryFast, inputTokenLimit: 1_048_576, outputTokenLimit: 8_192),
        
        LLMModelAdapter(name: "gemini-1.5-pro", displayName: "Gemini 1.5 Pro", description: "Complex reasoning tasks requiring more intelligence", provider: .google, category: .chat, capabilities: [.text, .vision, .audio, .video, .tools, .codeExecution, .structuredOutputs, .caching], tier: .large, latency: .moderate, inputTokenLimit: 2_097_152, outputTokenLimit: 8_192),
        
        // Imagen Models
        LLMModelAdapter(name: "imagen-4.0-generate-preview-06-06", displayName: "Imagen 4.0", description: "Our most up-to-date image generation model with highly detailed images", provider: .google, category: .imageGeneration, versionType: .preview, capabilities: [.text, .imageGeneration], tier: .flagship, latency: .moderate, inputTokenLimit: 480, outputTokenLimit: 0, specialization: "Standard image generation"),
        
        LLMModelAdapter(name: "imagen-4.0-ultra-generate-preview-06-06", displayName: "Imagen 4.0 Ultra", description: "Ultra-quality image generation with highest detail", provider: .google, category: .imageGeneration, versionType: .preview, capabilities: [.text, .imageGeneration], tier: .ultra, latency: .slow, inputTokenLimit: 480, outputTokenLimit: 0, specialization: "Ultra-quality image generation"),
        
        LLMModelAdapter(name: "imagen-3.0-generate-002", displayName: "Imagen 3.0", description: "High quality image generation model", provider: .google, category: .imageGeneration, capabilities: [.text, .imageGeneration], tier: .large, latency: .moderate, inputTokenLimit: 0, outputTokenLimit: 0, specialization: "High-quality image generation"),
        
        // Veo Models
        LLMModelAdapter(name: "veo-2.0-generate-001", displayName: "Veo 2.0", description: "High quality text- and image-to-video model", provider: .google, category: .videoGeneration, capabilities: [.text, .vision, .videoGeneration], tier: .flagship, latency: .slow, inputTokenLimit: 0, outputTokenLimit: 0, specialization: "Video generation"),
        
        // Embedding Models
        LLMModelAdapter(name: "gemini-embedding-exp-03-07", displayName: "Gemini Embedding Experimental", description: "State-of-the-art performance across code, multi-lingual, and retrieval", provider: .google, category: .embedding, versionType: .experimental, capabilities: [.text, .embedding], tier: .large, latency: .fast, inputTokenLimit: 8_192, outputTokenLimit: 0, specialization: "Elastic dimensions: 3072, 1536, or 768"),
        
        LLMModelAdapter(name: "text-embedding-004", displayName: "Text Embedding 004", description: "Stronger retrieval performance with 768 dimensions", provider: .google, category: .embedding, capabilities: [.text, .embedding], tier: .medium, latency: .fast, inputTokenLimit: 2_048, outputTokenLimit: 0, specialization: "768 dimension embeddings"),
        
        LLMModelAdapter(name: "embedding-001", displayName: "Text Embedding 001", description: "Optimized for creating embeddings with 768 dimensions", provider: .google, category: .embedding, capabilities: [.text, .embedding], tier: .small, latency: .fast, inputTokenLimit: 2_048, outputTokenLimit: 0, specialization: "768 dimension embeddings"),
        
        // AQA Model
        LLMModelAdapter(name: "aqa", displayName: "AQA", description: "Attributed Question-Answering over documents with grounded responses", provider: .google, category: .analysis, capabilities: [.text], tier: .medium, latency: .fast, inputTokenLimit: 7_168, outputTokenLimit: 1_024, specialization: "Attributed question-answering")
    ]
}

// MARK: - Convenience Extensions
public extension GeminiModels {
    // Most commonly used models for easy access
    static var gemini25Pro: LLMModelProtocol { GeminiModels().model(named: "gemini-2.5-pro")! }
    static var gemini25Flash: LLMModelProtocol { GeminiModels().model(named: "gemini-2.5-flash")! }
    static var gemini25FlashLite: LLMModelProtocol { GeminiModels().model(named: "gemini-2.5-flash-lite-preview-06-17")! }
    static var gemini20Flash: LLMModelProtocol { GeminiModels().model(named: "gemini-2.0-flash")! }
    static var gemini20FlashLite: LLMModelProtocol { GeminiModels().model(named: "gemini-2.0-flash-lite")! }
    static var gemini15Flash: LLMModelProtocol { GeminiModels().model(named: "gemini-1.5-flash")! }
    static var gemini15Flash8B: LLMModelProtocol { GeminiModels().model(named: "gemini-1.5-flash-8b")! }
    static var gemini15Pro: LLMModelProtocol { GeminiModels().model(named: "gemini-1.5-pro")! }
    static var imagen4: LLMModelProtocol { GeminiModels().model(named: "imagen-4.0-generate-preview-06-06")! }
    static var imagen3: LLMModelProtocol { GeminiModels().model(named: "imagen-3.0-generate-002")! }
    static var veo2: LLMModelProtocol { GeminiModels().model(named: "veo-2.0-generate-001")! }
    static var textEmbedding: LLMModelProtocol { GeminiModels().model(named: "text-embedding-004")! }
    
    // Get models by generation
    var gemini25Models: [LLMModelProtocol] {
        allModels.filter { $0.name.contains("gemini-2.5") || $0.name.contains("gemini-live-2.5") }
    }
    var gemini20Models: [LLMModelProtocol] {
        allModels.filter { $0.name.contains("gemini-2.0") }
    }
    var gemini15Models: [LLMModelProtocol] {
        allModels.filter { $0.name.contains("gemini-1.5") }
    }
    var imagenModels: [LLMModelProtocol] {
        allModels.filter { $0.name.contains("imagen") }
    }
    var veoModels: [LLMModelProtocol] {
        allModels.filter { $0.name.contains("veo") }
    }
    
    // Get models by capability
    var thinkingCapableModels: [LLMModelProtocol] { models(with: .thinking) }
    var multimodalModels: [LLMModelProtocol] { models(with: [.text, .vision]) }
    var audioCapableModels: [LLMModelProtocol] { models(with: .audio) }
    var liveAPIModels: [LLMModelProtocol] { models(with: .liveAPI) }
    var imageGenerationModels: [LLMModelProtocol] { models(with: .imageGeneration) }
    var videoGenerationModels: [LLMModelProtocol] { models(with: .videoGeneration) }
    var embeddingModels: [LLMModelProtocol] { models(with: .embedding) }
    
    // Latest models
    static var latestPro: LLMModelProtocol { gemini25Pro }
    static var latestFlash: LLMModelProtocol { gemini25Flash }
    static var latestImageGen: LLMModelProtocol { imagen4 }
    static var latestVideoGen: LLMModelProtocol { veo2 }
} 