//
//  SessionMetadataUpdate.swift
//  AISDK
//
//  Partial update type for session metadata.
//

import Foundation

/// Partial update for session metadata
public struct SessionMetadataUpdate: Codable, Sendable {
    public var title: String?
    public var tags: [String]?
    public var metadata: [String: String]?
    public var status: SessionStatus?

    public init(
        title: String? = nil,
        tags: [String]? = nil,
        metadata: [String: String]? = nil,
        status: SessionStatus? = nil
    ) {
        self.title = title
        self.tags = tags
        self.metadata = metadata
        self.status = status
    }
}
