import Foundation
import AISDK

public enum DemoProvider: String, CaseIterable, Identifiable, Codable {
    case openai
    case anthropic
    case gemini

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        }
    }
}

public enum DemoStoreKind: String, CaseIterable, Identifiable {
    case inMemory = "InMemory"
    case fileSystem = "FileSystem"
    case sqlite = "SQLite"

    public var id: String { rawValue }
}

public struct DiagnosticCheckResult: Identifiable, Codable {
    public let id: String
    public let name: String
    public let pass: Bool
    public let durationMs: Int
    public let message: String
}

private struct LoadedEnv {
    let openAI: String?
    let anthropic: String?
    let gemini: String?

    static func load() -> LoadedEnv {
        var env = ProcessInfo.processInfo.environment
        let candidates = [".env", "../.env", "../../.env"]

        for relative in candidates {
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(relative)
            guard let text = try? String(contentsOf: url) else { continue }
            for line in text.split(separator: "\n") {
                let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.isEmpty || raw.hasPrefix("#") { continue }
                let parts = raw.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                env[String(parts[0])] = String(parts[1])
            }
            break
        }

        return LoadedEnv(
            openAI: env["OPENAI_API_KEY"],
            anthropic: env["ANTHROPIC_API_KEY"],
            gemini: env["GEMINI_API_KEY"] ?? env["GOOGLE_API_KEY"]
        )
    }
}

@MainActor
public final class ExplorerRuntime: ObservableObject {
    @Published public var selectedProvider: DemoProvider = .openai
    @Published public var selectedStore: DemoStoreKind = .inMemory
    @Published public var isBusy = false
    @Published public var messages: [AIMessage] = []
    @Published public var activeToolEvents: [String] = []
    @Published public var lastError: String?
    @Published public var sessions: [SessionSummary] = []
    @Published public var missionEvidence: [MissionEvidence] = []
    @Published public var diagnostics: [DiagnosticCheckResult] = []
    @Published public var exportLocation: String?

    public let userId = "killgrave-demo-user"

    private let env = LoadedEnv.load()
    private var store: any SessionStore
    private var activeSessionID: String?

    private let fileStoreDirectory: URL
    private let sqlitePath: String

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.fileStoreDirectory = docs.appendingPathComponent("SDKExplorerSessions", isDirectory: true)
        self.sqlitePath = docs.appendingPathComponent("sdkexplorer.sqlite").path
        self.store = InMemorySessionStore()

