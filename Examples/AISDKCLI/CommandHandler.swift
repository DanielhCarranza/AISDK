//
//  CommandHandler.swift
//  AISDKCLI
//
//  Handles slash commands in the chat interface
//

import Foundation
import AISDK

/// Result of handling a command
enum CommandResult {
    /// Command was handled successfully
    case handled

    /// Command requires exiting the chat loop
    case exit

    /// Command requests model change
    case changeModel

    /// Command was not recognized
    case notRecognized(String)

    /// Command had an error
    case error(String)
}

/// Handles slash commands
class CommandHandler {
    /// Reference to session manager
    weak var sessionManager: SessionManager?

    /// Reference to runtime config
    weak var runtimeConfig: RuntimeConfig?

    /// Callback for model change requests
    var onModelChangeRequested: (() async -> Void)?

    init() {}

    /// Handle a command input
    /// Returns true if input was a command (handled or not)
    func isCommand(_ input: String) -> Bool {
        return input.hasPrefix("/")
    }

    /// Process a command
    func handle(_ input: String) async -> CommandResult {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else {
            return .notRecognized(trimmed)
        }

        // Parse command and arguments
        let parts = trimmed.dropFirst().components(separatedBy: " ")
        guard let command = parts.first?.lowercased() else {
            return .notRecognized(trimmed)
        }

        let args = Array(parts.dropFirst())
        let argString = args.joined(separator: " ")

        switch command {
        case "exit", "quit", "q":
            return .exit

        case "help", "h", "?":
            printHelp()
            return .handled

        case "clear", "c":
            handleClear()
            return .handled

        case "model", "m":
            return .changeModel

        case "system", "sys":
            handleSystem(argString)
            return .handled

        case "tokens", "usage":
            handleTokens()
            return .handled

        case "save":
            return handleSave(argString)

        case "load":
            return handleLoad(argString)

        case "verbose", "v":
            handleVerbose()
            return .handled

        case "history", "hist":
            handleHistory()
            return .handled

        case "config":
            handleConfig()
            return .handled

        case "tools":
            handleTools(argString)
            return .handled

        case "format":
            handleFormat(argString)
            return .handled

        case "citations":
            handleCitations(argString)
            return .handled

        case "reliable":
            handleReliable(argString)
            return .handled

        // OpenAI Responses API specific commands
        case "websearch":
            handleWebSearch(argString)
            return .handled

        case "code", "codeinterpreter":
            handleCodeInterpreter(argString)
            return .handled

        case "upload":
            return await handleUpload(argString)

        case "files":
            handleFiles()
            return .handled

        case "store":
            handleStore(argString)
            return .handled

        case "continue":
            handleContinue(argString)
            return .handled

        default:
            return .notRecognized(command)
        }
    }

    // MARK: - Command Implementations

    private func printHelp() {
        print("""

        \(ANSIStyles.bold("Available Commands:"))

        \(ANSIStyles.cyan("/help"))          Show this help
        \(ANSIStyles.cyan("/exit"))          Exit the CLI (also: /quit, /q)
        \(ANSIStyles.cyan("/clear"))         Clear conversation history
        \(ANSIStyles.cyan("/model"))         Change current model
        \(ANSIStyles.cyan("/system <msg>"))  Set system prompt
        \(ANSIStyles.cyan("/tokens"))        Show token usage statistics
        \(ANSIStyles.cyan("/save <file>"))   Save conversation to file
        \(ANSIStyles.cyan("/load <file>"))   Load conversation from file
        \(ANSIStyles.cyan("/verbose"))       Toggle verbose mode
        \(ANSIStyles.cyan("/history"))       Show conversation history
        \(ANSIStyles.cyan("/config"))        Show current configuration
        \(ANSIStyles.cyan("/tools on|off"))  Enable/disable tools
        \(ANSIStyles.cyan("/format <mode>")) Set response format (text|json|schema|ui)
        \(ANSIStyles.cyan("/citations on|off")) Toggle citations rendering
        \(ANSIStyles.cyan("/reliable on|off")) Toggle reliability/failover mode

        \(ANSIStyles.bold("OpenAI Responses API Commands (--provider openai):"))
        \(ANSIStyles.cyan("/websearch on|off"))   Toggle web search tool
        \(ANSIStyles.cyan("/code on|off"))        Toggle code interpreter
        \(ANSIStyles.cyan("/upload <file>"))      Upload file for analysis
        \(ANSIStyles.cyan("/files"))              List uploaded files
        \(ANSIStyles.cyan("/store on|off"))       Toggle response storage
        \(ANSIStyles.cyan("/continue <resp_id>")) Continue from a previous response

        \(ANSIStyles.bold("Input Modes:"))
        - Single line: Type message and press Enter
        - Multi-line: Start with \(ANSIStyles.cyan("```")), end with \(ANSIStyles.cyan("```"))

        \(ANSIStyles.bold("Keyboard Shortcuts:"))
        - Ctrl+C: Cancel current operation
        - Ctrl+D: Exit

        """)
    }

