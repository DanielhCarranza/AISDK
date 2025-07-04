//
//  ResponseAgentError.swift
//  AISDK
//
//  Created by AISDK on 01/01/25.
//

import Foundation

/// Comprehensive error handling for ResponseAgent
public enum ResponseAgentError: Error, LocalizedError, Equatable {
    // MARK: - Initialization Errors
    case invalidProvider(String)
    case invalidConfiguration(String)
    
    // MARK: - Tool Execution Errors  
    case toolNotFound(String)
    case toolExecutionFailed(String, Error?)
    case toolValidationFailed(String, String)
    case toolConflict(customTool: String, builtInTool: String)
    
    // MARK: - Response API Errors
    case responseAPIError(String)
    case backgroundProcessingFailed(String)
    case streamingError(String)
    case responseConversionFailed(String)
    
    // MARK: - Input/Output Errors
    case invalidInput(String)
    case emptyConversation
    case messageConversionFailed(String)
    
    // MARK: - State Management Errors
    case invalidState(String)
    case operationCancelled
    case agentBusy
    
    // MARK: - Background Processing Errors
    case backgroundTaskTimeout(String)
    case backgroundTaskFailed(String)
    case pollingError(String)
    
    // MARK: - LocalizedError Implementation
    
    public var errorDescription: String? {
        switch self {
        case .invalidProvider(let message):
            return "Invalid provider configuration: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid ResponseAgent configuration: \(message)"
            
        case .toolNotFound(let toolName):
            return "Tool '\(toolName)' not found in registry"
        case .toolExecutionFailed(let toolName, let underlyingError):
            if let error = underlyingError {
                return "Tool '\(toolName)' execution failed: \(error.localizedDescription)"
            } else {
                return "Tool '\(toolName)' execution failed"
            }
        case .toolValidationFailed(let toolName, let reason):
            return "Tool '\(toolName)' validation failed: \(reason)"
        case .toolConflict(let customTool, let builtInTool):
            return "Tool name conflict: Custom tool '\(customTool)' conflicts with built-in tool '\(builtInTool)'"
            
        case .responseAPIError(let message):
            return "Response API error: \(message)"
        case .backgroundProcessingFailed(let message):
            return "Background processing failed: \(message)"
        case .streamingError(let message):
            return "Streaming error: \(message)"
        case .responseConversionFailed(let message):
            return "Response conversion failed: \(message)"
            
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .emptyConversation:
            return "Cannot process empty conversation"
        case .messageConversionFailed(let message):
            return "Message conversion failed: \(message)"
            
        case .invalidState(let message):
            return "Invalid agent state: \(message)"
        case .operationCancelled:
            return "Operation was cancelled"
        case .agentBusy:
            return "Agent is currently busy processing another request"
            
        case .backgroundTaskTimeout(let taskId):
            return "Background task '\(taskId)' timed out"
        case .backgroundTaskFailed(let message):
            return "Background task failed: \(message)"
        case .pollingError(let message):
            return "Polling error: \(message)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .invalidProvider:
            return "The OpenAI provider is not properly configured for Response API usage"
        case .invalidConfiguration:
            return "ResponseAgent initialization parameters are invalid"
            
        case .toolNotFound:
            return "The requested tool has not been registered with the ToolRegistry"
        case .toolExecutionFailed:
            return "The tool failed to execute successfully"
        case .toolValidationFailed:
            return "Tool parameters failed validation"
        case .toolConflict:
            return "A custom tool name conflicts with a built-in Response API tool"
            
        case .responseAPIError:
            return "The OpenAI Response API returned an error"
        case .backgroundProcessingFailed:
            return "Background processing could not be completed"
        case .streamingError:
            return "An error occurred during response streaming"
        case .responseConversionFailed:
            return "Could not convert Response API response to expected format"
            
        case .invalidInput:
            return "The provided input is not valid for processing"
        case .emptyConversation:
            return "At least one message is required to start a conversation"
        case .messageConversionFailed:
            return "Could not convert message to required format"
            
        case .invalidState:
            return "The agent is in an invalid state for this operation"
        case .operationCancelled:
            return "The operation was cancelled by user request"
        case .agentBusy:
            return "The agent can only process one request at a time"
            
        case .backgroundTaskTimeout:
            return "The background task exceeded the maximum allowed time"
        case .backgroundTaskFailed:
            return "The background task could not be completed"
        case .pollingError:
            return "Error occurred while polling for background task completion"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .invalidProvider:
            return "Ensure you're using a properly configured OpenAIProvider with valid API credentials"
        case .invalidConfiguration:
            return "Check ResponseAgent initialization parameters and try again"
            
        case .toolNotFound:
            return "Register the tool with ToolRegistry.register(tool:) before using ResponseAgent"
        case .toolExecutionFailed:
            return "Check tool implementation and ensure all required parameters are provided"
        case .toolValidationFailed:
            return "Verify tool parameters match the expected schema"
        case .toolConflict:
            return "Rename your custom tool to avoid conflicts with built-in tools"
            
        case .responseAPIError:
            return "Check your OpenAI API configuration and network connectivity"
        case .backgroundProcessingFailed:
            return "Try the request again or use regular processing instead of background"
        case .streamingError:
            return "Try using non-streaming mode or check network connectivity"
        case .responseConversionFailed:
            return "This may be an internal error - please report if it persists"
            
        case .invalidInput:
            return "Provide valid input data and try again"
        case .emptyConversation:
            return "Send at least one message to start the conversation"
        case .messageConversionFailed:
            return "Ensure message content is properly formatted"
            
        case .invalidState:
            return "Wait for current operation to complete before starting a new one"
        case .operationCancelled:
            return "Start a new operation if needed"
        case .agentBusy:
            return "Wait for the current operation to complete before sending another request"
            
        case .backgroundTaskTimeout:
            return "Try using a simpler request or increase timeout if available"
        case .backgroundTaskFailed:
            return "Check the task parameters and try again"
        case .pollingError:
            return "Check network connectivity and try retrieving the result again"
        }
    }
    
