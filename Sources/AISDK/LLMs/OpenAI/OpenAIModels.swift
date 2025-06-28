//
//  OpenAIModels.swift
//  AISDK
//
//  Created by AI Assistant on 01/24/25.
//

import Foundation

// MARK: - OpenAI Provider Models
public struct OpenAIModels: LLMProviderModels {
    public let provider: LLMProvider = .openai
    
    public let allModels: [LLMModelProtocol] = [
        // Reasoning Models
        LLMModelAdapter(name: "o4-mini", description: "Faster, more affordable reasoning model", provider: .openai, category: .reasoning, capabilities: [.text, .reasoning, .tools], tier: .mini, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 65_536),
        LLMModelAdapter(name: "o3", description: "Our most powerful reasoning model", provider: .openai, category: .reasoning, capabilities: [.text, .reasoning, .tools], tier: .flagship, latency: .moderate, inputTokenLimit: 200_000, outputTokenLimit: 100_000),
        LLMModelAdapter(name: "o3-pro", description: "Version of o3 with more compute for better responses", provider: .openai, category: .reasoning, capabilities: [.text, .reasoning, .tools], tier: .pro, latency: .moderate, inputTokenLimit: 200_000, outputTokenLimit: 100_000),
        LLMModelAdapter(name: "o3-mini", description: "A small model alternative to o3", provider: .openai, category: .reasoning, capabilities: [.text, .reasoning, .tools], tier: .mini, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 65_536),
        LLMModelAdapter(name: "o1", description: "Previous full o-series reasoning model", provider: .openai, category: .reasoning, capabilities: [.text, .reasoning, .tools], tier: .large, latency: .moderate, inputTokenLimit: 200_000, outputTokenLimit: 100_000),
        LLMModelAdapter(name: "o1-mini", description: "A small model alternative to o1", provider: .openai, category: .reasoning, versionType: .deprecated, capabilities: [.text, .reasoning, .tools, .deprecated], tier: .mini, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 65_536),
        LLMModelAdapter(name: "o1-pro", description: "Version of o1 with more compute for better responses", provider: .openai, category: .reasoning, capabilities: [.text, .reasoning, .tools], tier: .pro, latency: .moderate, inputTokenLimit: 200_000, outputTokenLimit: 100_000),
        
        // Flagship Chat Models
        LLMModelAdapter(name: "gpt-4.1", description: "Flagship GPT model for complex tasks", provider: .openai, category: .chat, capabilities: [.text, .vision, .tools], tier: .flagship, latency: .moderate, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        LLMModelAdapter(name: "gpt-4o", description: "Fast, intelligent, flexible GPT model", provider: .openai, category: .chat, capabilities: [.text, .vision, .tools], tier: .large, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        LLMModelAdapter(name: "gpt-4o-audio-preview", description: "GPT-4o models capable of audio inputs and outputs", provider: .openai, category: .multimodal, versionType: .preview, capabilities: [.text, .vision, .audio, .tools], tier: .large, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        LLMModelAdapter(name: "chatgpt-4o-latest", description: "GPT-4o model used in ChatGPT", provider: .openai, category: .chat, versionType: .latest, capabilities: [.text, .vision, .tools], tier: .large, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        
        // Cost-Optimized Models
        LLMModelAdapter(name: "gpt-4.1-mini", description: "Balanced for intelligence, speed, and cost", provider: .openai, category: .chat, capabilities: [.text, .vision, .tools], tier: .mini, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        LLMModelAdapter(name: "gpt-4.1-nano", description: "Fastest, most cost-effective GPT-4.1 model", provider: .openai, category: .chat, capabilities: [.text, .tools], tier: .nano, latency: .ultraFast, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        LLMModelAdapter(name: "gpt-4o-mini", description: "Fast, affordable small model for focused tasks", provider: .openai, category: .chat, capabilities: [.text, .vision, .tools], tier: .mini, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        LLMModelAdapter(name: "gpt-4o-mini-audio-preview", description: "Smaller model capable of audio inputs and outputs", provider: .openai, category: .multimodal, versionType: .preview, capabilities: [.text, .vision, .audio, .tools], tier: .mini, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        
        // Deep Research Models
        LLMModelAdapter(name: "o3-deep-research", description: "Our most powerful deep research model", provider: .openai, category: .research, capabilities: [.text, .reasoning, .tools], tier: .flagship, latency: .slow, inputTokenLimit: 1_000_000, outputTokenLimit: 100_000),
        LLMModelAdapter(name: "o4-mini-deep-research", description: "Faster, more affordable deep research model", provider: .openai, category: .research, capabilities: [.text, .reasoning, .tools], tier: .mini, latency: .moderate, inputTokenLimit: 200_000, outputTokenLimit: 65_536),
        
        // Realtime Models
        LLMModelAdapter(name: "gpt-4o-realtime-preview", description: "Model capable of realtime text and audio inputs and outputs", provider: .openai, category: .realtime, versionType: .preview, capabilities: [.text, .audio, .realtime, .tools], tier: .large, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 4_096),
        LLMModelAdapter(name: "gpt-4o-mini-realtime-preview", description: "Smaller realtime model for text and audio inputs and outputs", provider: .openai, category: .realtime, versionType: .preview, capabilities: [.text, .audio, .realtime, .tools], tier: .mini, latency: .veryFast, inputTokenLimit: 128_000, outputTokenLimit: 4_096),
        
        // Image Generation Models
        LLMModelAdapter(name: "gpt-image-1", description: "State-of-the-art image generation model", provider: .openai, category: .imageGeneration, capabilities: [.imageGeneration, .tools], tier: .flagship, latency: .moderate, inputTokenLimit: 4_000, outputTokenLimit: 0),
        LLMModelAdapter(name: "dall-e-3", description: "Previous generation image generation model", provider: .openai, category: .imageGeneration, capabilities: [.imageGeneration], tier: .large, latency: .moderate, inputTokenLimit: 4_000, outputTokenLimit: 0),
        LLMModelAdapter(name: "dall-e-2", description: "Our first image generation model", provider: .openai, category: .imageGeneration, capabilities: [.imageGeneration], tier: .medium, latency: .fast, inputTokenLimit: 1_000, outputTokenLimit: 0),
        
        // Text-to-Speech Models
        LLMModelAdapter(name: "gpt-4o-mini-tts", description: "Text-to-speech model powered by GPT-4o mini", provider: .openai, category: .audioGeneration, capabilities: [.text, .textToSpeech], tier: .mini, latency: .fast, inputTokenLimit: 4_096, outputTokenLimit: 0),
        LLMModelAdapter(name: "tts-1", description: "Text-to-speech model optimized for speed", provider: .openai, category: .audioGeneration, capabilities: [.text, .textToSpeech], tier: .small, latency: .veryFast, inputTokenLimit: 4_096, outputTokenLimit: 0),
        LLMModelAdapter(name: "tts-1-hd", description: "Text-to-speech model optimized for quality", provider: .openai, category: .audioGeneration, capabilities: [.text, .textToSpeech], tier: .medium, latency: .fast, inputTokenLimit: 4_096, outputTokenLimit: 0),
        
        // Transcription Models
        LLMModelAdapter(name: "gpt-4o-transcribe", description: "Speech-to-text model powered by GPT-4o", provider: .openai, category: .transcription, capabilities: [.speechToText, .audio], tier: .large, latency: .fast, inputTokenLimit: 0, outputTokenLimit: 1_000_000),
        LLMModelAdapter(name: "gpt-4o-mini-transcribe", description: "Speech-to-text model powered by GPT-4o mini", provider: .openai, category: .transcription, capabilities: [.speechToText, .audio], tier: .mini, latency: .veryFast, inputTokenLimit: 0, outputTokenLimit: 1_000_000),
        LLMModelAdapter(name: "whisper-1", description: "General-purpose speech recognition model", provider: .openai, category: .transcription, capabilities: [.speechToText, .audio], tier: .medium, latency: .fast, inputTokenLimit: 0, outputTokenLimit: 1_000_000),
        
        // Tool-Specific Models
        LLMModelAdapter(name: "gpt-4o-search-preview", description: "GPT model for web search in Chat Completions", provider: .openai, category: .chat, versionType: .preview, capabilities: [.text, .vision, .tools, .search], tier: .large, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        LLMModelAdapter(name: "gpt-4o-mini-search-preview", description: "Fast, affordable small model for web search", provider: .openai, category: .chat, versionType: .preview, capabilities: [.text, .tools, .search], tier: .mini, latency: .veryFast, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        LLMModelAdapter(name: "computer-use-preview", description: "Specialized model for computer use tool", provider: .openai, category: .agents, versionType: .preview, capabilities: [.text, .tools, .computerUse], tier: .large, latency: .moderate, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        LLMModelAdapter(name: "codex-mini-latest", description: "Fast reasoning model optimized for the Codex CLI", provider: .openai, category: .coding, versionType: .latest, capabilities: [.text, .reasoning, .tools], tier: .mini, latency: .fast, inputTokenLimit: 128_000, outputTokenLimit: 16_384),
        
        // Embedding Models
        LLMModelAdapter(name: "text-embedding-3-small", description: "Small embedding model", provider: .openai, category: .embedding, capabilities: [.text, .embedding], tier: .small, latency: .veryFast, inputTokenLimit: 8_191, outputTokenLimit: 0),
        LLMModelAdapter(name: "text-embedding-3-large", description: "Most capable embedding model", provider: .openai, category: .embedding, capabilities: [.text, .embedding], tier: .large, latency: .fast, inputTokenLimit: 8_191, outputTokenLimit: 0),
        LLMModelAdapter(name: "text-embedding-ada-002", description: "Older embedding model", provider: .openai, category: .embedding, capabilities: [.text, .embedding], tier: .medium, latency: .fast, inputTokenLimit: 8_191, outputTokenLimit: 0),
        
        // Moderation Models
        LLMModelAdapter(name: "omni-moderation-latest", description: "Identify potentially harmful content in text and images", provider: .openai, category: .moderation, versionType: .latest, capabilities: [.text, .vision, .moderation], tier: .medium, latency: .veryFast, inputTokenLimit: 32_768, outputTokenLimit: 0),
        LLMModelAdapter(name: "text-moderation-latest", description: "Previous generation text-only moderation model", provider: .openai, category: .moderation, versionType: .deprecated, capabilities: [.text, .moderation, .deprecated], tier: .small, latency: .veryFast, inputTokenLimit: 32_768, outputTokenLimit: 0),
        
        // Legacy GPT Models
        LLMModelAdapter(name: "gpt-4-turbo", description: "An older high-intelligence GPT model", provider: .openai, category: .chat, versionType: .deprecated, capabilities: [.text, .vision, .tools], tier: .large, latency: .moderate, inputTokenLimit: 128_000, outputTokenLimit: 4_096),
        LLMModelAdapter(name: "gpt-4", description: "An older high-intelligence GPT model", provider: .openai, category: .chat, versionType: .deprecated, capabilities: [.text, .vision, .tools], tier: .large, latency: .moderate, inputTokenLimit: 8_192, outputTokenLimit: 4_096),
        LLMModelAdapter(name: "gpt-3.5-turbo", description: "Legacy GPT model for cheaper chat and non-chat tasks", provider: .openai, category: .chat, versionType: .deprecated, capabilities: [.text, .tools], tier: .medium, latency: .fast, inputTokenLimit: 16_385, outputTokenLimit: 4_096),
        
        // GPT Base Models
        LLMModelAdapter(name: "babbage-002", description: "Replacement for the GPT-3 ada and babbage base models", provider: .openai, category: .completion, capabilities: [.text], tier: .small, latency: .veryFast, inputTokenLimit: 16_384, outputTokenLimit: 16_384),
        LLMModelAdapter(name: "davinci-002", description: "Replacement for the GPT-3 curie and davinci base models", provider: .openai, category: .completion, capabilities: [.text], tier: .medium, latency: .fast, inputTokenLimit: 16_384, outputTokenLimit: 16_384)
    ]
}

// MARK: - Convenience Extensions
public extension OpenAIModels {
    // Most commonly used models for easy access
    static var gpt4o: LLMModelProtocol { OpenAIModels().model(named: "gpt-4o")! }
    static var gpt4oMini: LLMModelProtocol { OpenAIModels().model(named: "gpt-4o-mini")! }
    static var gpt41: LLMModelProtocol { OpenAIModels().model(named: "gpt-4.1")! }
    static var o4Mini: LLMModelProtocol { OpenAIModels().model(named: "o4-mini")! }
    static var o3: LLMModelProtocol { OpenAIModels().model(named: "o3")! }
    static var dalle3: LLMModelProtocol { OpenAIModels().model(named: "dall-e-3")! }
    static var whisper: LLMModelProtocol { OpenAIModels().model(named: "whisper-1")! }
    static var tts1HD: LLMModelProtocol { OpenAIModels().model(named: "tts-1-hd")! }
    
    // Get models by capability
    var reasoningModels: [LLMModelProtocol] { models(with: .reasoning) }
    var chatModels: [LLMModelProtocol] { models(for: .chat) }
    var imageGenerationModels: [LLMModelProtocol] { models(for: .imageGeneration) }
    var embeddingModels: [LLMModelProtocol] { models(for: .embedding) }
    var realtimeModels: [LLMModelProtocol] { models(with: .realtime) }
} 