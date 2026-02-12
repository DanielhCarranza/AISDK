//
//  CLIOptions.swift
//  AISDKCLI
//
//  Command line argument parsing and configuration
//

import Foundation
import AISDK

/// Provider type selection
enum ProviderType: String, CaseIterable {
    case openrouter
    case litellm
    case openai  // Direct OpenAI Responses API for testing
    case anthropic
    case gemini  // Direct Google Gemini API (supports video)

    var displayName: String {
        switch self {
        case .openrouter: return "OpenRouter"
        case .litellm: return "LiteLLM"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        }
    }

    var envKeyName: String {
        switch self {
        case .openrouter: return "OPENROUTER_API_KEY"
        case .litellm: return "LITELLM_API_KEY"
        case .openai: return "OPENAI_API_KEY"
        case .anthropic: return "ANTHROPIC_API_KEY"
        case .gemini: return "GOOGLE_API_KEY"
        }
    }
}

/// CLI configuration options
struct CLIOptions {
    /// AI provider to use
    var provider: ProviderType = .openrouter

    /// Pre-selected model ID (nil = interactive selection)
    var model: String?

    /// Custom system prompt
    var systemPrompt: String?

    /// Temperature for generation (0.0-2.0)
    var temperature: Double = 0.7

    /// Maximum tokens per response
    var maxTokens: Int = 4096

    /// Show verbose output
    var verbose: Bool = false

    /// Disable built-in tools
    var noTools: Bool = false

    /// Response format mode
    var responseFormat: ResponseFormatMode = .text

    /// Render a UI JSON file and exit
    var renderUIJSONPath: String?

    /// Enable citations rendering
    var citationsEnabled: Bool = true

    /// Enable reliability/failover layer
    var reliabilityEnabled: Bool = false

    /// Enable extended thinking (Anthropic)
    var thinkingEnabled: Bool = false

    /// Thinking budget tokens (Anthropic)
    var thinkingBudget: Int = 10000

    /// Enabled beta features (Anthropic)
    var betaFeatures: Set<String> = []

    /// Video URL to attach to the next message
    var videoURL: String?

    /// Reasoning effort level (all providers)
    var reasoningEffort: String? = nil

    /// Built-in tool names to enable (comma-separated via --builtin-tools)
    var builtInToolNames: [String] = []

    /// Show help and exit
    var showHelp: Bool = false

    /// Parse command line arguments
    static func parse() -> CLIOptions {
        var options = CLIOptions()
        let args = CommandLine.arguments

        var index = 1
        while index < args.count {
            let arg = args[index]

            switch arg {
            case "--provider", "-p":
                if index + 1 < args.count {
                    if let provider = ProviderType(rawValue: args[index + 1].lowercased()) {
                        options.provider = provider
                    } else {
                        print(ANSIStyles.warning("Unknown provider '\(args[index + 1])', using openrouter"))
                    }
                    index += 1
                }

            case "--model", "-m":
                if index + 1 < args.count {
                    options.model = args[index + 1]
                    index += 1
                }

            case "--system", "-s":
                if index + 1 < args.count {
                    options.systemPrompt = args[index + 1]
                    index += 1
                }

            case "--temperature", "-t":
                if index + 1 < args.count, let temp = Double(args[index + 1]) {
                    options.temperature = min(2.0, max(0.0, temp))
                    index += 1
                }

            case "--max-tokens":
                if index + 1 < args.count, let tokens = Int(args[index + 1]) {
                    options.maxTokens = max(1, tokens)
                    index += 1
                }

            case "--verbose", "-v":
                options.verbose = true

            case "--no-tools":
                options.noTools = true

            case "--format":
                if index + 1 < args.count {
                    options.responseFormat = ResponseFormatMode(rawValue: args[index + 1].lowercased()) ?? .text
                    index += 1
                }

            case "--render-ui-json":
                if index + 1 < args.count {
                    options.renderUIJSONPath = args[index + 1]
                    index += 1
                }

            case "--citations":
                options.citationsEnabled = true

            case "--no-citations":
                options.citationsEnabled = false

            case "--reliable":
                options.reliabilityEnabled = true

            case "--video":
                if index + 1 < args.count {
                    options.videoURL = args[index + 1]
                    index += 1
                }

            case "--help", "-h":
                options.showHelp = true

            case "--thinking":
                options.thinkingEnabled = true
                if index + 1 < args.count,
                   let budget = Int(args[index + 1]),
                   !args[index + 1].hasPrefix("-") {
                    options.thinkingBudget = budget
                    index += 1
                }

            case "--beta":
                var betaIndex = index + 1
                while betaIndex < args.count && !args[betaIndex].hasPrefix("-") {
                    options.betaFeatures.insert(args[betaIndex])
                    betaIndex += 1
                }
                index = betaIndex - 1

            case "--reasoning":
                if index + 1 < args.count, !args[index + 1].hasPrefix("-") {
                    let effort = args[index + 1].lowercased()
                    if ["low", "medium", "high"].contains(effort) {
                        options.reasoningEffort = effort
                    } else {
                        print(ANSIStyles.warning("Unknown reasoning effort '\(args[index + 1])'. Use: low, medium, high"))
                    }
                    index += 1
                } else {
                    print(ANSIStyles.warning("--reasoning requires an effort level: low, medium, high"))
                }

            case "--builtin-tools":
                if index + 1 < args.count, !args[index + 1].hasPrefix("-") {
                    options.builtInToolNames = args[index + 1]
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    index += 1
                } else {
                    print(ANSIStyles.warning("--builtin-tools requires comma-separated names: websearch,code,urlcontext"))
                }

            default:
                if arg.hasPrefix("-") {
                    print(ANSIStyles.warning("Unknown option: \(arg)"))
                }
            }

            index += 1
        }

        return options
    }
}