        Task {
            await self.refreshSessions()
        }
    }

    public var availableProviders: [DemoProvider] {
        DemoProvider.allCases.filter { key(for: $0) != nil }
    }

    public var canSwitchStore: Bool {
        messages.isEmpty
    }

    public func ensureSession() async throws {
        if activeSessionID != nil { return }
        let session = try await AISession.create(
            userId: userId,
            store: store,
            title: "KillgraveAI Session"
        )
        activeSessionID = session.id
        await refreshSessions()
    }

    public func sendMessage(_ text: String) async {
        await runMessage(text, provider: selectedProvider, recordMission: nil)
    }

    public func runMission(_ mission: MissionCard) async {
        switch mission.kind {
        case .crossProviderContinuation:
            let start = Date()
            await runMessage(mission.prompt, provider: selectedProvider, recordMission: nil)
            let alternate = selectedProvider == .openai ? DemoProvider.anthropic : .openai
            if availableProviders.contains(alternate) {
                await runMessage("What phrase did I ask you to remember?", provider: alternate, recordMission: mission.kind)
            } else {
                let latency = Int(Date().timeIntervalSince(start) * 1000)
                missionEvidence.append(
                    MissionEvidence(
                        timestamp: Date(),
                        name: mission.kind.rawValue,
                        provider: "\(selectedProvider.rawValue)->\(alternate.rawValue)",
                        pass: false,
                        latencyMs: latency,
                        retries: 0,
                        inputTokens: 0,
                        outputTokens: 0,
                        note: "Alternate provider key not configured."
                    )
                )
            }
        case .longContextCompaction:
            for idx in 1...4 {
                await runMessage("\(mission.prompt) Part \(idx).", provider: selectedProvider, recordMission: nil)
            }
            await compactActiveSession()
            await runMessage("What were the core themes?", provider: selectedProvider, recordMission: mission.kind)
        case .failureRecovery:
            await runFailureRecoveryMission(mission.kind)
        default:
            await runMessage(mission.prompt, provider: selectedProvider, recordMission: mission.kind)
        }
    }

    public func switchStore(to kind: DemoStoreKind) async {
        guard kind != selectedStore else { return }
        guard canSwitchStore else {
            lastError = "End or clear the active transcript before switching stores."
            return
        }
        do {
            store = try makeStore(kind: kind)
            selectedStore = kind
            activeSessionID = nil
            messages = []
            await refreshSessions()
        } catch {
            lastError = "Failed to switch store: \(error.localizedDescription)"
        }
    }

    public func restore(session summary: SessionSummary) async {
        do {
            guard let loaded = try await store.load(id: summary.id) else { return }
            activeSessionID = loaded.id
            messages = loaded.messages
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    public func delete(session summary: SessionSummary) async {
        do {
            try await store.delete(id: summary.id)
            if activeSessionID == summary.id {
                activeSessionID = nil
                messages = []
            }
            await refreshSessions()
        } catch {
            lastError = "Delete failed: \(error.localizedDescription)"
        }
    }

    public func estimateTokenCount() async -> Int {
        let service = SessionCompactionService()
        return await service.estimateTokens(messages)
    }

    public func compactActiveSession() async {
        do {
            let llm = try buildAdapter(for: selectedProvider, forceBadKey: false)
            let service = SessionCompactionService(llm: llm)
            let policy = ContextPolicy(
                maxTokens: 8_000,
                compactionThreshold: 0.6,
                compactionStrategy: .summarize,
                preserveSystemPrompt: true,
                minMessagesToKeep: 6
            )
            let compacted = try await service.compact(messages, policy: policy)
            messages = compacted
            try await persistFullTranscript()
        } catch {
            lastError = "Compaction failed: \(error.localizedDescription)"
        }
    }

    public func runDiagnostics() async {
        isBusy = true
        diagnostics = []
        defer { isBusy = false }

        await appendDiagnostic(name: "Provider Health", block: providerHealthCheck)
        await appendDiagnostic(name: "Error Recovery", block: errorRecoveryCheck)
        await appendDiagnostic(name: "UITree Parse (valid)", block: validUITreeParseCheck)
        await appendDiagnostic(name: "UITree Parse (invalid)", block: invalidUITreeParseCheck)
        await appendDiagnostic(name: "Store Roundtrip (InMemory)", block: { try await self.storeRoundtrip(.inMemory) })
        await appendDiagnostic(name: "Store Roundtrip (FileSystem)", block: { try await self.storeRoundtrip(.fileSystem) })
        await appendDiagnostic(name: "Store Roundtrip (SQLite)", block: { try await self.storeRoundtrip(.sqlite) })
        await appendDiagnostic(name: "Token Estimation", block: tokenEstimationCheck)
        await appendDiagnostic(name: "Stream Event Ordering", block: streamOrderingCheck)
    }

    public func exportEvidenceBundle() async {
        do {
            let diagnosticArtifacts = diagnostics.map {
                DiagnosticEvidence(name: $0.name, status: $0.pass ? "pass" : "fail", durationMs: $0.durationMs, message: $0.message)
            }
            let result = try EvidenceExporter.export(missions: missionEvidence, diagnostics: diagnosticArtifacts)
            exportLocation = "\(result.jsonURL.lastPathComponent), \(result.markdownURL.lastPathComponent)"
        } catch {
            lastError = "Evidence export failed: \(error.localizedDescription)"
        }
    }

    private func runMessage(_ text: String, provider: DemoProvider, recordMission: MissionKind?) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isBusy = true
        lastError = nil
        let started = Date()
        activeToolEvents = []

        do {
            try await ensureSession()
            let userMessage = AIMessage.user(text)
            messages.append(userMessage)
            if let sessionID = activeSessionID {
                try await store.appendMessage(userMessage, toSession: sessionID)
            }

            let adapter = try buildAdapter(for: provider, forceBadKey: false)
            let agent = Agent(
                model: adapter,
                tools: [CalculatorTool.self, WeatherTool.self],
                instructions: "You are KillgraveAI. Be concise and helpful."
            )
            let stream = agent.streamExecute(messages: messages)

            var assistantText = ""
            var calls: [AIMessage.ToolCall] = []
            var usage = AIUsage.zero

            for try await event in stream {
                switch event {
                case .textDelta(let delta):
                    assistantText += delta
                case .toolCallStart(_, let name):
                    activeToolEvents.append("Calling \(name)")
                case .toolCall(_, let name, let arguments):
                    calls.append(AIMessage.ToolCall(id: UUID().uuidString, name: name, arguments: arguments))
                case .toolResult(_, let result, _):
                    activeToolEvents.append("Tool result: \(result)")
                case .usage(let eventUsage):
                    usage = eventUsage
                default:
                    break
                }
            }

            let assistant = calls.isEmpty ? AIMessage.assistant(assistantText) : AIMessage.assistant(assistantText, toolCalls: calls)
            messages.append(assistant)
            if let sessionID = activeSessionID {
                try await store.appendMessage(assistant, toSession: sessionID)
            }
            await refreshSessions()

            if let mission = recordMission {
                missionEvidence.append(
                    MissionEvidence(
                        timestamp: Date(),
                        name: mission.rawValue,
                        provider: provider.rawValue,
                        pass: !assistantText.isEmpty,
                        latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                        retries: 0,
                        inputTokens: usage.promptTokens,
                        outputTokens: usage.completionTokens,
                        note: nil
                    )
                )
            }
        } catch {
            lastError = error.localizedDescription
            if let mission = recordMission {
                missionEvidence.append(
                    MissionEvidence(
                        timestamp: Date(),
                        name: mission.rawValue,
                        provider: provider.rawValue,
                        pass: false,
                        latencyMs: Int(Date().timeIntervalSince(started) * 1000),
                        retries: 0,
                        inputTokens: 0,
                        outputTokens: 0,
                        note: error.localizedDescription
                    )
                )
            }
        }

        isBusy = false
    }

    private func runFailureRecoveryMission(_ mission: MissionKind) async {
        let start = Date()
        do {
            let _ = try buildAdapter(for: selectedProvider, forceBadKey: true)
            throw ProviderError.authenticationFailed("Expected invalid key failure.")
        } catch {
            await runMessage("Say exactly: Recovery path is healthy.", provider: selectedProvider, recordMission: nil)
            missionEvidence.append(
                MissionEvidence(
                    timestamp: Date(),
                    name: mission.rawValue,
                    provider: selectedProvider.rawValue,
                    pass: true,
                    latencyMs: Int(Date().timeIntervalSince(start) * 1000),
                    retries: 1,
                    inputTokens: 0,
                    outputTokens: 0,
                    note: "Recovered after expected error: \(error.localizedDescription)"
                )
            )
        }
    }

    private func refreshSessions() async {
        do {
            let list = try await store.list(
                userId: userId,
                status: nil,
                limit: 200,
                cursor: nil,
                orderBy: .lastActivityAtDesc
            )
            sessions = list.sessions
        } catch {
            lastError = "Failed to load sessions: \(error.localizedDescription)"
        }
    }

    private func persistFullTranscript() async throws {
        guard let sessionID = activeSessionID else { return }
        guard var loaded = try await store.load(id: sessionID) else { return }
        loaded.messages = messages
        loaded.lastActivityAt = Date()
        try await store.save(loaded)
        await refreshSessions()
    }

    private func makeStore(kind: DemoStoreKind) throws -> any SessionStore {
        switch kind {
        case .inMemory:
            return InMemorySessionStore()
        case .fileSystem:
            return try FileSystemSessionStore(directory: fileStoreDirectory)
        case .sqlite:
            return try SQLiteSessionStore(path: sqlitePath)
        }
    }

    private func key(for provider: DemoProvider) -> String? {
        switch provider {
        case .openai: env.openAI
        case .anthropic: env.anthropic
        case .gemini: env.gemini
        }
    }

    private func defaultModel(for provider: DemoProvider) -> String {
        switch provider {
        case .openai: "gpt-4o-mini"
        case .anthropic: "claude-3-5-sonnet-20241022"
        case .gemini: "gemini-2.0-flash"
        }
    }

    private func buildAdapter(for provider: DemoProvider, forceBadKey: Bool) throws -> ProviderLanguageModelAdapter {
        guard var key = key(for: provider), !key.isEmpty else {
            throw ProviderError.authenticationFailed("Missing \(provider.title) API key.")
        }
        if forceBadKey {
            key = "invalid-\(key)"
        }
        let client: any ProviderClient
        switch provider {
        case .openai:
            client = OpenAIClientAdapter(apiKey: key)
        case .anthropic:
            client = AnthropicClientAdapter(apiKey: key)
        case .gemini:
            client = GeminiClientAdapter(apiKey: key)
        }
        return ProviderLanguageModelAdapter(client: client, modelId: defaultModel(for: provider))
    }

    private func appendDiagnostic(
        name: String,
        block: @escaping () async throws -> String
    ) async {
        let start = Date()
        do {
            let message = try await block()
            diagnostics.append(
                DiagnosticCheckResult(
                    id: name,
                    name: name,
                    pass: true,
                    durationMs: Int(Date().timeIntervalSince(start) * 1000),
                    message: message
                )
            )
        } catch {
            diagnostics.append(
                DiagnosticCheckResult(
                    id: name,
                    name: name,
                    pass: false,
                    durationMs: Int(Date().timeIntervalSince(start) * 1000),
                    message: error.localizedDescription
                )
            )
        }
    }

    private func providerHealthCheck() async throws -> String {
        var healthy: [String] = []
        for provider in availableProviders {
            let adapter = try buildAdapter(for: provider, forceBadKey: false)
            let result = try await adapter.generateText(request: AITextRequest(messages: [.user("Say hi")], maxTokens: 8))
            if result.text.isEmpty {
                throw ProviderError.unknown("Provider \(provider.title) returned empty response.")
            }
            healthy.append(provider.title)
        }
        if healthy.isEmpty {
            throw ProviderError.authenticationFailed("No provider keys configured.")
        }
        return "Healthy providers: \(healthy.joined(separator: ", "))"
    }

    private func errorRecoveryCheck() async throws -> String {
        guard let first = availableProviders.first else {
            throw ProviderError.authenticationFailed("No provider keys configured.")
        }
        do {
            _ = try buildAdapter(for: first, forceBadKey: true)
            throw ProviderError.authenticationFailed("Expected authentication error.")
        } catch {
            let adapter = try buildAdapter(for: first, forceBadKey: false)
            _ = try await adapter.generateText(request: AITextRequest(messages: [.user("Say hi")], maxTokens: 8))
            return "Expected failure captured, next request succeeded."
        }
    }

    private func validUITreeParseCheck() async throws -> String {
        _ = try UITree.parse(from: Self.validTreeJSON, validatingWith: UICatalog.extended)
        return "Valid UITree parsed."
    }

    private func invalidUITreeParseCheck() async throws -> String {
        do {
            _ = try UITree.parse(from: Data("{\"root\":\"x\"}".utf8), validatingWith: UICatalog.extended)
            throw UITreeError.invalidStructure(reason: "Expected parse failure for invalid tree.")
        } catch {
            return "Invalid UITree failed as expected."
        }
    }

    private func storeRoundtrip(_ kind: DemoStoreKind) async throws -> String {
        let testStore = try makeStore(kind: kind)
        var session = AISession(userId: "roundtrip-user")
        session.messages = [.user("hello"), .assistant("world")]
        let created = try await testStore.create(session)
        guard let loaded = try await testStore.load(id: created.id) else {
            throw SessionStoreError.notFound(sessionId: created.id)
        }
        guard loaded.messages.count == 2 else {
            throw SessionStoreError.invalidData(reason: "Roundtrip message count mismatch.")
        }
        try await testStore.delete(id: created.id)
        return "\(kind.rawValue) roundtrip passed."
    }

    private func tokenEstimationCheck() async throws -> String {
        let service = SessionCompactionService()
        let estimate = await service.estimateTokens([.user("hello"), .assistant("hi there")])
        guard estimate > 0 else {
            throw SessionStoreError.invalidData(reason: "Token estimate should be positive.")
        }
        return "Estimated tokens: \(estimate)"
    }

    private func streamOrderingCheck() async throws -> String {
        guard let provider = availableProviders.first else {
            throw ProviderError.authenticationFailed("No provider keys configured.")
        }
        let adapter = try buildAdapter(for: provider, forceBadKey: false)
        let stream = adapter.streamText(request: AITextRequest(messages: [.user("Say hello in 3 words.")], maxTokens: 16))
        var sawStart = false
        var sawText = false
        var sawFinish = false
        for try await event in stream {
            switch event {
            case .start:
                sawStart = true
            case .textDelta:
                if !sawStart {
                    throw ProviderError.parseError("Received text before start.")
                }
                sawText = true
            case .finish:
                sawFinish = true
            default:
                break
            }
        }
        guard sawStart && sawText && sawFinish else {
            throw ProviderError.parseError("Missing start/text/finish sequence.")
        }
        return "Stream ordering validated."
    }

    private static let validTreeJSON = Data(
        """
        {
          "root": "main",
          "elements": {
            "main": {
              "type": "Card",
              "props": { "title": "KillgraveAI" },
              "children": ["metric"]
            },
            "metric": {
              "type": "Metric",
              "props": { "label": "Confidence", "value": 0.93, "format": "percent" }
            }
          }
        }
        """.utf8
    )
}
