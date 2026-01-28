//
//  GeminiProvider.swift
//  AISDK
//
//  Created by AI Assistant on 01/25/25.
//

import Foundation

/// Concrete implementation of GeminiService with model awareness and smart defaults
public class GeminiProvider: GeminiService {

    // MARK: - Upload Configuration

    private enum UploadConfig {
        static let chunkSize: Int = 262_144  // 256KB (Google recommended)
        static let maxUploadRetries: Int = 3
        static let baseRetryDelay: TimeInterval = 1.0
        static let uploadBaseURL = "https://generativelanguage.googleapis.com/upload/v1beta/files"
    }

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

    // MARK: - Resumable File Upload

    public func uploadFileResumable(
        fileData: Data,
        mimeType: String,
        displayName: String?,
        maxPollAttempts: Int,
        pollInterval: TimeInterval
    ) async throws -> GeminiFile {
        // Check cancellation before starting
        try Task.checkCancellation()

        // Step 1: Initiate resumable upload session
        let uploadURL = try await initiateUploadSession(
            mimeType: mimeType,
            fileSize: fileData.count,
            displayName: displayName
        )

        // Check cancellation after session initiation
        try Task.checkCancellation()

        // Step 2: Upload file content (single or chunked)
        let file = try await uploadFileContent(
            data: fileData,
            to: uploadURL,
            mimeType: mimeType
        )

        // Check cancellation after upload
        try Task.checkCancellation()

        // Step 3: Poll until file is ACTIVE
        guard file.state != .active else {
            return file
        }

        guard let fileName = file.name else {
            throw GeminiError.uploadFailed(reason: "Missing file name in upload response")
        }

        // Polling already has cancellation support built-in
        return try await pollForFileUploadComplete(
            fileURL: URL(string: "https://generativelanguage.googleapis.com/v1beta/\(fileName)")!,
            pollAttempts: maxPollAttempts,
            secondsBetweenPollAttempts: UInt64(pollInterval)
        )
    }

