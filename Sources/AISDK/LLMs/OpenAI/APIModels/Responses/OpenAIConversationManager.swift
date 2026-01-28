//
//  OpenAIConversationManager.swift
//  AISDK
//
//  Conversation management for OpenAI Responses API
//  Supports persistent conversation threads with CRUD operations
//

import Foundation

// MARK: - OpenAIConversationManager

/// Actor-based conversation manager for OpenAI persistent conversations
///
/// Provides thread-safe conversation management operations for use with
/// the Responses API. Conversations allow multiple responses to be grouped
/// together with full CRUD operations on conversation items.
///
/// Example:
/// ```swift
/// let conversationManager = OpenAIConversationManager(apiKey: "sk-...")
///
/// // Create a new conversation
/// let conversation = try await conversationManager.create(
///     metadata: ["session_id": "abc123", "user_id": "user_456"]
/// )
///
/// // Add items to the conversation
/// let items = try await conversationManager.createItems(
///     conversationId: conversation.id,
///     items: [.userMessage("Hello!"), .assistantMessage("Hi there!")]
/// )
///
/// // List all items
/// let allItems = try await conversationManager.listItems(conversationId: conversation.id)
///
/// // Delete the conversation when done
/// try await conversationManager.delete(id: conversation.id)
/// ```
public actor OpenAIConversationManager {
    private let baseURL = "https://api.openai.com/v1/conversations"
    private let apiKey: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Create Conversation

    /// Create a new conversation
    ///
    /// - Parameters:
    ///   - items: Optional initial items to add
    ///   - metadata: Optional metadata key-value pairs
    /// - Returns: The created conversation
    /// - Throws: `AISDKErrorV2` if creation fails
    public func create(
        items: [ConversationInputItem]? = nil,
        metadata: [String: String]? = nil
    ) async throws -> Conversation {
        var request = makeRequest(url: URL(string: baseURL)!, method: "POST")

        let body = CreateConversationRequest(items: items, metadata: metadata)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(Conversation.self, from: data)
    }

    // MARK: - List Conversations

    /// List conversations with pagination
    ///
    /// - Parameters:
    ///   - limit: Maximum number of results (default: 20)
    ///   - after: Cursor for forward pagination
    ///   - before: Cursor for backward pagination
    ///   - order: Sort order (default: descending by creation time)
    /// - Returns: List of conversations
    /// - Throws: `AISDKErrorV2` if the request fails
    public func list(
        limit: Int = 20,
        after: String? = nil,
        before: String? = nil,
        order: SortOrder = .desc
    ) async throws -> ConversationList {
        var components = URLComponents(string: baseURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order", value: order.rawValue)
        ]
        if let after = after { queryItems.append(URLQueryItem(name: "after", value: after)) }
        if let before = before { queryItems.append(URLQueryItem(name: "before", value: before)) }
        components.queryItems = queryItems

        let request = makeRequest(url: components.url!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(ConversationList.self, from: data)
    }

    // MARK: - Retrieve Conversation

    /// Retrieve a conversation by ID
    ///
    /// - Parameter id: The conversation ID
    /// - Returns: The conversation
    /// - Throws: `AISDKErrorV2` if not found or request fails
    public func retrieve(id: String) async throws -> Conversation {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(id)")!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(Conversation.self, from: data)
    }

    // MARK: - Update Conversation

    /// Update a conversation's metadata
    ///
    /// - Parameters:
    ///   - id: The conversation ID
    ///   - metadata: New metadata key-value pairs
    /// - Returns: The updated conversation
    /// - Throws: `AISDKErrorV2` if update fails
    public func update(id: String, metadata: [String: String]) async throws -> Conversation {
        var request = makeRequest(url: URL(string: "\(baseURL)/\(id)")!, method: "POST")

        let body = UpdateConversationRequest(metadata: metadata)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(Conversation.self, from: data)
    }

    // MARK: - Delete Conversation

    /// Delete a conversation
    ///
    /// - Parameter id: The conversation ID to delete
    /// - Returns: Deletion status
    /// - Throws: `AISDKErrorV2` if deletion fails
    public func delete(id: String) async throws -> DeletionStatus {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(id)")!, method: "DELETE")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(DeletionStatus.self, from: data)
    }

    // MARK: - Item Operations

    /// List items in a conversation
    ///
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - limit: Maximum number of results (default: 20)
    ///   - after: Cursor for forward pagination
    ///   - before: Cursor for backward pagination
    ///   - order: Sort order (default: descending by creation time)
    ///   - include: Optional expansion options for additional data
    /// - Returns: List of conversation items
    /// - Throws: `AISDKErrorV2` if the request fails
    public func listItems(
        conversationId: String,
        limit: Int = 20,
        after: String? = nil,
        before: String? = nil,
        order: SortOrder = .desc,
        include: [ConversationIncludeOption]? = nil
    ) async throws -> ConversationItemList {
        var components = URLComponents(string: "\(baseURL)/\(conversationId)/items")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order", value: order.rawValue)
        ]
        if let after = after { queryItems.append(URLQueryItem(name: "after", value: after)) }
        if let before = before { queryItems.append(URLQueryItem(name: "before", value: before)) }
        if let include = include {
            for option in include {
                queryItems.append(URLQueryItem(name: "include[]", value: option.rawValue))
            }
        }
        components.queryItems = queryItems

        let request = makeRequest(url: components.url!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(ConversationItemList.self, from: data)
    }

    /// Add items to a conversation
    ///
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - items: Items to add (up to 20 at a time)
    /// - Returns: List of added items
    /// - Throws: `AISDKErrorV2` if the operation fails
    public func createItems(conversationId: String, items: [ConversationInputItem]) async throws -> ConversationItemList {
        guard items.count <= 20 else {
            throw AISDKErrorV2(code: .invalidRequest, message: "Cannot add more than 20 items at a time")
        }

        var request = makeRequest(url: URL(string: "\(baseURL)/\(conversationId)/items")!, method: "POST")

        let body = CreateItemsRequest(items: items)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(ConversationItemList.self, from: data)
    }

    /// Retrieve a specific item from a conversation
    ///
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - itemId: The item ID
    ///   - include: Optional expansion options for additional data
    /// - Returns: The conversation item
    /// - Throws: `AISDKErrorV2` if not found or request fails
    public func retrieveItem(
        conversationId: String,
        itemId: String,
        include: [ConversationIncludeOption]? = nil
    ) async throws -> ConversationItem {
        var components = URLComponents(string: "\(baseURL)/\(conversationId)/items/\(itemId)")!
        if let include = include {
            components.queryItems = include.map { URLQueryItem(name: "include[]", value: $0.rawValue) }
        }

        let request = makeRequest(url: components.url!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(ConversationItem.self, from: data)
    }

    /// Delete an item from a conversation
    ///
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - itemId: The item ID to delete
    /// - Returns: The updated conversation
    /// - Throws: `AISDKErrorV2` if deletion fails
    public func deleteItem(conversationId: String, itemId: String) async throws -> Conversation {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(conversationId)/items/\(itemId)")!, method: "DELETE")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(Conversation.self, from: data)
    }

    // MARK: - Helpers

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AISDKErrorV2(code: .networkFailed, message: "Invalid response type")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"
            throw mapHTTPError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        struct OpenAIError: Codable {
            let error: ErrorDetail
            struct ErrorDetail: Codable {
                let message: String
            }
        }

        if let error = try? JSONDecoder().decode(OpenAIError.self, from: data) {
            return error.error.message
        }
        return String(data: data, encoding: .utf8)
    }

    private func mapHTTPError(statusCode: Int, message: String) -> AISDKErrorV2 {
        switch statusCode {
        case 400:
            return AISDKErrorV2(code: .invalidRequest, message: message)
        case 401:
            return AISDKErrorV2(code: .authenticationFailed, message: message)
        case 404:
            return AISDKErrorV2(code: .invalidRequest, message: "Conversation not found: \(message)")
        case 429:
            return AISDKErrorV2(code: .rateLimitExceeded, message: message)
        case 500...599:
            return AISDKErrorV2(code: .providerUnavailable, message: message)
        default:
            return AISDKErrorV2(code: .unknown, message: message)
        }
    }
}

// MARK: - Conversation

/// A persistent conversation in the OpenAI Responses API
public struct Conversation: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let createdAt: Int
    public let metadata: [String: String]?

    public init(
        id: String,
        object: String = "conversation",
        createdAt: Int,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.object = object
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

// MARK: - Conversation List

/// Paginated list of conversations
public struct ConversationList: Codable, Sendable {
    public let object: String
    public let data: [Conversation]
    public let firstId: String?
    public let lastId: String?
    public let hasMore: Bool

    public init(
        object: String = "list",
        data: [Conversation],
        firstId: String? = nil,
        lastId: String? = nil,
        hasMore: Bool = false
    ) {
        self.object = object
        self.data = data
        self.firstId = firstId
        self.lastId = lastId
        self.hasMore = hasMore
    }
}

// MARK: - Conversation Item

/// An item within a conversation
public struct ConversationItem: Codable, Sendable {
    public let type: ConversationItemType
    public let id: String?
    public let status: ConversationItemStatus?
    public let role: ConversationRole?
    public let content: [ConversationContentPart]?

    public init(
        type: ConversationItemType,
        id: String? = nil,
        status: ConversationItemStatus? = nil,
        role: ConversationRole? = nil,
        content: [ConversationContentPart]? = nil
    ) {
        self.type = type
        self.id = id
        self.status = status
        self.role = role
        self.content = content
    }
}

// MARK: - Conversation Input Item

/// An item to add to a conversation (simplified for input)
public struct ConversationInputItem: Codable, Sendable {
    public let type: ConversationItemType
    public let role: ConversationRole?
    public let content: [ConversationInputContentPart]?
    public let callId: String?
    public let output: String?

    public init(
        type: ConversationItemType,
        role: ConversationRole? = nil,
        content: [ConversationInputContentPart]? = nil,
        callId: String? = nil,
        output: String? = nil
    ) {
        self.type = type
        self.role = role
        self.content = content
        self.callId = callId
        self.output = output
    }

    // Convenience initializers

    /// Create a user message item
    public static func userMessage(_ text: String) -> ConversationInputItem {
        ConversationInputItem(
            type: .message,
            role: .user,
            content: [.inputText(text)]
        )
    }

    /// Create an assistant message item
    public static func assistantMessage(_ text: String) -> ConversationInputItem {
        ConversationInputItem(
            type: .message,
            role: .assistant,
            content: [.inputText(text)]
        )
    }

    /// Create a system message item
    public static func systemMessage(_ text: String) -> ConversationInputItem {
        ConversationInputItem(
            type: .message,
            role: .system,
            content: [.inputText(text)]
        )
    }

    /// Create a function call output item
    public static func functionCallOutput(callId: String, output: String) -> ConversationInputItem {
        ConversationInputItem(
            type: .functionCallOutput,
            callId: callId,
            output: output
        )
    }
}

// MARK: - Conversation Item Type

/// Type of conversation item
public enum ConversationItemType: String, Codable, Sendable {
    case message
    case functionCall = "function_call"
    case functionCallOutput = "function_call_output"
    case fileSearchCall = "file_search_call"
    case webSearchCall = "web_search_call"
    case codeInterpreterCall = "code_interpreter_call"
    case computerCall = "computer_call"
    case reasoning
}

// MARK: - Conversation Item Status

/// Status of a conversation item
public enum ConversationItemStatus: String, Codable, Sendable {
    case inProgress = "in_progress"
    case completed
    case incomplete
}

// MARK: - Conversation Role

/// Role in a conversation
public enum ConversationRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

// MARK: - Conversation Content Part (Output)

/// Content part within a conversation item (for output/retrieval)
public enum ConversationContentPart: Codable, Sendable {
    case inputText(ConversationInputTextContent)
    case inputImage(ConversationInputImageContent)
    case inputFile(ConversationInputFileContent)
    case outputText(ConversationOutputTextContent)
    case refusal(String)

    private enum CodingKeys: String, CodingKey {
        case type, text, imageUrl, fileId, detail, annotations, refusal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "input_text":
            let text = try container.decode(String.self, forKey: .text)
            self = .inputText(ConversationInputTextContent(text: text))
        case "input_image":
            let imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
            let fileId = try container.decodeIfPresent(String.self, forKey: .fileId)
            let detail = try container.decodeIfPresent(String.self, forKey: .detail)
            self = .inputImage(ConversationInputImageContent(imageUrl: imageUrl, fileId: fileId, detail: detail))
        case "input_file":
            let fileId = try container.decode(String.self, forKey: .fileId)
            self = .inputFile(ConversationInputFileContent(fileId: fileId))
        case "output_text":
            let text = try container.decode(String.self, forKey: .text)
            let annotations = try container.decodeIfPresent([ConversationAnnotation].self, forKey: .annotations)
            self = .outputText(ConversationOutputTextContent(text: text, annotations: annotations))
        case "refusal":
            let refusal = try container.decode(String.self, forKey: .refusal)
            self = .refusal(refusal)
        default:
            // Fallback to input text
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .inputText(ConversationInputTextContent(text: text))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .inputText(let content):
            try container.encode("input_text", forKey: .type)
            try container.encode(content.text, forKey: .text)
        case .inputImage(let content):
            try container.encode("input_image", forKey: .type)
            try container.encodeIfPresent(content.imageUrl, forKey: .imageUrl)
            try container.encodeIfPresent(content.fileId, forKey: .fileId)
            try container.encodeIfPresent(content.detail, forKey: .detail)
        case .inputFile(let content):
            try container.encode("input_file", forKey: .type)
            try container.encode(content.fileId, forKey: .fileId)
        case .outputText(let content):
            try container.encode("output_text", forKey: .type)
            try container.encode(content.text, forKey: .text)
            try container.encodeIfPresent(content.annotations, forKey: .annotations)
        case .refusal(let text):
            try container.encode("refusal", forKey: .type)
            try container.encode(text, forKey: .refusal)
        }
    }
}

// MARK: - Conversation Input Content Part (for creating items)

/// Simplified content part for input operations
public enum ConversationInputContentPart: Codable, Sendable {
    case inputText(String)
    case inputImage(imageUrl: String?, fileId: String?, detail: String?)
    case inputFile(fileId: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, imageUrl, fileId, detail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "input_text":
            let text = try container.decode(String.self, forKey: .text)
            self = .inputText(text)
        case "input_image":
            let imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
            let fileId = try container.decodeIfPresent(String.self, forKey: .fileId)
            let detail = try container.decodeIfPresent(String.self, forKey: .detail)
            self = .inputImage(imageUrl: imageUrl, fileId: fileId, detail: detail)
        case "input_file":
            let fileId = try container.decode(String.self, forKey: .fileId)
            self = .inputFile(fileId: fileId)
        default:
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .inputText(text)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .inputText(let text):
            try container.encode("input_text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .inputImage(let imageUrl, let fileId, let detail):
            try container.encode("input_image", forKey: .type)
            try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
            try container.encodeIfPresent(fileId, forKey: .fileId)
            try container.encodeIfPresent(detail, forKey: .detail)
        case .inputFile(let fileId):
            try container.encode("input_file", forKey: .type)
            try container.encode(fileId, forKey: .fileId)
        }
    }
}

// MARK: - Content Part Types

/// Input text content
public struct ConversationInputTextContent: Codable, Sendable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

/// Input image content
public struct ConversationInputImageContent: Codable, Sendable, Equatable {
    public let imageUrl: String?
    public let fileId: String?
    public let detail: String?

    public init(imageUrl: String? = nil, fileId: String? = nil, detail: String? = nil) {
        self.imageUrl = imageUrl
        self.fileId = fileId
        self.detail = detail
    }
}

/// Input file content
public struct ConversationInputFileContent: Codable, Sendable, Equatable {
    public let fileId: String

    public init(fileId: String) {
        self.fileId = fileId
    }
}

/// Output text content with optional annotations
public struct ConversationOutputTextContent: Codable, Sendable, Equatable {
    public let text: String
    public let annotations: [ConversationAnnotation]?

    public init(text: String, annotations: [ConversationAnnotation]? = nil) {
        self.text = text
        self.annotations = annotations
    }
}

// MARK: - Conversation Annotation

/// Annotation within conversation output text
public struct ConversationAnnotation: Codable, Sendable, Equatable {
    public let type: String?
    public let text: String?
    public let startIndex: Int?
    public let endIndex: Int?
    public let url: String?
    public let title: String?
    public let fileId: String?
    public let fileCitation: FileCitation?

    public init(
        type: String? = nil,
        text: String? = nil,
        startIndex: Int? = nil,
        endIndex: Int? = nil,
        url: String? = nil,
        title: String? = nil,
        fileId: String? = nil,
        fileCitation: FileCitation? = nil
    ) {
        self.type = type
        self.text = text
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.url = url
        self.title = title
        self.fileId = fileId
        self.fileCitation = fileCitation
    }

    /// File citation details
    public struct FileCitation: Codable, Sendable, Equatable {
        public let fileId: String?
        public let quote: String?

        public init(fileId: String? = nil, quote: String? = nil) {
            self.fileId = fileId
            self.quote = quote
        }
    }
}

// MARK: - Conversation Item List

/// Paginated list of conversation items
public struct ConversationItemList: Codable, Sendable {
    public let object: String
    public let data: [ConversationItem]
    public let firstId: String?
    public let lastId: String?
    public let hasMore: Bool

    public init(
        object: String = "list",
        data: [ConversationItem],
        firstId: String? = nil,
        lastId: String? = nil,
        hasMore: Bool = false
    ) {
        self.object = object
        self.data = data
        self.firstId = firstId
        self.lastId = lastId
        self.hasMore = hasMore
    }
}

// MARK: - Include Options

/// Options for including additional data in conversation responses
public enum ConversationIncludeOption: String, Codable, Sendable {
    case fileSearchCallResults = "file_search_call.results"
    case webSearchCallResults = "web_search_call.results"
    case codeInterpreterCallOutputs = "code_interpreter_call.outputs"
    case reasoningEncryptedContent = "reasoning.encrypted_content"
    case messageInputImageImageUrl = "message.input_image.image_url"
    case computerCallOutputs = "computer_call.outputs"
}

// MARK: - Request Types (internal)

struct CreateConversationRequest: Codable {
    let items: [ConversationInputItem]?
    let metadata: [String: String]?
}

struct UpdateConversationRequest: Codable {
    let metadata: [String: String]
}

struct CreateItemsRequest: Codable {
    let items: [ConversationInputItem]
}
