//
//  SessionExport.swift
//  AISDK
//
//  Session export and import in JSON and Markdown formats.
//

import Foundation

// MARK: - JSON Export/Import

extension AISession {
    /// Export the session as JSON data.
    ///
    /// Uses ISO 8601 date encoding and sorted keys for deterministic output.
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Import a session from JSON data.
    public static func importJSON(_ data: Data) throws -> AISession {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AISession.self, from: data)
    }
}

// MARK: - Markdown Export

extension AISession {
    /// Export the session as human-readable Markdown.
    ///
    /// Includes session metadata, message history with role labels,
    /// and tool call/result formatting.
    public func exportMarkdown() -> String {
        var lines: [String] = []

        // Header
        lines.append("# \(title ?? "Untitled Session")")
        lines.append("")
        lines.append("- **Session ID:** \(id)")
        lines.append("- **User:** \(userId)")
        if let agentId = agentId {
            lines.append("- **Agent:** \(agentId)")
        }
        lines.append("- **Status:** \(status.rawValue)")
        lines.append("- **Created:** \(formatDate(createdAt))")
        lines.append("- **Last Activity:** \(formatDate(lastActivityAt))")
        if let tags = tags, !tags.isEmpty {
            lines.append("- **Tags:** \(tags.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("---")
        lines.append("")

        // Messages
        for message in messages {
            lines.append(formatMessage(message))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func formatMessage(_ message: AIMessage) -> String {
        var parts: [String] = []
        let roleLabel: String

        switch message.role {
        case .system:
            roleLabel = "System"
        case .user:
            roleLabel = "User"
        case .assistant:
            if let agentName = message.agentName {
                roleLabel = "Assistant (\(agentName))"
            } else {
                roleLabel = "Assistant"
            }
        case .tool:
            roleLabel = "Tool Result"
        }

        parts.append("### \(roleLabel)")
        parts.append("")

        // Content
        switch message.content {
        case .text(let text):
            parts.append(text)
        case .parts(let contentParts):
            for part in contentParts {
                switch part {
                case .text(let text):
                    parts.append(text)
                case .image, .imageURL:
                    parts.append("[image]")
                case .audio:
                    parts.append("[audio]")
                case .file(_, let filename, _):
                    parts.append("[file: \(filename)]")
                case .video, .videoURL:
                    parts.append("[video]")
                @unknown default:
                    parts.append("[attachment]")
                }
            }
        }

        // Tool calls
        if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
            parts.append("")
            parts.append("**Tool Calls:**")
            for call in toolCalls {
                parts.append("- `\(call.name)` (id: \(call.id))")
                if !call.arguments.isEmpty {
                    parts.append("  ```json")
                    parts.append("  \(call.arguments)")
                    parts.append("  ```")
                }
            }
        }

        // Tool call ID (for tool result messages)
        if let toolCallId = message.toolCallId {
            parts.insert("> Response to tool call: \(toolCallId)", at: 2)
            parts.insert("", at: 3)
        }

        return parts.joined(separator: "\n")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - Bulk Export

extension SessionStore {
    /// Export all sessions for a user as JSON data.
    ///
    /// Note: For stores with many sessions, this loads all sessions into memory.
    /// Consider paginated export for large datasets.
    public func exportAll(userId: String) async throws -> Data {
        var allSessions: [AISession] = []
        var cursor: String? = nil

        repeat {
            let result = try await list(
                userId: userId,
                status: nil,
                limit: 100,
                cursor: cursor,
                orderBy: .createdAtAsc
            )

            // Load full sessions (list returns summaries)
            for summary in result.sessions {
                if let session = try await load(id: summary.id) {
                    allSessions.append(session)
                }
            }

            cursor = result.nextCursor
        } while cursor != nil

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(allSessions)
    }
}
