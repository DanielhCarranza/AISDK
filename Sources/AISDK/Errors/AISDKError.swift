//
//  AISDKError.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 29/12/24.
//

import Foundation
import Alamofire

// Base protocol for all AI SDK errors
public protocol AIError: LocalizedError {
    var detailedDescription: String { get }
}

// Default implementation for AIError
extension AIError {
    // Conform to LocalizedError
    public var errorDescription: String? {
        return detailedDescription
    }
}

public enum AISDKError: AIError {
    case invalidURL
    case underlying(Error)
    case httpError(Int, String)  // e.g. 400, "Bad Request"
    case parsingError(String)
    case custom(String)
    case streamError(String)
    
    public var detailedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL configuration"
        case .underlying(let error):
            return "Underlying error: \(error.localizedDescription)"
        case .httpError(let code, let message):
            return "HTTP Error \(code): \(message)"
        case .parsingError(let details):
            return "Failed to parse response: \(details)"
        case .custom(let message):
            return message
        case .streamError(let details):
            return "Stream error: \(details)"
        }
    }
}

public enum LLMError: AIError, Equatable {
    case invalidRequest(String)
    case networkError(Int?, String)
    case parsingError(String)
    case streamError(String)
    case invalidResponse(String)
    case rateLimitExceeded
    case authenticationError
    case modelNotAvailable
    case contextLengthExceeded
    case underlying(Error)
    
    public static func == (lhs: LLMError, rhs: LLMError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidRequest(let lMsg), .invalidRequest(let rMsg)):
            return lMsg == rMsg
        case (.networkError(let lCode, let lMsg), .networkError(let rCode, let rMsg)):
            return lCode == rCode && lMsg == rMsg
        case (.parsingError(let lMsg), .parsingError(let rMsg)):
            return lMsg == rMsg
        case (.streamError(let lMsg), .streamError(let rMsg)):
            return lMsg == rMsg
        case (.invalidResponse(let lMsg), .invalidResponse(let rMsg)):
            return lMsg == rMsg
        case (.rateLimitExceeded, .rateLimitExceeded),
             (.authenticationError, .authenticationError),
             (.modelNotAvailable, .modelNotAvailable),
             (.contextLengthExceeded, .contextLengthExceeded):
            return true
        case (.underlying(let lError), .underlying(let rError)):
            return lError.localizedDescription == rError.localizedDescription
        default:
            return false
        }
    }
    
    public var detailedDescription: String {
        switch self {
        case .invalidRequest(let details):
            return "Invalid request: \(details)"
        case .networkError(let code, let message):
            if let code = code {
                return "Network error (\(code)): \(message)"
            }
            return "Network error: \(message)"
        case .parsingError(let details):
            return "Failed to parse response: \(details)"
        case .streamError(let details):
            return "Stream error: \(details)"
        case .invalidResponse(let details):
            return "Invalid response: \(details)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .authenticationError:
            return "Authentication failed. Please check your API key."
        case .modelNotAvailable:
            return "The requested model is not available."
        case .contextLengthExceeded:
            return "The input exceeded the model's context length."
        case .underlying(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }
    
    static func from(_ error: Error) -> LLMError {
        if let llmError = error as? LLMError {
            return llmError
        }
        
        // Convert common errors to appropriate LLMError cases
        switch error {
        case let afError as AFError:
            if let responseCode = afError.responseCode {
                switch responseCode {
                case 401:
                    return .authenticationError
                case 429:
                    return .rateLimitExceeded
                case 400...499:
                    return .networkError(responseCode, afError.localizedDescription)
                case 500...599:
                    return .networkError(responseCode, "Server error")
                default:
                    return .networkError(responseCode, afError.localizedDescription)
                }
            }
            return .networkError(nil, afError.localizedDescription)
        default:
            return .underlying(error)
        }
    }
} 

// MARK: - Agent Errors
public enum AgentError: AIError {
    case invalidModel
    case missingAPIKey
    case toolExecutionFailed(String)
    case invalidToolResponse
    case conversationLimitExceeded
    case invalidParameterType(String)
    case invalidConfiguration(String)
    case streamingError(String)
    case underlying(Error)
    case operationCancelled
    public var detailedDescription: String {
        switch self {
        case .invalidModel:
            return "Invalid model configuration"
        case .missingAPIKey:
            return "Missing API key in configuration"
        case .toolExecutionFailed(let message):
            return "Tool execution failed: \(message)"
        case .invalidToolResponse:
            return "Received invalid response from tool"
        case .conversationLimitExceeded:
            return "Conversation length limit exceeded"
        case .invalidParameterType(let parameter):
            return "Invalid parameter type: \(parameter)"
        case .invalidConfiguration(let details):
            return "Invalid configuration: \(details)"
        case .streamingError(let details):
            return "Streaming error: \(details)"
        case .underlying(let error):
            return "Error: \(error.localizedDescription)"
        case .operationCancelled:
            return "Operation was cancelled by a callback handler"
        }
    }
    
    // Add convenience initializer to convert any Error to AgentError
    public init(from error: Error) {
        if let agentError = error as? AgentError {
            self = agentError
        } else {
            self = .underlying(error)
        }
    }
}

// MARK: - Tool Errors
public enum ToolError: AIError {
    case invalidParameters(String)
    case executionFailed(String)
    case validationFailed(String)
    case unsupportedOperation(String)

    public var detailedDescription: String {
        switch self {
        case .invalidParameters(let message):
            return "Invalid tool parameters: \(message)"
        case .executionFailed(let message):
            return "Tool execution failed: \(message)"
        case .validationFailed(let message):
            return "Tool validation failed: \(message)"
        case .unsupportedOperation(let message):
            return "Unsupported operation: \(message)"
        }
    }
}

// MARK: - Provider Access Errors

/// Errors related to provider access control and PHI protection
public enum AIProviderAccessError: AIError, Equatable {
    /// The provider is not in the allowed providers list
    case providerNotAllowed(provider: String, allowedProviders: Set<String>)
    /// Sensitive or PHI data requires explicit provider allowlisting
    case sensitiveDataRequiresAllowlist(sensitivity: DataSensitivity)

    public var detailedDescription: String {
        switch self {
        case .providerNotAllowed(let provider, let allowed):
            let allowedList = allowed.isEmpty ? "(none)" : allowed.sorted().joined(separator: ", ")
            return "Provider '\(provider)' is not allowed. Allowed providers: \(allowedList)"
        case .sensitiveDataRequiresAllowlist(let sensitivity):
            return "Requests with \(sensitivity.rawValue) sensitivity require explicit provider allowlisting via allowedProviders"
        }
    }
}

// MARK: - Error Helpers
extension Error {
    public var userFriendlyDescription: String {
        switch self {
        case let error as AIError:
            return error.detailedDescription
        default:
            return localizedDescription
        }
    }
}

extension Error {
    /// Converts any error to an AIError
    public var asAIError: AIError {
        switch self {
        case let error as AIError:
            return error
        default:
            return AISDKError.underlying(self)
        }
    }
}

