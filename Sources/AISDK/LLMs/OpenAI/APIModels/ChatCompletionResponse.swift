//
//  CreateChatCompletionResponse.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 29/12/24.
//


import Foundation

/// Matches the "ChatCompletionResponse" schema for a non-streaming chat
public struct ChatCompletionResponse: Decodable, Sendable {
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
    
    // MARK: - Nested Types
    
    public struct Choice: Decodable, Sendable {
        public let index: Int
        public let message: Message
        public let logprobs: Logprobs?
        public let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index, message, logprobs
            case finishReason = "finish_reason"
        }
    }
    
    public struct Message: Decodable, Sendable {
        public let role: String
        
        /// In normal text completions, `content` is the returned text.
        /// Note: This can be null when tool_calls are present
        public let content: String?
        
        /// If tool-calling (function-calling) was used, the assistant can
        /// return "tool_calls" in the message
        public let toolCalls: [ToolCall]?
        
        /// Some responses may provide a `refusal` if the request was refused
        public let refusal: String?
        
        enum CodingKeys: String, CodingKey {
            case role, content, refusal
            case toolCalls = "tool_calls"
        }
    }
    
    /// If the model calls a function, you might see something like:
    /// "tool_calls": [ { "id": "...", "type": "function", "function": {...} } ]
    public struct ToolCall: Codable, Sendable {
        public let id: String
        public let type: String
        public let function: ToolFunctionCall?
        
        enum CodingKeys: String, CodingKey {
            case id
            case type
            case function
        }
    }
    
    public struct ToolFunctionCall: Codable, Sendable {
        public let name: String
        public let arguments: String
        
        enum CodingKeys: String, CodingKey {
            case name
            case arguments
        }
    }
    
    /// If `logprobs = true`, the model can return log probabilities
    public struct Logprobs: Decodable, Sendable {
        // For example, logprob details returned for each token
        // This example is simplified. Adjust to your actual payload structure.
        public let content: [TokenLogprob]?
    }
    
    /// Represents details for each token’s log probability
    public struct TokenLogprob: Decodable, Sendable {
        public let token: String
        public let logprob: Double
        public let bytes: [UInt8]?
        
        /// `top_logprobs` is an array of possible tokens with their logprobs
        /// Note: Excluded for Sendable compliance - rarely used
        // public let topLogprobs: [[String: AnyDecodable]]?
        
        enum CodingKeys: String, CodingKey {
            case token, logprob, bytes
            // case topLogprobs = "top_logprobs"
        }
    }
    
    public struct Usage: Decodable, Sendable {
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int
        public let completionTokensDetails: CompletionTokensDetails?
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case completionTokensDetails = "completion_tokens_details"
        }
    }
    
    public struct CompletionTokensDetails: Decodable, Sendable {
        public let reasoningTokens: Int
        public let acceptedPredictionTokens: Int
        public let rejectedPredictionTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
            case acceptedPredictionTokens = "accepted_prediction_tokens"
            case rejectedPredictionTokens = "rejected_prediction_tokens"
        }
    }
}

/// Similar to AnyEncodable, for decoding arbitrary JSON structures
public struct AnyDecodable: Decodable {
    public let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        // We'll try decoding a variety of types:
        if let c = try? decoder.singleValueContainer() {
            if c.decodeNil() {
                self.value = NSNull()
                return
            }
            if let boolVal = try? c.decode(Bool.self) {
                self.value = boolVal
                return
            }
            if let intVal = try? c.decode(Int.self) {
                self.value = intVal
                return
            }
            if let doubleVal = try? c.decode(Double.self) {
                self.value = doubleVal
                return
            }
            if let stringVal = try? c.decode(String.self) {
                self.value = stringVal
                return
            }
            // Attempt array
            if let arrVal = try? c.decode([AnyDecodable].self) {
                self.value = arrVal.map { $0.value }
                return
            }
            // Attempt dictionary
            if let dictVal = try? c.decode([String: AnyDecodable].self) {
                var decodedDict = [String: Any]()
                for (key, anyDec) in dictVal {
                    decodedDict[key] = anyDec.value
                }
                self.value = decodedDict
                return
            }
        }
        
        throw DecodingError.dataCorruptedError(
            in: try decoder.singleValueContainer(),
            debugDescription: "Unable to decode AnyDecodable"
        )
    }
}
