import Foundation

public enum MissionKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case crossProviderContinuation = "CrossProviderContinuation"
    case toolReasoningChain = "ToolReasoningChain"
    case generativeUICard = "GenerativeUICard"
    case longContextCompaction = "LongContextCompaction"
    case failureRecovery = "FailureRecovery"

    public var id: String { rawValue }
}

public struct MissionCard: Identifiable, Codable, Sendable {
    public let kind: MissionKind
    public let title: String
    public let prompt: String

    public var id: String { kind.id }
}

public enum MissionCatalog {
    public static let all: [MissionCard] = [
        MissionCard(
            kind: .crossProviderContinuation,
            title: "Cross-provider continuation",
            prompt: "Remember this phrase exactly: 'Killgrave remembers purple'. Summarize it in one sentence."
        ),
        MissionCard(
            kind: .toolReasoningChain,
            title: "Tool reasoning chain",
            prompt: "Use tools to compute: ((5 + 3) * 4) - 6, then explain briefly."
        ),
        MissionCard(
            kind: .generativeUICard,
            title: "Generative UI card",
            prompt: """
            Return ONLY valid json-render JSON, no markdown.
            Build a compact dashboard card with:
            - a title text
            - a metric
            - a badge
            """
        ),
        MissionCard(
            kind: .longContextCompaction,
            title: "Long context compaction",
            prompt: "Write 8 short bullet points about tradeoffs in shipping AI apps to mobile."
        ),
        MissionCard(
            kind: .failureRecovery,
            title: "Failure recovery",
            prompt: "Say exactly: Recovery path is healthy."
        )
    ]
}
