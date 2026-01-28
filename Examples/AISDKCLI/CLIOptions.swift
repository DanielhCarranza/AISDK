//
//  CLIOptions.swift
//  AISDKCLI
//
//  Command line argument parsing and configuration
//

import Foundation

/// Provider type selection
enum ProviderType: String {
    case openrouter
    case litellm
    case openai  // Direct OpenAI Responses API for testing
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

    /// Enable citations rendering
    var citationsEnabled: Bool = true

    /// Enable reliability/failover layer
    var reliabilityEnabled: Bool = false

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

            case "--citations":
                options.citationsEnabled = true

            case "--no-citations":
                options.citationsEnabled = false

            case "--reliable":
                options.reliabilityEnabled = true

            case "--help", "-h":
                options.showHelp = true

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
    }
}

enum ResponseFormatMode: String {
    case text
    case json
    case schema
    case ui
}
