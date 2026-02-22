//
//  OpenAICompactionModels.swift
//  AISDK
//
//  Compaction models for OpenAI Responses API
//  Supports efficient context window management for long conversations
//

import Foundation

// MARK: - Compact Request

/// Request for compacting a conversation's context window
public struct CompactRequest: Encodable, @unchecked Sendable {
    /// The model to use for compaction (should match conversation model)
    public let model: String

    /// Input to compact (messages, tool calls, etc.)
    public var input: ResponseInput?

    /// System instructions for guiding compaction
    public var instructions: String?

    /// Previous response ID to compact from (uses conversation history)
    public var previousResponseId: String?

    /// Optional metadata to preserve
    public var metadata: [String: String]?

    public init(
        model: String,
        input: ResponseInput? = nil,
        instructions: String? = nil,
        previousResponseId: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.model = model
        self.input = input
        self.instructions = instructions
        self.previousResponseId = previousResponseId
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case instructions
        case previousResponseId = "previous_response_id"
        case metadata
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(model, forKey: .model)

        if let input = input {
            try container.encode(input, forKey: .input)
        }

        if let instructions = instructions {
            try container.encode(instructions, forKey: .instructions)
        }

        if let previousResponseId = previousResponseId {
            try container.encode(previousResponseId, forKey: .previousResponseId)
        }

        if let metadata = metadata, !metadata.isEmpty {
            try container.encode(metadata, forKey: .metadata)
        }
    }
}

// MARK: - Compact Response

/// Response from compacting a conversation
public struct CompactResponse: Codable, Sendable {
    /// Unique ID for this compaction
    public let id: String

    /// Object type ("response.compact")
    public let object: String

    /// Unix timestamp of creation
    public let createdAt: Int

    /// Compacted output items (encrypted)
    public let output: [CompactedOutputItem]

    /// Token usage for the compaction operation
    public let usage: ResponseUsage

    /// Status of the compaction
    public let status: CompactStatus

    public init(
        id: String,
        object: String = "response.compact",
        createdAt: Int,
        output: [CompactedOutputItem],
        usage: ResponseUsage,
        status: CompactStatus
    ) {
        self.id = id
        self.object = object
        self.createdAt = createdAt
        self.output = output
        self.usage = usage
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id, object, output, usage, status
        case createdAt = "created_at"
    }
}

// MARK: - Compact Status

/// Status of a compaction operation
public enum CompactStatus: String, Codable, Sendable {
    case completed
    case failed
    case inProgress = "in_progress"
}

// MARK: - Compacted Output Item

/// A compacted output item containing encrypted content
public struct CompactedOutputItem: Codable, Sendable, Equatable {
    /// Item type (e.g., "compaction")
    public let type: String

    /// Unique ID for this item
    public let id: String

    /// Encrypted/compressed content (opaque, ZDR-compatible)
    public let encryptedContent: String?

    /// Summary of what was compacted (for debugging/logging)
    public let summary: String?

    /// Number of items that were compacted
    public let compactedItemCount: Int?

    /// Original token count before compaction
    public let originalTokenCount: Int?

    /// Token count after compaction
    public let compactedTokenCount: Int?

    public init(
        type: String = "compaction",
        id: String,
        encryptedContent: String? = nil,
        summary: String? = nil,
        compactedItemCount: Int? = nil,
        originalTokenCount: Int? = nil,
        compactedTokenCount: Int? = nil
    ) {
        self.type = type
        self.id = id
        self.encryptedContent = encryptedContent
        self.summary = summary
        self.compactedItemCount = compactedItemCount
        self.originalTokenCount = originalTokenCount
        self.compactedTokenCount = compactedTokenCount
    }

    enum CodingKeys: String, CodingKey {
        case type, id, summary
        case encryptedContent = "encrypted_content"
        case compactedItemCount = "compacted_item_count"
        case originalTokenCount = "original_token_count"
        case compactedTokenCount = "compacted_token_count"
    }
}

// MARK: - Compacted Conversation

/// Result of conversation compaction, can be used in subsequent requests
public struct CompactedConversation: Sendable, Equatable {
    /// Unique ID for this compaction
    public let id: String

    /// Compacted items to use in subsequent requests
    public let compactedItems: [CompactedOutputItem]

    /// Token usage for the compaction operation
    public let usage: AIUsage

    /// Original token count before compaction
    public let originalTokenCount: Int?

    /// Token count after compaction
    public let compactedTokenCount: Int?

    /// Compression ratio achieved (if available)
    /// Returns the percentage of tokens saved (e.g., 0.7 means 70% reduction)
    public var compressionRatio: Double? {
        guard let original = originalTokenCount, let compacted = compactedTokenCount, original > 0 else {
            return nil
        }
        return Double(original - compacted) / Double(original)
    }

    /// Token savings from compaction
    public var tokensSaved: Int? {
        guard let original = originalTokenCount, let compacted = compactedTokenCount else {
            return nil
        }
        return original - compacted
    }

    public init(
        id: String,
        compactedItems: [CompactedOutputItem],
        usage: AIUsage,
        originalTokenCount: Int? = nil,
        compactedTokenCount: Int? = nil
    ) {
        self.id = id
        self.compactedItems = compactedItems
        self.usage = usage
        self.originalTokenCount = originalTokenCount
        self.compactedTokenCount = compactedTokenCount
    }
}

// MARK: - Compaction Input Item Reference

/// Reference to a compacted item for use in subsequent requests
public struct CompactionItemReference: Encodable, Sendable {
    /// The type, always "item_reference"
    public let type: String = "item_reference"

    /// The ID of the compacted item to reference
    public let id: String

    public init(id: String) {
        self.id = id
    }
}
