//
//  ResponseChunk.swift
//  AISDK
//
//  Created by AISDK on 01/01/25.
//

import Foundation

/// Streaming event from OpenAI Responses API
/// Based on official OpenAI Responses API streaming documentation
public struct ResponseStreamEvent: Codable {
    public let type: String
    public let sequenceNumber: Int?
    
    // Response-level events
    public let response: ResponseObject?
    
    // Output item events
    public let outputIndex: Int?
    public let item: ResponseOutputItem?
    public let itemId: String?
    
    // Content events
    public let contentIndex: Int?
    public let part: ResponseContentPart?
    
    // Text delta events
    public let delta: String?
    public let text: String?
    
    // Error events
    public let code: String?
    public let message: String?
    public let param: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case sequenceNumber = "sequence_number"
        case response
        case outputIndex = "output_index"
        case item
        case itemId = "item_id"
        case contentIndex = "content_index"
        case part
        case delta
        case text
        case code
        case message
        case param
    }
}

/// Content part for streaming events
public struct ResponseContentPart: Codable {
    public let type: String
    public let text: String?
    public let annotations: [ResponseAnnotation]?
}

/// Legacy ResponseChunk for backward compatibility
/// This will be used to provide a simplified interface for streaming
public struct ResponseChunk: Codable {
    public let id: String
    public let object: String
    public let createdAt: TimeInterval
    public let model: String
    public let status: ResponseStatus?
    public let delta: ResponseDelta?
    public let usage: ResponseUsage?
    public let error: ResponseError?
    
    enum CodingKeys: String, CodingKey {
        case id, object, model, status, delta, usage, error
        case createdAt = "created_at"
    }
    
    /// Create a ResponseChunk from a streaming event and accumulated state
    public static func from(
        event: ResponseStreamEvent,
        accumulatedResponse: ResponseObject?
    ) -> ResponseChunk? {
        // Extract basic info from accumulated response or create defaults
        let id = accumulatedResponse?.id ?? "stream_\(UUID().uuidString)"
        let model = accumulatedResponse?.model ?? "unknown"
        let createdAt = accumulatedResponse?.createdAt ?? Date().timeIntervalSince1970
        
        // Determine status from event type
        let status: ResponseStatus? = {
            switch event.type {
            case "response.created", "response.in_progress":
                return .inProgress
            case "response.completed":
                return .completed
            case "response.failed":
                return .failed
            case "response.cancelled":
                return .cancelled
            default:
                return accumulatedResponse?.status
            }
        }()
        
        // Create delta from event
        let delta: ResponseDelta? = {
            if event.type == "response.output_text.delta", let deltaText = event.delta {
                return ResponseDelta(
                    output: nil,
                    outputText: deltaText,
                    reasoning: nil,
                    text: deltaText
                )
            } else if event.type == "response.output_text.done", let text = event.text {
                return ResponseDelta(
                    output: nil,
                    outputText: text,
                    reasoning: nil,
                    text: text
                )
            }
            return nil
        }()
        
        // Extract usage from response events
        let usage = (event.type == "response.completed") ? event.response?.usage : nil
        
        // Extract error from error events
        let error: ResponseError? = {
            if event.type == "error", let code = event.code, let message = event.message {
                return ResponseError(code: code, message: message, type: event.param)
            }
            return nil
        }()
        
        return ResponseChunk(
            id: id,
            object: "response.chunk",
            createdAt: createdAt,
            model: model,
            status: status,
            delta: delta,
            usage: usage,
            error: error
        )
    }
}

/// Delta changes in streaming response
public struct ResponseDelta: Codable {
    public let output: [ResponseOutputItem]?
    public let outputText: String?
    public let reasoning: ResponseReasoning?
    public let text: String?
    
    enum CodingKeys: String, CodingKey {
        case output, reasoning, text
        case outputText = "output_text"
    }
}

/// Event types for server-sent events (comprehensive list from OpenAI docs)
public enum ResponseEventType: String, Codable {
    case responseCreated = "response.created"
    case responseInProgress = "response.in_progress"
    case responseCompleted = "response.completed"
    case responseFailed = "response.failed"
    case responseIncomplete = "response.incomplete"
    case responseQueued = "response.queued"
    
    // Output item events
    case responseOutputItemAdded = "response.output_item.added"
    case responseOutputItemDone = "response.output_item.done"
    
    // Content part events
    case responseContentPartAdded = "response.content_part.added"
    case responseContentPartDone = "response.content_part.done"
    
    // Text events
    case responseOutputTextDelta = "response.output_text.delta"
    case responseOutputTextDone = "response.output_text.done"
    case responseRefusalDelta = "response.refusal.delta"
    case responseRefusalDone = "response.refusal.done"
    
    // Function call events
    case responseFunctionCallArgumentsDelta = "response.function_call_arguments.delta"
    case responseFunctionCallArgumentsDone = "response.function_call_arguments.done"
    
    // Tool call events
    case responseFileSearchCallInProgress = "response.file_search_call.in_progress"
    case responseFileSearchCallSearching = "response.file_search_call.searching"
    case responseFileSearchCallCompleted = "response.file_search_call.completed"
    case responseWebSearchCallInProgress = "response.web_search_call.in_progress"
    case responseWebSearchCallSearching = "response.web_search_call.searching"
    case responseWebSearchCallCompleted = "response.web_search_call.completed"
    
    // Reasoning events
    case responseReasoningDelta = "response.reasoning.delta"
    case responseReasoningDone = "response.reasoning.done"
    case responseReasoningSummaryDelta = "response.reasoning_summary.delta"
    case responseReasoningSummaryDone = "response.reasoning_summary.done"
    
    // Error events
    case error = "error"
}

