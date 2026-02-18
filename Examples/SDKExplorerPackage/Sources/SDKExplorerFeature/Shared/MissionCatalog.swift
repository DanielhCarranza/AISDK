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
            prompt: "Use the calculator tool step by step: first compute 5 + 3, then multiply that result by 4, then subtract 6. Show each step."
        ),
        MissionCard(
            kind: .generativeUICard,
            title: "Generative UI card",
            prompt: """
            Build me a villain HQ dashboard as a generative UI card. Include: \
            a Card titled "Killgrave Command Center" with style "elevated", \
            containing a vertical Stack with: a Metric showing revenue of 2500000 in currency format with trend up and change 18.5, \
            a Badge saying "All Systems Online" with variant success, \
            and a Progress bar at 0.87 labeled "World Domination" with color accent and showValue true. \
            Return ONLY the raw json-render JSON object, no markdown, no explanation.
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
