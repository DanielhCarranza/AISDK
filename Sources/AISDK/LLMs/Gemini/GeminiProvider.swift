//
//  GeminiProvider.swift
//  AISDK
//
//  Created by AI Assistant on 01/25/25.
//

import Foundation

/// Concrete implementation of GeminiService with model awareness and smart defaults
public class GeminiProvider: GeminiService {
    
    // MARK: - Properties
    
    private let apiKey: String
    private let baseUrl: String
    private let maxRetries: Int
    private let retryDelay: TimeInterval
    
    /// The selected model for this provider instance
    public let model: LLMModelProtocol
    
    // MARK: - Initialization
    
    /// Model-aware initializer with smart default
    /// - Parameters:
    ///   - model: The Gemini model to use (defaults to Gemini 2.5 Flash)
    ///   - apiKey: Your Google AI API key (falls back to environment variable)
    ///   - baseUrl: Base URL for Google AI API (defaults to official API)
    ///   - maxRetries: Maximum number of retry attempts for failed requests
    ///   - retryDelay: Delay between retry attempts in seconds
    public init(
        model: LLMModelProtocol? = nil,
        apiKey: String? = nil,
        baseUrl: String = "https://generativelanguage.googleapis.com/v1beta",
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0
    ) {
        // Use provided model or default to Gemini's best balance of performance and cost
        self.model = model ?? GeminiModels.gemini25Flash
        
        // API key resolution: parameter → environment → empty (will throw later)
        self.apiKey = apiKey 
            ?? ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] 
            ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"] 
            ?? ""
        
        self.baseUrl = baseUrl
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
    
    /// Legacy initializer - maintained for backward compatibility
    /// - Parameters:
    ///   - apiKey: Your Google AI API key
    ///   - baseUrl: Base URL for Google AI API (defaults to official API)
    ///   - maxRetries: Maximum number of retry attempts for failed requests
    ///   - retryDelay: Delay between retry attempts in seconds
    public init(
        apiKey: String? = nil,
        baseUrl: String = "https://generativelanguage.googleapis.com/v1beta",
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0
    ) {
        self.model = GeminiModels.gemini25Flash // Default model for legacy usage
        
        // API key resolution: parameter → environment → empty (will throw later)
        self.apiKey = apiKey 
            ?? ProcessInfo.processInfo.environment["GOOGLE_API_KEY"] 
            ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"] 
            ?? ""
        
        self.baseUrl = baseUrl
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
    }
    
    // MARK: - GeminiService Protocol Implementation
    
    public func generateContentRequest(
        body: GeminiGenerateContentRequestBody,
        model: String,
        secondsToWait: UInt
    ) async throws -> GeminiGenerateContentResponseBody {
        let effectiveModel = model.isEmpty ? self.model.name : model
        return try await performGenerateContentRequest(
            body: body,
            model: effectiveModel,
            secondsToWait: secondsToWait
        )
    }
    
    public func generateStreamingContentRequest(
        body: GeminiGenerateContentRequestBody,
        model: String,
        secondsToWait: UInt
    ) async throws -> AsyncCompactMapSequence<AsyncLineSequence<URLSession.AsyncBytes>, GeminiGenerateContentResponseBody> {
        let effectiveModel = model.isEmpty ? self.model.name : model
        return try await performStreamingGenerateContentRequest(
            body: body,
            model: effectiveModel,
            secondsToWait: secondsToWait
        )
    }
    
    public func makeImagenRequest(
        body: GeminiImagenRequestBody,
        model: String
    ) async throws -> GeminiImagenResponseBody {
        let effectiveModel = model.isEmpty ? self.model.name : model
        return try await performImagenRequest(body: body, model: effectiveModel)
    }
    
    public func uploadFile(
        fileData: Data,
        mimeType: String
    ) async throws -> GeminiFile {
        return try await performFileUpload(fileData: fileData, mimeType: mimeType)
    }
    
    public func deleteFile(fileURL: URL) async throws {
        try await performFileDelete(fileURL: fileURL)
    }
    
    public func getStatus(fileURL: URL) async throws -> GeminiFile {
        return try await performGetFileStatus(fileURL: fileURL)
    }
    