/// Runtime configuration that can be modified during session
class RuntimeConfig {
    var systemPrompt: String
    var temperature: Double
    var maxTokens: Int
    var verbose: Bool
    var toolsEnabled: Bool
    var currentModel: String?
    var responseFormat: ResponseFormatMode
    var citationsEnabled: Bool
    var reliabilityEnabled: Bool

    // Anthropic settings
    var thinkingEnabled: Bool
    var thinkingBudget: Int
    var betaFeatures: Set<String>

    // Video attachment for next message
    var pendingVideoURL: String?
    var pendingVideoFilePath: String?
    var pendingVideoData: Data?
    var pendingVideoMimeType: String?
    var pendingVideoDisplayName: String?

    // Unified reasoning (all providers)
    var reasoningEffort: String?

    // Provider-agnostic built-in tools
    var activeBuiltInTools: [BuiltInTool] = []

    // OpenAI Responses API specific settings
    var webSearchEnabled: Bool = false
    var codeInterpreterEnabled: Bool = false
    var storeResponses: Bool = false
    var previousResponseId: String? = nil
    var uploadedFileIds: [String] = []

    init(from options: CLIOptions) {
        self.systemPrompt = options.systemPrompt ?? "You are a helpful AI assistant."
        self.temperature = options.temperature
        self.maxTokens = options.maxTokens
        self.verbose = options.verbose
        self.toolsEnabled = !options.noTools
        self.currentModel = options.model
        self.responseFormat = options.responseFormat
        self.citationsEnabled = options.citationsEnabled
        self.reliabilityEnabled = options.reliabilityEnabled
        self.thinkingEnabled = options.thinkingEnabled
        self.thinkingBudget = options.thinkingBudget
        self.betaFeatures = options.betaFeatures
        self.pendingVideoURL = options.videoURL
        self.reasoningEffort = options.reasoningEffort
        self.activeBuiltInTools = Self.parseBuiltInToolNames(options.builtInToolNames)
    }

    static func parseBuiltInToolNames(_ names: [String]) -> [BuiltInTool] {
        var tools: [BuiltInTool] = []
        for name in names {
            switch name {
            case "websearch", "web-search", "web_search":
                tools.append(.webSearchDefault)
            case "code", "codeexecution", "code-execution", "code_execution":
                tools.append(.codeExecutionDefault)
            case "urlcontext", "url-context", "url_context":
                tools.append(.urlContext)
            default:
                print(ANSIStyles.warning("Unknown built-in tool: '\(name)'. Available: websearch, code, urlcontext"))
            }
        }
        return tools
    }

    func clearPendingVideo() {
        pendingVideoURL = nil
        pendingVideoFilePath = nil
        pendingVideoData = nil
        pendingVideoMimeType = nil
        pendingVideoDisplayName = nil
    }
}

enum ResponseFormatMode: String {
    case text
    case json
    case schema
    case ui
}
