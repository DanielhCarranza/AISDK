import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct MissionEvidence: Codable, Identifiable {
    public var id: String { "\(name)-\(provider)-\(timestamp.timeIntervalSince1970)" }
    public let timestamp: Date
    public let name: String
    public let provider: String
    public let pass: Bool
    public let latencyMs: Int
    public let retries: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let note: String?
}

public struct DiagnosticEvidence: Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let status: String
    public let durationMs: Int
    public let message: String
}

public struct EvidenceBundle: Codable {
    public let timestamp: String
    public let appVersion: String
    public let device: String
    public let osVersion: String
    public let missions: [MissionEvidence]
    public let diagnostics: [DiagnosticEvidence]
}

public enum EvidenceExporter {
    public static func export(
        missions: [MissionEvidence],
        diagnostics: [DiagnosticEvidence]
    ) throws -> (jsonURL: URL, markdownURL: URL) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeStamp = timestamp.replacingOccurrences(of: ":", with: "-")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let evidenceDir = docs.appendingPathComponent("SDKExplorerEvidence", isDirectory: true)
        try FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)

        let bundle = EvidenceBundle(
            timestamp: timestamp,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            device: deviceName(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            missions: missions,
            diagnostics: diagnostics
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonURL = evidenceDir.appendingPathComponent("sdk-explorer-evidence-\(safeStamp).json")
        let markdownURL = evidenceDir.appendingPathComponent("sdk-explorer-evidence-\(safeStamp).md")

        let data = try encoder.encode(bundle)
        try data.write(to: jsonURL, options: .atomic)

        let md = markdown(for: bundle)
        try md.write(to: markdownURL, atomically: true, encoding: .utf8)
        return (jsonURL, markdownURL)
    }

    private static func markdown(for bundle: EvidenceBundle) -> String {
        var lines: [String] = []
        lines.append("# SDK Explorer Evidence")
        lines.append("")
        lines.append("- Timestamp: \(bundle.timestamp)")
        lines.append("- App Version: \(bundle.appVersion)")
        lines.append("- Device: \(bundle.device)")
        lines.append("- OS: \(bundle.osVersion)")
        lines.append("")
        lines.append("## Missions")
        if bundle.missions.isEmpty {
            lines.append("- No mission runs recorded.")
        } else {
            for mission in bundle.missions {
                lines.append("- \(mission.name) | provider=\(mission.provider) | pass=\(mission.pass) | latencyMs=\(mission.latencyMs) | tokens=\(mission.inputTokens)/\(mission.outputTokens)")
            }
        }
        lines.append("")
        lines.append("## Diagnostics")
        if bundle.diagnostics.isEmpty {
            lines.append("- No diagnostic runs recorded.")
        } else {
            for check in bundle.diagnostics {
                lines.append("- \(check.name) | status=\(check.status) | durationMs=\(check.durationMs) | \(check.message)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func deviceName() -> String {
        #if canImport(UIKit)
        UIDevice.current.model
        #else
        Host.current().localizedName ?? "Unknown"
        #endif
    }
}
