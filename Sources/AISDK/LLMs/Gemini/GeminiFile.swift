//
//  GeminiFile.swift
//
//
//  Created by Lou Zell on 10/24/24.
//

import Foundation

public struct GeminiFile: Codable, Sendable {
    public let createTime: String?
    public let expirationTime: String?
    public let mimeType: String?
    public let name: String?
    public let sha256Hash: String?
    public let sizeBytes: String?
    public let state: State
    public let updateTime: String?
    public let uri: URL
    public let videoMetadata: VideoMetadata?
    public let error: FileError?

    public init(
        createTime: String? = nil,
        expirationTime: String? = nil,
        mimeType: String? = nil,
        name: String? = nil,
        sha256Hash: String? = nil,
        sizeBytes: String? = nil,
        state: State,
        updateTime: String? = nil,
        uri: URL,
        videoMetadata: VideoMetadata? = nil,
        error: FileError? = nil
    ) {
        self.createTime = createTime
        self.expirationTime = expirationTime
        self.mimeType = mimeType
        self.name = name
        self.sha256Hash = sha256Hash
        self.sizeBytes = sizeBytes
        self.state = state
        self.updateTime = updateTime
        self.uri = uri
        self.videoMetadata = videoMetadata
        self.error = error
    }
}

// MARK: - GeminiFile.State
extension GeminiFile {
    public enum State: String, Codable, Sendable {
        case processing = "PROCESSING"
        case active = "ACTIVE"
        case failed = "FAILED"
    }
}

// MARK: - GeminiFile.FileError
extension GeminiFile {
    public struct FileError: Codable, Sendable {
        public let code: Int?
        public let message: String?
        public let status: String?

        public init(code: Int? = nil, message: String? = nil, status: String? = nil) {
            self.code = code
            self.message = message
            self.status = status
        }
    }
}

// MARK: - GeminiFile.VideoMetadata
extension GeminiFile {
    public struct VideoMetadata: Codable, Sendable {
        public let videoDuration: String

        public init(videoDuration: String) {
            self.videoDuration = videoDuration
        }
    }
}
