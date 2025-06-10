//
//  ChatCompletionChunk.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 29/12/24.
//


import Foundation

/// Represents a single chunk in a streamed chat completion response.
public struct ChatCompletionChunk: Decodable {
    public let id: String
    public let object: String
    public let created: Int
    public let model: String
    public let systemFingerprint: String?
    public let serviceTier: String?
    public let choices: [Choice]
    public let usage: Usage?
    
    enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices, usage
        case systemFingerprint = "system_fingerprint"
        case serviceTier = "service_tier"
    }
    
    public struct Choice: Decodable {
        public let index: Int
        public let delta: Delta
        public let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }
    
    public struct Delta: Decodable {
        public let role: String?
        public let content: String?
        public let toolCalls: [ToolCallDelta]?
        
        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
        }
    }
    
    public struct ToolCallDelta: Decodable {
        public let index: Int
        public let id: String?
        public let type: String?
        public let function: FunctionDelta?
    }
    
    public struct FunctionDelta: Decodable {
        public let name: String?
        public let arguments: String?
    }
    
    public struct Usage: Decodable {
        public let promptTokens: Int?
        public let completionTokens: Int?
        public let totalTokens: Int?
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}
