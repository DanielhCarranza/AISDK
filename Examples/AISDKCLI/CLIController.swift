//
//  CLIController.swift
//  AISDKCLI
//
//  Main orchestrator for the CLI application
//

import Foundation
import AISDK

/// Main CLI controller that orchestrates all components
class CLIController {
    // MARK: - Properties

    /// CLI options from command line
    private let options: CLIOptions

    /// Runtime configuration (mutable during session)
    private let runtimeConfig: RuntimeConfig

    /// Provider client for API calls
    private var client: (any ProviderClient)?

    /// Session manager for conversation state
    private let sessionManager: SessionManager

    /// Command handler for slash commands
    private let commandHandler: CommandHandler

    /// Input reader for user input
    private let inputReader: InputReader

    /// Stream renderer for AI responses
    private let streamRenderer: StreamRenderer

    /// Reasoning renderer for thinking display
    private let reasoningRenderer: ReasoningRenderer

    /// Tool call renderer
    private let toolRenderer: ToolCallRenderer

    /// Terminal UI renderer
    private let uiRenderer: TerminalUIRenderer

    /// SpecStream compiler for progressive UI rendering
    private var specCompiler = SpecStreamCompiler()

    /// Built-in tool types
    private var builtInTools: [Tool.Type] = []

    /// Whether the main loop should continue
    private var shouldContinue = true

    // MARK: - Initialization

    init(options: CLIOptions) {
        self.options = options
        self.runtimeConfig = RuntimeConfig(from: options)

        // Initialize components
        self.sessionManager = SessionManager(systemPrompt: runtimeConfig.systemPrompt)
        self.commandHandler = CommandHandler()
        self.inputReader = InputReader(username: "You")
        self.streamRenderer = StreamRenderer()
        self.reasoningRenderer = ReasoningRenderer(mode: .inline)
        self.toolRenderer = ToolCallRenderer()
        self.uiRenderer = TerminalUIRenderer()

        // Wire up references
        self.commandHandler.sessionManager = sessionManager
        self.commandHandler.runtimeConfig = runtimeConfig
        self.commandHandler.provider = options.provider
        self.commandHandler.onProviderConfigChanged = { [weak self] in
            self?.refreshProviderClient()
        }

        // Initialize built-in tools
        if runtimeConfig.toolsEnabled {
            var tools: [Tool.Type] = [
                WeatherTool.self,
                CalculatorTool.self,
                WebSearchTool.self,
                DashboardStreamTool.self,
                StateChangeDemoTool.self,
            ]
            #if canImport(SwiftUI)
            tools.append(WeatherDashboardTool.self)
            #endif
            self.builtInTools = tools
        }
    }

    // MARK: - Main Entry Point

    /// Run the CLI
    func run() async {
        // Initialize provider client
        client = createClient()
        if client == nil {
            print(ANSIStyles.error("Provider client could not be initialized. Exiting."))
            return
        }

        // Select model if not pre-specified
        if runtimeConfig.currentModel == nil {
            await selectModel()
        }

        guard runtimeConfig.currentModel != nil else {
            print(ANSIStyles.error("No model selected. Exiting."))
            return
        }

        // Show initial status
        printStatus()

        // Prepare any pending video from CLI options
        prepareInitialVideoAttachmentIfNeeded()

        // Run main chat loop
        await runChatLoop()

        // Cleanup
        print("\n" + ANSIStyles.info("Session ended."))
        printFinalStats()
    }

    // MARK: - Provider Setup

    private func createClient() -> (any ProviderClient)? {
        switch options.provider {
        case .openrouter:
            guard let client = createOpenRouterClient() else {
                print(ANSIStyles.error("Missing OPENROUTER_API_KEY"))
                return nil
            }
            return client

        case .litellm:
            return createLiteLLMClient()

        case .openai:
            guard let client = createOpenAIClient() else {
                print(ANSIStyles.error("Missing OPENAI_API_KEY"))
                return nil
            }
            return client
        case .anthropic:
            return createAnthropicClient()
        case .gemini:
            guard let client = createGeminiClient() else {
                print(ANSIStyles.error("Missing GOOGLE_API_KEY"))
                return nil
            }
            return client
        }
    }

