//
//  AgenticModels.swift
//  HealthCompanion
//
//  Created by Apple 55 on 4/27/24.
//

import Foundation

public struct LLMModel {
    public let name: String
    public let modalities: [Modality]
    public var apiKey: String?
    public var mode: Mode?
    
    public init(name: String, modalities: [Modality], apiKey: String? = nil, mode: Mode? = nil) {
        self.name = name
        self.modalities = modalities
        self.apiKey = apiKey
        self.mode = mode
    }
    
    public enum Modality: String {
        case text = "text"
        case vision = "vision"
        case audio = "audio"
        case video = "video"
    }
    
    public enum Mode: String {
        case parallelTools = "PARALLEL_TOOLS"
        case tools = "TOOLS"
        case json  = "JSON"
    }
    
    public enum Capability {
        case functionCalling
        case structuredOutputs
        case uploadFiles
        case imageGeneration
        case codeInterpreter
        case retrieval
    }
}

public struct AgenticModels {
    public static let gpt5 = LLMModel(name: "gpt-5",
                                     modalities: [.text, .vision],
                                     apiKey: ConfigManager.shared["OPENAI_API_KEY"],
                                     mode: .parallelTools)
    
    public static let gpt5Mini = LLMModel(name: "gpt-5-mini",
                                         modalities: [.text, .vision],
                                         apiKey: ConfigManager.shared["OPENAI_API_KEY"],
                                         mode: .parallelTools)
    
    public static let gpt5Nano = LLMModel(name: "gpt-5-nano",
                                         modalities: [.text],
                                         apiKey: ConfigManager.shared["OPENAI_API_KEY"],
                                         mode: .parallelTools)
    
    public static let o3 = LLMModel(name: "o3",
                                    modalities: [.text, .vision, .audio],
                                    apiKey: ConfigManager.shared["OPENAI_API_KEY"],
                                    mode: .parallelTools)
    
    public static let o4mini = LLMModel(name: "o4-mini",
                                    modalities: [.text, .vision],
                                    apiKey: ConfigManager.shared["OPENAI_API_KEY"],
                                    mode: .parallelTools)
                                    
    public static let gpt4 = LLMModel(name: "gpt-4o",
                                    modalities: [.text, .vision],
                                    apiKey: ConfigManager.shared["OPENAI_API_KEY"],
                                    mode: .parallelTools)
                                
    
    public static let llama370b8k = LLMModel(name: "llama3-70b-8192",
                                      modalities: [.text],
                                      apiKey: ConfigManager.shared["GROQ_API_KEY"],
                                      mode: .tools)
    public static let llama38b8k = LLMModel(name: "llama3-8b-8192",
                                      modalities: [.text],
                                      apiKey: ConfigManager.shared["GROQ_API_KEY"],
                                      mode: .tools)
    
    public static let mixtral8x7b32k = LLMModel(name: "groq/mixtral-8x7b-32768",
                                         modalities: [.text],
                                         apiKey: ConfigManager.shared["GROQ_API_KEY"],
                                         mode: .tools)
    
    public static let gemini15ProLatest = LLMModel(name: "gemini-1.5-pro-latest",
                                            modalities: [.text, .vision, .video],
                                            apiKey: ConfigManager.shared["GOOGLE_GEMINI_API_KEY"])

    public static let claude = LLMModel(
        name: "claude-sonnet-4-5-20250929",
        modalities: [.text, .vision],
        apiKey: ConfigManager.shared["CLAUDE_API_KEY"],
        mode: .tools
    )
}