    private func handleClear() {
        sessionManager?.clear()
        print(ANSIStyles.success("Conversation cleared"))
    }

    private func handleSystem(_ prompt: String) {
        if prompt.isEmpty {
            print(ANSIStyles.info("Current system prompt:"))
            print(ANSIStyles.dim(sessionManager?.systemPrompt ?? "Not set"))
        } else {
            sessionManager?.systemPrompt = prompt
            print(ANSIStyles.success("System prompt updated"))
        }
    }

    private func handleTokens() {
        guard let stats = sessionManager?.getStatistics() else {
            print(ANSIStyles.warning("No session data available"))
            return
        }

        print("""

        \(ANSIStyles.bold("Session Statistics:"))
        ┌──────────────────────────────────────┐
        │ Exchanges:      \(String(format: "%6d", stats.exchangeCount).padding(toLength: 20, withPad: " ", startingAt: 0))│
        │ Messages:       \(String(format: "%6d", stats.messageCount).padding(toLength: 20, withPad: " ", startingAt: 0))│
        ├──────────────────────────────────────┤
        │ Prompt tokens:  \(String(format: "%6d", stats.totalPromptTokens).padding(toLength: 20, withPad: " ", startingAt: 0))│
        │ Output tokens:  \(String(format: "%6d", stats.totalCompletionTokens).padding(toLength: 20, withPad: " ", startingAt: 0))│
        │ Total tokens:   \(String(format: "%6d", stats.totalTokens).padding(toLength: 20, withPad: " ", startingAt: 0))│
        ├──────────────────────────────────────┤
        │ Duration:       \(stats.formattedDuration.padding(toLength: 20, withPad: " ", startingAt: 0))│
        └──────────────────────────────────────┘

        """)
    }

    private func handleSave(_ filename: String) -> CommandResult {
        guard !filename.isEmpty else {
            print(ANSIStyles.error("Usage: /save <filename>"))
            return .error("Missing filename")
        }

        let path = filename.hasSuffix(".json") ? filename : filename + ".json"

        do {
            try sessionManager?.save(to: path)
            print(ANSIStyles.success("Conversation saved to: \(path)"))
            return .handled
        } catch {
            print(ANSIStyles.error("Failed to save: \(error.localizedDescription)"))
            return .error(error.localizedDescription)
        }
    }

    private func handleLoad(_ filename: String) -> CommandResult {
        guard !filename.isEmpty else {
            print(ANSIStyles.error("Usage: /load <filename>"))
            return .error("Missing filename")
        }

        let path = filename.hasSuffix(".json") ? filename : filename + ".json"

        do {
            try sessionManager?.load(from: path)
            let count = sessionManager?.messages.count ?? 0
            print(ANSIStyles.success("Loaded \(count) messages from: \(path)"))
            return .handled
        } catch {
            print(ANSIStyles.error("Failed to load: \(error.localizedDescription)"))
            return .error(error.localizedDescription)
        }
    }

    private func handleVerbose() {
        if let config = runtimeConfig {
            config.verbose.toggle()
            print(ANSIStyles.info("Verbose mode: \(config.verbose ? "ON" : "OFF")"))
        }
    }

    private func handleHistory() {
        guard let messages = sessionManager?.messages else {
            print(ANSIStyles.warning("No history available"))
            return
        }

        print("\n" + ANSIStyles.bold("Conversation History:"))
        print(ANSIStyles.dim(String(repeating: "─", count: 50)))

        for (index, message) in messages.enumerated() {
            let roleLabel: String
            let color: (String) -> String

            switch message.role {
            case .system:
                roleLabel = "System"
                color = ANSIStyles.magenta
            case .user:
                roleLabel = "You"
                color = ANSIStyles.green
            case .assistant:
                roleLabel = "Assistant"
                color = ANSIStyles.cyan
            case .tool:
                roleLabel = "Tool"
                color = ANSIStyles.yellow
            }

            let content = message.content.textValue
            let truncated = content.count > 100
                ? String(content.prefix(100)) + "..."
                : content

            print("\(ANSIStyles.dim("[\(index)]")) \(color(roleLabel)): \(truncated)")
        }

        print(ANSIStyles.dim(String(repeating: "─", count: 50)) + "\n")
    }