    // MARK: - Private Implementation Methods
    
    private func validateAPIKey() throws {
        guard !apiKey.isEmpty else {
            throw LLMError.authenticationError
        }
    }
    
    private func performGenerateContentRequest(
        body: GeminiGenerateContentRequestBody,
        model: String,
        secondsToWait: UInt
    ) async throws -> GeminiGenerateContentResponseBody {
        try validateAPIKey()
        
        let endpoint = "\(baseUrl)/models/\(model):generateContent"
        
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid Gemini API URL configuration")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = TimeInterval(secondsToWait)
        
        // Encode request body
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw LLMError.parsingError("Failed to encode request: \(error.localizedDescription)")
        }
        
        // Perform request with retry logic
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    guard 200...299 ~= httpResponse.statusCode else {
                        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                        throw LLMError.networkError(httpResponse.statusCode, errorMessage)
                    }
                }
                
                return try JSONDecoder().decode(GeminiGenerateContentResponseBody.self, from: data)
                
            } catch {
                lastError = error
                
                // Don't retry on client errors (4xx) except rate limiting
                if let llmError = error as? LLMError,
                   case .networkError(let statusCode, _) = llmError,
                   let code = statusCode,
                   code >= 400 && code < 500 && code != 429 {
                    throw error
                }
                
                // If this is our last attempt, throw the error
                if attempt == maxRetries {
                    throw error
                }
                
                // Wait before retrying
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
        
        throw lastError ?? LLMError.networkError(nil, "Unknown error")
    }
    
    private func performStreamingGenerateContentRequest(
        body: GeminiGenerateContentRequestBody,
        model: String,
        secondsToWait: UInt
    ) async throws -> AsyncCompactMapSequence<AsyncLineSequence<URLSession.AsyncBytes>, GeminiGenerateContentResponseBody> {
        try validateAPIKey()
        
        let endpoint = "\(baseUrl)/models/\(model):streamGenerateContent"
        
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid Gemini API URL configuration")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = TimeInterval(secondsToWait)
        
        // Encode request body
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw LLMError.parsingError("Failed to encode request: \(error.localizedDescription)")
        }
        
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard 200...299 ~= httpResponse.statusCode else {
                throw LLMError.networkError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
            }
        }
        
        return asyncBytes.lines.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(GeminiGenerateContentResponseBody.self, from: data)
        }
    }
    
    private func performImagenRequest(
        body: GeminiImagenRequestBody,
        model: String
    ) async throws -> GeminiImagenResponseBody {
        try validateAPIKey()
        
        // Imagen has a different endpoint structure
        let endpoint = "\(baseUrl)/models/\(model):predict"
        
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid Imagen API URL configuration")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        // Encode request body
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw LLMError.parsingError("Failed to encode request: \(error.localizedDescription)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw LLMError.networkError(httpResponse.statusCode, errorMessage)
            }
        }
        
        return try JSONDecoder().decode(GeminiImagenResponseBody.self, from: data)
    }
    
    private func performFileUpload(
        fileData: Data,
        mimeType: String
    ) async throws -> GeminiFile {
        try validateAPIKey()
        
        let endpoint = "\(baseUrl)/upload/v1beta/files"
        
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid file upload URL configuration")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = fileData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw LLMError.networkError(httpResponse.statusCode, errorMessage)
            }
        }
        
        let uploadResponse = try JSONDecoder().decode(GeminiFileUploadResponseBody.self, from: data)
        return uploadResponse.file
    }
    
    private func performFileDelete(fileURL: URL) async throws {
        try validateAPIKey()
        
        var request = URLRequest(url: fileURL)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard 200...299 ~= httpResponse.statusCode else {
                throw LLMError.networkError(httpResponse.statusCode, "Failed to delete file")
            }
        }
    }
    
    private func performGetFileStatus(fileURL: URL) async throws -> GeminiFile {
        try validateAPIKey()
        
        var request = URLRequest(url: fileURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            guard 200...299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw LLMError.networkError(httpResponse.statusCode, errorMessage)
            }
        }
        
        return try JSONDecoder().decode(GeminiFile.self, from: data)
    }
} 