    // MARK: - Equatable Implementation
    
    public static func == (lhs: ResponseAgentError, rhs: ResponseAgentError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidProvider(let lhsMsg), .invalidProvider(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.invalidConfiguration(let lhsMsg), .invalidConfiguration(let rhsMsg)):
            return lhsMsg == rhsMsg
            
        case (.toolNotFound(let lhsTool), .toolNotFound(let rhsTool)):
            return lhsTool == rhsTool
        case (.toolExecutionFailed(let lhsTool, _), .toolExecutionFailed(let rhsTool, _)):
            return lhsTool == rhsTool // Compare tool names, not underlying errors
        case (.toolValidationFailed(let lhsTool, let lhsReason), .toolValidationFailed(let rhsTool, let rhsReason)):
            return lhsTool == rhsTool && lhsReason == rhsReason
        case (.toolConflict(let lhsCustom, let lhsBuiltIn), .toolConflict(let rhsCustom, let rhsBuiltIn)):
            return lhsCustom == rhsCustom && lhsBuiltIn == rhsBuiltIn
            
        case (.responseAPIError(let lhsMsg), .responseAPIError(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.backgroundProcessingFailed(let lhsMsg), .backgroundProcessingFailed(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.streamingError(let lhsMsg), .streamingError(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.responseConversionFailed(let lhsMsg), .responseConversionFailed(let rhsMsg)):
            return lhsMsg == rhsMsg
            
        case (.invalidInput(let lhsMsg), .invalidInput(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.emptyConversation, .emptyConversation):
            return true
        case (.messageConversionFailed(let lhsMsg), .messageConversionFailed(let rhsMsg)):
            return lhsMsg == rhsMsg
            
        case (.invalidState(let lhsMsg), .invalidState(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.operationCancelled, .operationCancelled):
            return true
        case (.agentBusy, .agentBusy):
            return true
            
        case (.backgroundTaskTimeout(let lhsId), .backgroundTaskTimeout(let rhsId)):
            return lhsId == rhsId
        case (.backgroundTaskFailed(let lhsMsg), .backgroundTaskFailed(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.pollingError(let lhsMsg), .pollingError(let rhsMsg)):
            return lhsMsg == rhsMsg
            
        default:
            return false
        }
    }
}

// MARK: - Error Conversion Helpers

extension ResponseAgentError {
    /// Convert from underlying errors to ResponseAgentError
    static func from(_ error: Error) -> ResponseAgentError {
        if let responseAgentError = error as? ResponseAgentError {
            return responseAgentError
        }
        
        // Convert common error types
        if let aiError = error as? AISDKError {
            switch aiError {
            case .httpError(_, let message):
                return .responseAPIError(message)
            case .streamError(let message):
                return .streamingError(message)
            case .parsingError(let message):
                return .responseConversionFailed(message)
            default:
                return .responseAPIError(aiError.localizedDescription)
            }
        }
        
        if let toolError = error as? ToolError {
            switch toolError {
            case .invalidParameters(let message):
                return .toolValidationFailed("unknown", message)
            case .executionFailed(let message):
                return .toolExecutionFailed("unknown", error)
            default:
                return .responseAPIError(toolError.localizedDescription)
            }
        }
        
        // Default conversion
        return .responseAPIError("Unexpected error: \(error.localizedDescription)")
    }
} 