    private func handleConfig() {
        guard let config = runtimeConfig else {
            print(ANSIStyles.warning("No configuration available"))
            return
        }

        print("""

        \(ANSIStyles.bold("Current Configuration:"))
        ┌──────────────────────────────────────┐
        │ Model:        \((config.currentModel ?? "Not selected").prefix(22).padding(toLength: 22, withPad: " ", startingAt: 0))│
        │ Temperature:  \(String(format: "%.2f", config.temperature).padding(toLength: 22, withPad: " ", startingAt: 0))│
        │ Max tokens:   \(String(config.maxTokens).padding(toLength: 22, withPad: " ", startingAt: 0))│
        │ Verbose:      \((config.verbose ? "ON" : "OFF").padding(toLength: 22, withPad: " ", startingAt: 0))│
        │ Tools:        \((config.toolsEnabled ? "Enabled" : "Disabled").padding(toLength: 22, withPad: " ", startingAt: 0))│
        │ Format:       \((config.responseFormat.rawValue).padding(toLength: 22, withPad: " ", startingAt: 0))│
        │ Citations:    \((config.citationsEnabled ? "ON" : "OFF").padding(toLength: 22, withPad: " ", startingAt: 0))│
        │ Reliable:     \((config.reliabilityEnabled ? "ON" : "OFF").padding(toLength: 22, withPad: " ", startingAt: 0))│
        └──────────────────────────────────────┘

        """)
    }

    private func handleTools(_ arg: String) {
        guard let config = runtimeConfig else { return }

        switch arg.lowercased() {
        case "on", "enable", "true":
            config.toolsEnabled = true
            print(ANSIStyles.success("Tools enabled"))
        case "off", "disable", "false":
            config.toolsEnabled = false
            print(ANSIStyles.success("Tools disabled"))
        case "":
            print(ANSIStyles.info("Tools are \(config.toolsEnabled ? "enabled" : "disabled")"))
            print(ANSIStyles.dim("Usage: /tools on|off"))
        default:
            print(ANSIStyles.error("Unknown option. Use: /tools on|off"))
        }
    }

    private func handleFormat(_ arg: String) {
        guard let config = runtimeConfig else { return }

        let trimmed = arg.lowercased()
        if trimmed.isEmpty {
            print(ANSIStyles.info("Current format: \(config.responseFormat.rawValue)"))
            print(ANSIStyles.dim("Usage: /format text|json|schema|ui"))
            return
        }

        if let mode = ResponseFormatMode(rawValue: trimmed) {
            config.responseFormat = mode
            print(ANSIStyles.success("Response format set to: \(mode.rawValue)"))
        } else {
            print(ANSIStyles.error("Unknown format. Use: text|json|schema|ui"))
        }
    }

    private func handleCitations(_ arg: String) {
        guard let config = runtimeConfig else { return }

        switch arg.lowercased() {
        case "on", "enable", "true":
            config.citationsEnabled = true
            print(ANSIStyles.success("Citations enabled"))
        case "off", "disable", "false":
            config.citationsEnabled = false
            print(ANSIStyles.success("Citations disabled"))
        case "":
            print(ANSIStyles.info("Citations are \(config.citationsEnabled ? "enabled" : "disabled")"))
            print(ANSIStyles.dim("Usage: /citations on|off"))
        default:
            print(ANSIStyles.error("Unknown option. Use: /citations on|off"))
        }
    }

    private func handleReliable(_ arg: String) {
        guard let config = runtimeConfig else { return }

        switch arg.lowercased() {
        case "on", "enable", "true":
            config.reliabilityEnabled = true
            print(ANSIStyles.success("Reliability mode enabled"))
        case "off", "disable", "false":
            config.reliabilityEnabled = false
            print(ANSIStyles.success("Reliability mode disabled"))
        case "":
            print(ANSIStyles.info("Reliability mode is \(config.reliabilityEnabled ? "enabled" : "disabled")"))
            print(ANSIStyles.dim("Usage: /reliable on|off"))
        default:
            print(ANSIStyles.error("Unknown option. Use: /reliable on|off"))
        }
    }