    private func initiateUploadSession(
        mimeType: String,
        fileSize: Int,
        displayName: String?
    ) async throws -> URL {
        try validateAPIKey()

        guard let url = URL(string: UploadConfig.uploadBaseURL) else {
            throw GeminiError.uploadInitiationFailed("Invalid upload URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Required headers for resumable upload initiation
        request.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "X-Goog-Upload-Raw-Size")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Optional: file metadata in body
        if let displayName = displayName {
            let metadata: [String: Any] = [
                "file": ["display_name": displayName]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        } else {
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.uploadInitiationFailed("Invalid response type")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw GeminiError.uploadInitiationFailed("HTTP \(httpResponse.statusCode)")
        }

        // Extract upload URL from response header
        guard let uploadURLString = httpResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLString) else {
            throw GeminiError.uploadInitiationFailed("Missing X-Goog-Upload-URL header")
        }

        return uploadURL
    }

    private func uploadFileContent(
        data: Data,
        to uploadURL: URL,
        mimeType: String
    ) async throws -> GeminiFile {
        // For small files, upload in one request
        if data.count <= UploadConfig.chunkSize {
            return try await uploadSingleChunk(data: data, to: uploadURL)
        }

        // For large files, upload in chunks
        return try await uploadInChunks(data: data, to: uploadURL)
    }

    private func uploadSingleChunk(
        data: Data,
        to uploadURL: URL
    ) async throws -> GeminiFile {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.httpBody = data

        return try await executeUploadWithRetry(request: request, chunkIndex: 0)
    }

    private func uploadInChunks(
        data: Data,
        to uploadURL: URL
    ) async throws -> GeminiFile {
        var offset = 0
        var chunkIndex = 0

        while offset < data.count {
            // Check cancellation before each chunk
            try Task.checkCancellation()

            let chunkEnd = min(offset + UploadConfig.chunkSize, data.count)
            let chunk = data.subdata(in: offset..<chunkEnd)
            let isLastChunk = chunkEnd >= data.count

            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PUT"

            let command = isLastChunk ? "upload, finalize" : "upload"
            request.setValue(command, forHTTPHeaderField: "X-Goog-Upload-Command")
            request.setValue(String(chunk.count), forHTTPHeaderField: "Content-Length")
            request.setValue(String(offset), forHTTPHeaderField: "X-Goog-Upload-Offset")
            request.httpBody = chunk

            if isLastChunk {
                return try await executeUploadWithRetry(request: request, chunkIndex: chunkIndex)
            } else {
                try await executeChunkUploadWithRetry(request: request, chunkIndex: chunkIndex)
            }

            offset = chunkEnd
            chunkIndex += 1
        }

        throw GeminiError.uploadFailed(reason: "Unexpected end of upload loop")
    }

    private func executeUploadWithRetry(
        request: URLRequest,
        chunkIndex: Int,
        attempt: Int = 0
    ) async throws -> GeminiFile {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiError.chunkUploadFailed(chunkIndex: chunkIndex, reason: "Invalid response")
            }

            // Handle success
            if 200..<300 ~= httpResponse.statusCode {
                // Parse the file response
                struct UploadResponse: Decodable {
                    let file: GeminiFile
                }
                let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
                return uploadResponse.file
            }

            // Handle retryable errors
            if isRetryableStatusCode(httpResponse.statusCode) && attempt < UploadConfig.maxUploadRetries {
                let delay = UploadConfig.baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await executeUploadWithRetry(
                    request: request,
                    chunkIndex: chunkIndex,
                    attempt: attempt + 1
                )
            }

            // Non-retryable error
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GeminiError.chunkUploadFailed(
                chunkIndex: chunkIndex,
                reason: "HTTP \(httpResponse.statusCode): \(errorMessage)"
            )
        } catch let error as GeminiError {
            throw error
        } catch {
            // Handle network errors with retry
            if isRetryableError(error) && attempt < UploadConfig.maxUploadRetries {
                let delay = UploadConfig.baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await executeUploadWithRetry(
                    request: request,
                    chunkIndex: chunkIndex,
                    attempt: attempt + 1
                )
            }
            throw error
        }
    }

    private func executeChunkUploadWithRetry(
        request: URLRequest,
        chunkIndex: Int,
        attempt: Int = 0
    ) async throws {
        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiError.chunkUploadFailed(chunkIndex: chunkIndex, reason: "Invalid response")
            }

            // 308 Resume Incomplete is expected for intermediate chunks
            if httpResponse.statusCode == 308 || (200..<300 ~= httpResponse.statusCode) {
                return
            }

            if isRetryableStatusCode(httpResponse.statusCode) && attempt < UploadConfig.maxUploadRetries {
                let delay = UploadConfig.baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await executeChunkUploadWithRetry(
                    request: request,
                    chunkIndex: chunkIndex,
                    attempt: attempt + 1
                )
            }

            throw GeminiError.chunkUploadFailed(
                chunkIndex: chunkIndex,
                reason: "HTTP \(httpResponse.statusCode)"
            )
        } catch let error as GeminiError {
            throw error
        } catch {
            if isRetryableError(error) && attempt < UploadConfig.maxUploadRetries {
                let delay = UploadConfig.baseRetryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await executeChunkUploadWithRetry(
                    request: request,
                    chunkIndex: chunkIndex,
                    attempt: attempt + 1
                )
            }
            throw error
        }
    }

    private func isRetryableStatusCode(_ statusCode: Int) -> Bool {
        // Retry on rate limiting and server errors
        return statusCode == 429 || (500..<600 ~= statusCode)
    }

    private func isRetryableError(_ error: Error) -> Bool {
        // Don't retry cancellation
        if error is CancellationError { return false }

        // Retry on network errors
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let retryableCodes = [
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorTimedOut
            ]
            return retryableCodes.contains(nsError.code)
        }

        return false
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