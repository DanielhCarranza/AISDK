//
//  VideoAttachmentUtils.swift
//  AISDKCLI
//
//  Helpers for preparing and rendering video attachments
//

import Foundation

struct VideoAttachmentInfo {
    let name: String
    let sizeBytes: Int
    let mimeType: String
    let source: String

    var sizeDescription: String {
        VideoAttachmentUtils.formatBytes(sizeBytes)
    }
}

enum VideoAttachmentUtils {
    static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func mimeType(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "m4v":
            return "video/x-m4v"
        case "webm":
            return "video/webm"
        case "mkv":
            return "video/x-matroska"
        case "avi":
            return "video/x-msvideo"
        default:
            return "video/mp4"
        }
    }

    static func videoInfo(forPath path: String, sizeBytes: Int? = nil, name: String? = nil) -> VideoAttachmentInfo {
        let fileURL = URL(fileURLWithPath: path)
        let resolvedName = name ?? fileURL.lastPathComponent
        let resolvedSize: Int
        if let sizeBytes = sizeBytes {
            resolvedSize = sizeBytes
        } else if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber {
            resolvedSize = size.intValue
        } else {
            resolvedSize = 0
        }

        return VideoAttachmentInfo(
            name: resolvedName,
            sizeBytes: resolvedSize,
            mimeType: mimeType(forPath: path),
            source: path
        )
    }

    static func downloadVideo(from remoteURL: URL, to destinationURL: URL) throws -> VideoAttachmentInfo {
        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultError: Error?

        let task = URLSession.shared.dataTask(with: remoteURL) { data, response, error in
            if let error = error {
                resultError = error
            } else if let httpResponse = response as? HTTPURLResponse,
                      !(200...299).contains(httpResponse.statusCode) {
                resultError = NSError(
                    domain: "VideoDownload",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode) downloading video"]
                )
            } else {
                resultData = data
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let error = resultError {
            throw error
        }
        guard let data = resultData, !data.isEmpty else {
            throw NSError(
                domain: "VideoDownload",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No data received from \(remoteURL.absoluteString)"]
            )
        }

        try data.write(to: destinationURL, options: .atomic)
        return VideoAttachmentInfo(
            name: destinationURL.lastPathComponent,
            sizeBytes: data.count,
            mimeType: mimeType(forPath: destinationURL.path),
            source: destinationURL.path
        )
    }

    static func renderAttachmentBox(for info: VideoAttachmentInfo) -> String {
        let lines = [
            "📹 \(info.name)",
            "Size: \(info.sizeDescription) │ Format: \(info.mimeType)",
            "Source: \(info.source)"
        ]

        let contentWidth = lines.map { ANSIStyles.stripANSI($0).count }.max() ?? 0
        let title = " Video Attached "
        let innerWidth = max(contentWidth, title.count)
        let totalWidth = innerWidth + 4
        let dashCount = max(0, totalWidth - title.count - 3)
        var result = "┌─" + title + String(repeating: "─", count: dashCount) + "┐\n"

        for line in lines {
            let stripped = ANSIStyles.stripANSI(line)
            let padding = totalWidth - stripped.count - 4
            result += "│ \(line)\(String(repeating: " ", count: max(0, padding))) │\n"
        }

        result += "└" + String(repeating: "─", count: totalWidth - 2) + "┘"
        return result
    }
}