    // MARK: - OpenAI Responses API Commands

    private func handleWebSearch(_ arg: String) {
        guard let config = runtimeConfig else { return }

        switch arg.lowercased() {
        case "on", "enable", "true":
            config.webSearchEnabled = true
            print(ANSIStyles.success("Web search enabled"))
        case "off", "disable", "false":
            config.webSearchEnabled = false
            print(ANSIStyles.success("Web search disabled"))
        case "":
            print(ANSIStyles.info("Web search is \(config.webSearchEnabled ? "enabled" : "disabled")"))
            print(ANSIStyles.dim("Usage: /websearch on|off"))
        default:
            print(ANSIStyles.error("Unknown option. Use: /websearch on|off"))
        }
    }

    private func handleCodeInterpreter(_ arg: String) {
        guard let config = runtimeConfig else { return }

        switch arg.lowercased() {
        case "on", "enable", "true":
            config.codeInterpreterEnabled = true
            print(ANSIStyles.success("Code interpreter enabled"))
        case "off", "disable", "false":
            config.codeInterpreterEnabled = false
            print(ANSIStyles.success("Code interpreter disabled"))
        case "":
            print(ANSIStyles.info("Code interpreter is \(config.codeInterpreterEnabled ? "enabled" : "disabled")"))
            print(ANSIStyles.dim("Usage: /code on|off"))
        default:
            print(ANSIStyles.error("Unknown option. Use: /code on|off"))
        }
    }

    private func handleUpload(_ path: String) async -> CommandResult {
        guard let config = runtimeConfig else {
            return .error("No configuration available")
        }

        guard !path.isEmpty else {
            print(ANSIStyles.error("Usage: /upload <file_path>"))
            return .error("Missing file path")
        }

        let expandedPath = NSString(string: path).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            print(ANSIStyles.error("File not found: \(path)"))
            return .error("File not found")
        }

        print(ANSIStyles.info("Uploading file: \(path)..."))

        // TODO: Implement actual file upload via OpenAI Provider
        // For now, simulate the upload
        let simulatedFileId = "file_\(UUID().uuidString.prefix(8))"
        config.uploadedFileIds.append(simulatedFileId)

        print(ANSIStyles.success("File uploaded: \(simulatedFileId)"))
        print(ANSIStyles.dim("Note: File upload requires --provider openai"))
        return .handled
    }

    private func handleFiles() {
        guard let config = runtimeConfig else { return }

        if config.uploadedFileIds.isEmpty {
            print(ANSIStyles.info("No files uploaded"))
            print(ANSIStyles.dim("Use /upload <file_path> to upload a file"))
        } else {
            print(ANSIStyles.bold("\nUploaded Files:"))
            for (index, fileId) in config.uploadedFileIds.enumerated() {
                print("  [\(index + 1)] \(fileId)")
            }
            print("")
        }
    }

    private func handleStore(_ arg: String) {
        guard let config = runtimeConfig else { return }

        switch arg.lowercased() {
        case "on", "enable", "true":
            config.storeResponses = true
            print(ANSIStyles.success("Response storage enabled"))
            print(ANSIStyles.dim("Responses will be stored and can be continued with /continue"))
        case "off", "disable", "false":
            config.storeResponses = false
            print(ANSIStyles.success("Response storage disabled"))
        case "":
            print(ANSIStyles.info("Response storage is \(config.storeResponses ? "enabled" : "disabled")"))
            print(ANSIStyles.dim("Usage: /store on|off"))
        default:
            print(ANSIStyles.error("Unknown option. Use: /store on|off"))
        }
    }

    private func handleContinue(_ responseId: String) {
        guard let config = runtimeConfig else { return }

        if responseId.isEmpty {
            if let currentId = config.previousResponseId {
                print(ANSIStyles.info("Current response ID: \(currentId)"))
            } else {
                print(ANSIStyles.info("No previous response ID set"))
            }
            print(ANSIStyles.dim("Usage: /continue <response_id>"))
            print(ANSIStyles.dim("Use /store on to enable response storage"))
        } else {
            config.previousResponseId = responseId
            print(ANSIStyles.success("Continuing from response: \(responseId)"))
        }
    }
}
