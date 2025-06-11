//
//  AgenticModels.swift
//  HealthCompanion
//
//  Created by Apple 55 on 4/27/24.
//

import Foundation

struct LLMModel {
    let name: String
    let modalities: [Modality]
    var apiKey: String?
    var mode: Mode?
    
    enum Modality: String {
        case text = "text"
        case vision = "vision"
        case audio = "audio"
        case video = "video"
    }
    
    enum Mode: String {
        case parallelTools = "PARALLEL_TOOLS"
        case tools = "TOOLS"
        case json  = "JSON"
    }
    
    enum Capability {
        case functionCalling
        case structuredOutputs
        case uploadFiles
        case imageGeneration
        case codeInterpreter
        case retrieval
    }
}

struct AgenticModels {
    static let o4mini = LLMModel(name: "o4-mini",
                                    modalities: [.text, .vision],
                                    apiKey: ConfigManager.shared["OPENAI_API_KEY"],
                                    mode: .parallelTools)
                                    
    static let gpt4 = LLMModel(name: "gpt-4o",
                                    modalities: [.text, .vision],
                                    apiKey: ConfigManager.shared["OPENAI_API_KEY"],
                                    mode: .parallelTools)
                                
    
    static let llama370b8k = LLMModel(name: "llama3-70b-8192",
                                      modalities: [.text],
                                      apiKey: ConfigManager.shared["GROQ_API_KEY"],
                                      mode: .tools)
    static let llama38b8k = LLMModel(name: "llama3-8b-8192",
                                      modalities: [.text],
                                      apiKey: ConfigManager.shared["GROQ_API_KEY"],
                                      mode: .tools)
    
    static let mixtral8x7b32k = LLMModel(name: "groq/mixtral-8x7b-32768",
                                         modalities: [.text],
                                         apiKey: ConfigManager.shared["GROQ_API_KEY"],
                                         mode: .tools)
    
    static let gemini15ProLatest = LLMModel(name: "gemini-1.5-pro-latest",
                                            modalities: [.text, .vision, .video],
                                            apiKey: ConfigManager.shared["GOOGLE_GEMINI_API_KEY"])

    public static let claude = LLMModel(
        name: "claude-3-7-sonnet-20250219",
        modalities: [.text, .vision],
        apiKey: ConfigManager.shared["CLAUDE_API_KEY"],
        mode: .tools
    )
}