    private func createOpenAIClient() -> (any ProviderClient)? {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            return nil
        }
        // Use OpenAIClientAdapter for direct OpenAI API testing
        return OpenAIClientAdapter(apiKey: apiKey)
    }

    private func createGeminiClient() -> GeminiClientAdapter? {
        guard let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"], !apiKey.isEmpty else {
            return nil
        }
        return GeminiClientAdapter(apiKey: apiKey)
    }

    private func createAnthropicClient() -> (any ProviderClient)? {
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty else {
            print(ANSIStyles.error("Missing ANTHROPIC_API_KEY"))
            return nil
        }

        var betaConfig = BetaConfiguration()
        for feature in runtimeConfig.betaFeatures {
            switch feature {
            case "files-api":
                betaConfig.filesAPI = true
            case "context-1m":
                betaConfig.context1M = true
            case "skills":
                betaConfig.skills = true
            case "mcp-client":
                betaConfig.mcpClient = true
            case "interleaved-thinking":
                betaConfig.interleavedThinking = true
            case "computer-use":
                betaConfig.computerUse = true
            case "code-execution":
                betaConfig.codeExecution = true
            case "output-128k":
                betaConfig.output128k = true
            case "extended-cache-ttl":
                betaConfig.extendedCacheTTL = true
            case "context-management":
                betaConfig.contextManagement = true
            case "token-efficient-tools":
                betaConfig.tokenEfficientTools = true
            default:
                print(ANSIStyles.warning("Unknown beta feature: \(feature)"))
            }
        }

        if runtimeConfig.thinkingEnabled {
            betaConfig.extendedThinking = true
            betaConfig.interleavedThinking = true
        }

        let thinkingBudget = runtimeConfig.thinkingEnabled ? runtimeConfig.thinkingBudget : nil
        return AnthropicClientAdapter(
            apiKey: apiKey,
            betaConfiguration: betaConfig,
            thinkingBudgetOverride: thinkingBudget
        )
    }

    // MARK: - Video Handling

    private func prepareInitialVideoAttachmentIfNeeded() {
        guard let rawInput = runtimeConfig.pendingVideoURL else { return }
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard options.provider == .gemini else {
            print(ANSIStyles.warning("Video is only supported with --provider gemini"))
            runtimeConfig.clearPendingVideo()
            return
        }

        if trimmed.lowercased() == "demo" {
            attachDemoVideo(announce: true)
            return
        }

        let expandedPath = NSString(string: trimmed).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expandedPath) {
            attachLocalVideo(at: expandedPath, announce: true)
            return
        }

        if let remoteURL = URL(string: trimmed),
           let scheme = remoteURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            runtimeConfig.pendingVideoURL = trimmed
            runtimeConfig.pendingVideoDisplayName = remoteURL.lastPathComponent.isEmpty ? trimmed : remoteURL.lastPathComponent
            print(ANSIStyles.success("Video attached: \(trimmed)"))
            print(ANSIStyles.dim("This video will be downloaded and played before sending."))
            return
        }

        print(ANSIStyles.error("Video not found. Provide a valid URL or local file path."))
        runtimeConfig.clearPendingVideo()
    }

    private func attachDemoVideo(announce: Bool) {
        let demoURL = URL(string: "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4")!
        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aisdk-test-video.mp4")

        do {
            let info = try VideoAttachmentUtils.downloadVideo(from: demoURL, to: destinationURL)
            let data = try Data(contentsOf: destinationURL)
            runtimeConfig.clearPendingVideo()
            runtimeConfig.pendingVideoFilePath = destinationURL.path
            runtimeConfig.pendingVideoData = data
            runtimeConfig.pendingVideoMimeType = info.mimeType
            runtimeConfig.pendingVideoDisplayName = info.name
            if announce {
                print(VideoAttachmentUtils.renderAttachmentBox(for: info))
                print(ANSIStyles.dim("Demo video saved to \(destinationURL.path)"))
                print(ANSIStyles.dim("This video will be sent with your next message."))
            }
        } catch {
            print(ANSIStyles.error("Failed to download demo video: \(error.localizedDescription)"))
            runtimeConfig.clearPendingVideo()
        }
    }

    private func attachLocalVideo(at path: String, announce: Bool) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let info = VideoAttachmentUtils.videoInfo(forPath: path, sizeBytes: data.count)
            runtimeConfig.clearPendingVideo()
            runtimeConfig.pendingVideoFilePath = path
            runtimeConfig.pendingVideoData = data
            runtimeConfig.pendingVideoMimeType = info.mimeType
            runtimeConfig.pendingVideoDisplayName = info.name
            if announce {
                print(VideoAttachmentUtils.renderAttachmentBox(for: info))
                print(ANSIStyles.dim("This video will be sent with your next message."))
            }
        } catch {
            print(ANSIStyles.error("Failed to read video file: \(error.localizedDescription)"))
            runtimeConfig.clearPendingVideo()
        }
    }

    private func downloadVideoForPlayback(from urlString: String) -> (info: VideoAttachmentInfo, localPath: String)? {
        guard let remoteURL = URL(string: urlString) else {
            return nil
        }
        let destinationURL = temporaryVideoURL(for: remoteURL)
        do {
            let info = try VideoAttachmentUtils.downloadVideo(from: remoteURL, to: destinationURL)
            return (info: info, localPath: destinationURL.path)
        } catch {
            print(ANSIStyles.error("Failed to download video for playback: \(error.localizedDescription)"))
            return nil
        }
    }

    private func temporaryVideoURL(for remoteURL: URL) -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let baseName = remoteURL.lastPathComponent.isEmpty ? "video.mp4" : remoteURL.lastPathComponent
        let uniqueName = "aisdk-\(UUID().uuidString)-\(baseName)"
        return tempDir.appendingPathComponent(uniqueName)
    }

    private func openVideo(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [path]
        do {
            try process.run()
        } catch {
            print(ANSIStyles.warning("Unable to open video player: \(error.localizedDescription)"))
        }
    }

    private func refreshProviderClient() {
        guard options.provider == .anthropic else { return }
        client = createClient()
    }

    // MARK: - Model Selection

    private func selectModel() async {
        guard let client = client else { return }

        if TerminalSize.isTTY && TerminalSize.isInputTTY {
            // Interactive selection with arrow keys
            let selector = ModelSelector(client: client)
            if let selectedModel = await selector.selectModel() {
                runtimeConfig.currentModel = selectedModel
            }
        } else {
            // Simple numbered list for non-TTY
            if let selectedModel = await selectModelSimple(client: client) {
                runtimeConfig.currentModel = selectedModel
            }
        }
    }

    // MARK: - Chat Loop

    private func runChatLoop() async {
        print("\n" + ANSIStyles.dim("Type your message and press Enter. Use /help for commands."))
        print("")

        while shouldContinue {
            // Read user input
            guard let input = inputReader.readInput() else {
                // EOF (Ctrl+D)
                shouldContinue = false
                break
            }

            let trimmedInput = input.trimmingCharacters(in: .whitespaces)

            // Skip empty input
            if trimmedInput.isEmpty { continue }

            // Handle commands
            if commandHandler.isCommand(trimmedInput) {
                let result = await commandHandler.handle(trimmedInput)

                switch result {
                case .exit:
                    shouldContinue = false

                case .changeModel:
                    await selectModel()
                    printStatus()

                case .notRecognized(let cmd):
                    print(ANSIStyles.warning("Unknown command: /\(cmd)"))
                    print(ANSIStyles.dim("Type /help for available commands"))

                case .error(let msg):
                    print(ANSIStyles.error(msg))

                case .handled:
                    break
                }

                continue
            }

            // Process as chat message
            await processMessage(trimmedInput)
        }
    }

    // MARK: - LegacyMessage Processing

    private func processMessage(_ input: String) async {
        guard let client = client, let model = runtimeConfig.currentModel else {
            print(ANSIStyles.error("No model selected"))
            return
        }

        var videoAttachmentInfo: VideoAttachmentInfo?
        var videoContentPart: AIMessage.ContentPart?
        var videoPlaybackPath: String?

        if runtimeConfig.pendingVideoURL != nil || runtimeConfig.pendingVideoData != nil {
            guard options.provider == .gemini else {
                print(ANSIStyles.warning("Video is only supported with --provider gemini"))
                runtimeConfig.clearPendingVideo()
                return
            }
        }

        if let pendingData = runtimeConfig.pendingVideoData,
           let pendingMimeType = runtimeConfig.pendingVideoMimeType {
            let pendingPath = runtimeConfig.pendingVideoFilePath ?? "video.mp4"
            let pendingName = runtimeConfig.pendingVideoDisplayName ?? URL(fileURLWithPath: pendingPath).lastPathComponent
            videoAttachmentInfo = VideoAttachmentInfo(
                name: pendingName,
                sizeBytes: pendingData.count,
                mimeType: pendingMimeType,
                source: pendingPath
            )
            videoContentPart = .video(pendingData, mimeType: pendingMimeType)
            videoPlaybackPath = runtimeConfig.pendingVideoFilePath
        } else if let pendingURL = runtimeConfig.pendingVideoURL {
            if let playbackInfo = downloadVideoForPlayback(from: pendingURL) {
                videoAttachmentInfo = playbackInfo.info
                videoPlaybackPath = playbackInfo.localPath
            } else {
                print(ANSIStyles.warning("Unable to download video for playback. Sending URL to provider."))
            }
            videoContentPart = .videoURL(pendingURL)
        }

        if let videoContentPart = videoContentPart {
            sessionManager.addUserMessage(parts: [.text(input), videoContentPart])
            runtimeConfig.clearPendingVideo()

            if let info = videoAttachmentInfo {
                print("")
                print(VideoAttachmentUtils.renderAttachmentBox(for: info))
                if let playbackPath = videoPlaybackPath {
                    print("▶ Playing video: \(playbackPath) (\(info.sizeDescription), \(info.mimeType))")
                    openVideo(at: playbackPath)
                } else {
                    print(ANSIStyles.warning("Video playback skipped (no local file)."))
                }
                print("⏳ Analyzing video with \(model)...")
            } else {
                print("⏳ Analyzing video with \(model)...")
            }
        } else {
            sessionManager.addUserMessage(input)
        }

        streamRenderer.reset()
        reasoningRenderer.reset()
        specCompiler.reset()

        do {
            let agent = buildAgent(client: client, modelId: model)
            let messages = buildConversationMessages()
            let shouldRenderStreamingText = runtimeConfig.responseFormat == .text

            var responseText = ""
            var hasReasoning = false
            var hasPrintedAssistantLabel = false
            var hasPrintedVideoAnalysisLabel = false
            let isVideoMessage = videoContentPart != nil
            let spinnerMessage = isVideoMessage ? "Analyzing..." : "Thinking..."
            var responseSpinner: Spinner? = Spinner(message: spinnerMessage)
            var sources: [WebSearchSource] = []
            var seenToolCalls: Set<String> = []

            print("")
            responseSpinner?.start()

            func stopSpinnerIfNeeded() {
                responseSpinner?.stop()
                responseSpinner = nil
            }

            func printAssistantLabelIfNeeded() {
                guard !hasPrintedAssistantLabel else { return }
                if isVideoMessage && shouldRenderStreamingText && !hasPrintedVideoAnalysisLabel {
                    print(ANSIStyles.bold("🎬 Video Analysis:"))
                    hasPrintedVideoAnalysisLabel = true
                }
                print("\(ANSIStyles.cyan("Assistant")): ", terminator: "")
                fflush(stdout)
                hasPrintedAssistantLabel = true
            }

            for try await event in agent.streamExecute(messages: messages) {
                switch event {
                case .start:
                    if runtimeConfig.verbose {
                        print(ANSIStyles.dim("[Stream started]"))
                    }

                case .textDelta(let text):
                    if hasReasoning {
                        reasoningRenderer.finishThinking()
                        hasReasoning = false
                        stopSpinnerIfNeeded()
                        if shouldRenderStreamingText {
                            print("\n\(ANSIStyles.cyan("Assistant")): ", terminator: "")
                            fflush(stdout)
                            hasPrintedAssistantLabel = true
                        }
                    } else {
                        stopSpinnerIfNeeded()
                        if shouldRenderStreamingText {
                            printAssistantLabelIfNeeded()
                        }
                    }

                    responseText += text
                    if shouldRenderStreamingText {
                        streamRenderer.append(text)
                    }

                case .reasoningDelta(let thinking):
                    stopSpinnerIfNeeded()
                    if !hasReasoning {
                        hasReasoning = true
                        reasoningRenderer.startThinking()
                    }
                    reasoningRenderer.appendThinking(thinking)

                case .toolCallStart(let id, let name):
                    stopSpinnerIfNeeded()
                    if shouldRenderStreamingText {
                        streamRenderer.finish()
                        hasPrintedAssistantLabel = false
                    }
                    toolRenderer.startToolCall(id: id, name: name)

                case .toolCallDelta(let id, let argumentsDelta):
                    toolRenderer.appendArguments(id: id, delta: argumentsDelta)

                case .toolCall(let id, let name, let arguments),
                     .toolCallFinish(let id, let name, let arguments):
                    if !seenToolCalls.contains(id) {
                        seenToolCalls.insert(id)
                        toolRenderer.toolCallReady(id: id, name: name, arguments: arguments)
                        toolRenderer.showExecuting(id: id)
                    }

                case .toolResult(let id, let result, let metadata):
                    if result.lowercased().hasPrefix("error:") {
                        toolRenderer.showError(id: id, error: result)
                    } else {
                        toolRenderer.showResult(id: id, result: result, metadata: metadata)
                    }
                    if let searchMeta = metadata as? WebSearchMetadata {
                        sources.append(contentsOf: searchMeta.sources)
                    }

                case .stepStart(let stepIndex):
                    stopSpinnerIfNeeded()
                    responseSpinner = Spinner(message: "Thinking (step \(stepIndex + 1))...")
                    responseSpinner?.start()

                case .stepFinish(_, let result):
                    sessionManager.applyStepResult(result)

                case .usage(let usage):
                    sessionManager.updateUsage(
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens
                    )

                case .finish(let reason, _):
                    stopSpinnerIfNeeded()
                    if hasReasoning {
                        reasoningRenderer.finishThinking()
                    }
                    if shouldRenderStreamingText {
                        streamRenderer.finish()
                    }

                    if runtimeConfig.verbose {
                        print(ANSIStyles.dim("\n[Finished: \(reason)]"))
                    }

                case .source(let aiSource):
                    if let url = aiSource.url {
                        sources.append(WebSearchSource(
                            title: aiSource.title ?? "",
                            url: url,
                            snippet: aiSource.snippet
                        ))
                    }

                case .uiPatch(let patchBatch):
                    stopSpinnerIfNeeded()
                    if let tree = specCompiler.apply(patchBatch) {
                        if let rendered = try? uiRenderer.render(tree: tree) {
                            print("\n" + rendered)
                        }
                    }

                default:
                    break
                }
            }

            if !shouldRenderStreamingText {
                renderStructuredResponse(responseText)
            }

            if runtimeConfig.citationsEnabled {
                printSources(sources)
            }
        } catch {
            print("\n" + ANSIStyles.error("Error: \(error.localizedDescription)"))

            if sessionManager.messages.last?.role == .user {
                sessionManager.removeLastMessage()
            }
        }

        print("")
    }

    // MARK: - LegacyAgent Setup

    private func buildAgent(client: any ProviderClient, modelId: String) -> Agent {
        let toolTypes = runtimeConfig.toolsEnabled ? builtInTools : []

        let reasoning: AIReasoningConfig? = runtimeConfig.reasoningEffort.flatMap { effortString in
            AIReasoningConfig.AIReasoningEffort(rawValue: effortString).map { .effort($0) }
        }

        // Anthropic requires temperature=1 when thinking/reasoning is enabled
        let temperature: Double?
        if reasoning != nil, options.provider == .anthropic {
            temperature = 1.0
        } else {
            temperature = runtimeConfig.temperature
        }

        // Build caching config from runtime settings
        let caching: AICacheConfig? = runtimeConfig.cachingEnabled
            ? AICacheConfig(retention: runtimeConfig.cachingExtended ? .extended : .standard)
            : nil

        let requestOptions = Agent.RequestOptions(
            maxTokens: runtimeConfig.maxTokens,
            temperature: temperature,
            toolChoice: toolTypes.isEmpty ? nil : .auto,
            responseFormat: buildResponseFormat(),
            reasoning: reasoning,
            caching: caching
        )

        let languageModel: any LLM
        if runtimeConfig.reliabilityEnabled {
            let providers = buildFailoverProviders(primary: client)
            let executor = FailoverExecutor(providers: providers)
            languageModel = ReliableLanguageModelAdapter(
                executor: executor,
                modelId: modelId,
                providerLabel: providers.map { $0.providerId }.joined(separator: " → ")
            )
        } else {
            languageModel = ProviderLanguageModelAdapter(client: client, modelId: modelId)
        }

        return Agent(
            model: languageModel,
            tools: toolTypes,
            builtInTools: runtimeConfig.activeBuiltInTools,
            instructions: buildSystemPrompt(),
            requestOptions: requestOptions
        )
    }

    private func buildSystemPrompt() -> String {
        var prompt = sessionManager.systemPrompt
        prompt += "\n\nTool outputs are live data. Do not describe tool results as simulated."

        if runtimeConfig.citationsEnabled {
            prompt += "\n\nWhen you use web_search results, cite sources inline with [n] where n is the result index."
        }

        switch runtimeConfig.responseFormat {
        case .json:
            prompt += "\n\nRespond with a single JSON object only. Do not wrap in markdown."
        case .schema:
            prompt += "\n\nRespond with a JSON object that matches the schema for the CLI response. Do not wrap in markdown."
        case .ui:
            prompt += "\n\n" + UICatalog.extended.generatePrompt()
            prompt += """

            CRITICAL INSTRUCTIONS FOR UI FORMAT:
            - You MUST respond with ONLY valid JSON in the json-render format above
            - Do NOT include any text before or after the JSON
            - Do NOT wrap in markdown code fences
            - If you need to ask the user a question, use a Card with Text components containing your question
            - If you need to show information, use appropriate UI components
            - NEVER respond with plain text - always use the JSON UI format
            - Example for asking a question:
            {"root":"q","elements":{"q":{"type":"Card","props":{"title":"Question"},"children":["msg"]},"msg":{"type":"Text","props":{"content":"What city would you like weather for?"}}}}
            """
        case .text:
            break
        }

        return prompt
    }

    private func buildResponseFormat() -> ResponseFormat? {
        switch runtimeConfig.responseFormat {
        case .text:
            return .text
        case .json:
            return .jsonObject
        case .schema:
            return .jsonSchema(
                name: "cli_response",
                description: "Structured CLI response",
                schemaBuilder: CLIResponseSchemaBuilder(),
                strict: true
            )
        case .ui:
            return .jsonObject
        }
    }

    private func buildConversationMessages() -> [AIMessage] {
        guard let first = sessionManager.messages.first, first.role == .system else {
            return sessionManager.messages
        }
        return Array(sessionManager.messages.dropFirst())
    }

    private func renderStructuredResponse(_ response: String) {
        guard !response.isEmpty else { return }

        let payload = extractJSONPayload(from: response) ?? response
        print("\(ANSIStyles.cyan("Assistant")): ")

        switch runtimeConfig.responseFormat {
        case .ui:
            // First check if we have JSON-like content
            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{") else {
                // Model responded with text instead of JSON
                print(ANSIStyles.warning("⚠ Model responded with text instead of UI JSON."))
                print(ANSIStyles.dim("Tip: The model should return json-render format. Try rephrasing or being more specific."))
                print("")
                print(payload)
                return
            }

            do {
                let data = Data(payload.utf8)
                let tree = try UITree.parse(from: data, validatingWith: UICatalog.extended)
                let rendered = try uiRenderer.render(tree: tree)
                print(rendered)
            } catch {
                print(ANSIStyles.error("Failed to render UI: \(error.localizedDescription)"))
                print(ANSIStyles.dim("Raw response:"))
                print(payload)
            }
        case .json, .schema:
            if let data = payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
               let prettyString = String(data: pretty, encoding: .utf8) {
                print(prettyString)
            } else {
                print(payload)
            }
        case .text:
            print(payload)
        }
    }

    private func extractJSONPayload(from text: String) -> String? {
        if let fenceStart = text.range(of: "```") {
            let rest = text[fenceStart.upperBound...]
            if let fenceEnd = rest.range(of: "```") {
                var content = String(rest[..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let newline = content.firstIndex(of: "\n") {
                    let prefix = content[..<newline].lowercased()
                    if prefix == "json" || prefix == "jsonc" {
                        content = String(content[content.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                return content
            }
        }

        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }

        return nil
    }

    private func printSources(_ sources: [WebSearchSource]) {
        guard !sources.isEmpty else { return }

        print("")
        print(ANSIStyles.bold("Sources:"))
        for (index, source) in sources.enumerated() {
            let title = source.title.isEmpty ? source.url : source.title
            print(ANSIStyles.dim("[\(index + 1)]") + " \(title)")
            print(ANSIStyles.dim("    \(source.url)"))
            if let snippet = source.snippet, !snippet.isEmpty {
                print(ANSIStyles.dim("    \(snippet)"))
            }
        }
    }

    private func buildFailoverProviders(primary: any ProviderClient) -> [any ProviderClient] {
        var providers: [any ProviderClient] = [primary]

        guard runtimeConfig.reliabilityEnabled else {
            return providers
        }

        switch options.provider {
        case .openrouter:
            if let lite = createLiteLLMClient() {
                if !providers.contains(where: { $0.providerId == lite.providerId }) {
                    providers.append(lite)
                }
            }
        case .litellm:
            if let openRouter = createOpenRouterClient() {
                if !providers.contains(where: { $0.providerId == openRouter.providerId }) {
                    providers.append(openRouter)
                }
            }
        case .openai:
            // OpenAI direct testing - no failover needed
            break
        case .anthropic:
            // Anthropic direct testing - no failover needed
            break
        case .gemini:
            // Gemini direct testing - no failover needed
            break
        }

        return providers
    }

    private func createOpenRouterClient() -> OpenRouterClient? {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !apiKey.isEmpty else {
            return nil
        }
        return OpenRouterClient(
            apiKey: apiKey,
            appName: "AISDK-CLI",
            siteURL: "https://github.com/AISDK"
        )
    }

    private func createLiteLLMClient() -> LiteLLMClient? {
        let baseURL = ProcessInfo.processInfo.environment["LITELLM_BASE_URL"]
            .flatMap { URL(string: $0) }
        let apiKey = ProcessInfo.processInfo.environment["LITELLM_API_KEY"]
        return LiteLLMClient(baseURL: baseURL, apiKey: apiKey)
    }

    // MARK: - Status Display

    private func printStatus() {
        guard let model = runtimeConfig.currentModel else { return }

        print("")
        print(ANSIStyles.dim(String(repeating: "─", count: 60)))
        print(" Model: \(ANSIStyles.cyan(model))")
        print(" Format: \(ANSIStyles.cyan(runtimeConfig.responseFormat.rawValue))")
        print(" Citations: \(ANSIStyles.cyan(runtimeConfig.citationsEnabled ? "on" : "off"))")
        if runtimeConfig.reliabilityEnabled {
            print(" Reliability: \(ANSIStyles.cyan("on"))")
        }

        if runtimeConfig.toolsEnabled {
            let toolNames = builtInTools.map { $0.init().name }.joined(separator: ", ")
            print(" Tools: \(ANSIStyles.green(toolNames))")
        }

        if !runtimeConfig.activeBuiltInTools.isEmpty {
            let builtInNames = runtimeConfig.activeBuiltInTools.map { $0.kind }.joined(separator: ", ")
            print(" Built-in: \(ANSIStyles.green(builtInNames))")
        }

        print(ANSIStyles.dim(String(repeating: "─", count: 60)))
    }

    private func printFinalStats() {
        let stats = sessionManager.getStatistics()

        if stats.exchangeCount > 0 {
            print("""

            \(ANSIStyles.dim("Session Summary:"))
            \(ANSIStyles.dim("  Exchanges: \(stats.exchangeCount)"))
            \(ANSIStyles.dim("  Tokens: \(stats.totalTokens) (\(stats.totalPromptTokens) prompt, \(stats.totalCompletionTokens) completion)"))
            \(ANSIStyles.dim("  Duration: \(stats.formattedDuration)"))
            """)
        }
    }
}

private struct CLIResponseSchemaBuilder: SchemaBuilding {
    func build() -> JSONSchema {
        JSONSchema.object(
            title: "CLIResponse",
            description: "Structured response for AISDK CLI",
            properties: [
                "answer": .string(description: "Assistant response text"),
                "citations": .array(
                    description: "List of source indices cited in the answer",
                    items: .integer(description: "Source index")
                )
            ],
            required: ["answer"]
        )
    }
}
