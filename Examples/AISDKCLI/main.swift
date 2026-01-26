//
//  main.swift
//  AISDKCLI
//
//  Interactive terminal AI assistant powered by OpenRouter/LiteLLM
//  Supports model selection, streaming conversations, reasoning display,
//  tool execution, and GenerativeUI rendering
//

import Foundation
import AISDK

// MARK: - Entry Point

// Bridge async code to sync main
let semaphore = DispatchSemaphore(value: 0)

Task {
    await runCLI()
    semaphore.signal()
}

semaphore.wait()

// MARK: - Main CLI Runner

func runCLI() async {
    // Load environment variables from .env files
    loadEnvironmentVariables()

    // Parse command line options
    let options = CLIOptions.parse()

    // Handle help flag
    if options.showHelp {
        printUsage()
        return
    }

    // Validate API keys
    guard validateAPIKeys(for: options.provider) else {
        return
    }

    // Print welcome banner
    printWelcomeBanner()

    // Create and run the CLI controller
    let controller = CLIController(options: options)
    await controller.run()
}

// MARK: - Environment Loading

func loadEnvironmentVariables() {
    let paths = [".env", "../.env", "../../.env", "~/.config/aisdk/.env"]

    for path in paths {
        let expandedPath = NSString(string: path).expandingTildeInPath
        if let content = try? String(contentsOfFile: expandedPath) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count >= 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = parts[1...].joined(separator: "=")
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        setenv(key, value, 0) // 0 = don't overwrite existing
                    }
                }
            }
            return
        }
    }
}

// MARK: - API Key Validation

func validateAPIKeys(for provider: ProviderType) -> Bool {
    switch provider {
    case .openrouter:
        guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
              !key.isEmpty else {
            print(ANSIStyles.error("OPENROUTER_API_KEY not found!"))
            print("""

            Please set your API key using one of these methods:

            \(ANSIStyles.dim("1. Environment variable:"))
               export OPENROUTER_API_KEY=your_key_here

            \(ANSIStyles.dim("2. Create a .env file:"))
               echo "OPENROUTER_API_KEY=your_key_here" > .env

            Get your API key at: \(ANSIStyles.cyan("https://openrouter.ai/keys"))
            """)
            return false
        }
        return true

    case .litellm:
        // LiteLLM may not require an API key for local deployments
        if let baseURL = ProcessInfo.processInfo.environment["LITELLM_BASE_URL"],
           !baseURL.isEmpty {
            return true
        }
        print(ANSIStyles.warning("LITELLM_BASE_URL not set, using default: http://localhost:4000"))
        return true
    }
}

// MARK: - Welcome Banner

func printWelcomeBanner() {
    let banner = """

    \(ANSIStyles.cyan("╔═══════════════════════════════════════════════════════════════╗"))
    \(ANSIStyles.cyan("║")) \(ANSIStyles.bold("    █████╗ ██╗███████╗██████╗ ██╗  ██╗"))                        \(ANSIStyles.cyan("║"))
    \(ANSIStyles.cyan("║")) \(ANSIStyles.bold("   ██╔══██╗██║██╔════╝██╔══██╗██║ ██╔╝"))                        \(ANSIStyles.cyan("║"))
    \(ANSIStyles.cyan("║")) \(ANSIStyles.bold("   ███████║██║███████╗██║  ██║█████╔╝"))                         \(ANSIStyles.cyan("║"))
    \(ANSIStyles.cyan("║")) \(ANSIStyles.bold("   ██╔══██║██║╚════██║██║  ██║██╔═██╗"))                         \(ANSIStyles.cyan("║"))
    \(ANSIStyles.cyan("║")) \(ANSIStyles.bold("   ██║  ██║██║███████║██████╔╝██║  ██╗"))                        \(ANSIStyles.cyan("║"))
    \(ANSIStyles.cyan("║")) \(ANSIStyles.bold("   ╚═╝  ╚═╝╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝"))  \(ANSIStyles.dim("CLI v1.0"))         \(ANSIStyles.cyan("║"))
    \(ANSIStyles.cyan("║"))                                                               \(ANSIStyles.cyan("║"))
    \(ANSIStyles.cyan("║"))   \(ANSIStyles.white("Interactive AI Assistant - Powered by OpenRouter/LiteLLM"))   \(ANSIStyles.cyan("║"))
    \(ANSIStyles.cyan("╚═══════════════════════════════════════════════════════════════╝"))

    """
    print(banner)
}

// MARK: - Usage

func printUsage() {
    print("""
    \(ANSIStyles.bold("AISDK CLI")) - Interactive AI Assistant

    \(ANSIStyles.bold("USAGE:"))
        swift run AISDKCLI [OPTIONS]

    \(ANSIStyles.bold("OPTIONS:"))
        --provider <type>     Provider: openrouter (default) or litellm
        --model <id>          Pre-select a model (skip interactive selection)
        --system <prompt>     Set custom system prompt
        --temperature <num>   Temperature (0.0-2.0, default: 0.7)
        --max-tokens <num>    Max tokens per response (default: 4096)
        --verbose             Show detailed output (API calls, timing)
        --no-tools            Disable built-in tools
        --format <mode>       Response format: text|json|schema|ui
        --citations           Enable citations (default on)
        --no-citations        Disable citations
        --reliable            Enable reliability/failover layer
        --help, -h            Show this help

    \(ANSIStyles.bold("INTERACTIVE COMMANDS:"))
        /help                 Show available commands
        /exit, /quit          Exit the CLI
        /clear                Clear conversation history
        /model                Change current model
        /system <prompt>      Set system prompt
        /tokens               Show token usage
        /save <filename>      Save conversation to file
        /load <filename>      Load conversation from file
        /verbose              Toggle verbose mode
        /format <mode>        Set response format (text|json|schema|ui)
        /citations on|off     Toggle citations rendering
        /reliable on|off      Toggle reliability mode

    \(ANSIStyles.bold("INPUT MODES:"))
        Single line           Press Enter to send
        Multi-line            Start with ``` to enter multi-line mode
                              End with ``` to send

    \(ANSIStyles.bold("ENVIRONMENT VARIABLES:"))
        OPENROUTER_API_KEY    Required for OpenRouter provider
        LITELLM_BASE_URL      LiteLLM server URL (default: http://localhost:4000)
        LITELLM_API_KEY       Optional API key for LiteLLM
        TAVILY_API_KEY        Required for web_search tool

    \(ANSIStyles.bold("EXAMPLES:"))
        swift run AISDKCLI
        swift run AISDKCLI --provider litellm
        swift run AISDKCLI --model anthropic/claude-3-5-sonnet
        swift run AISDKCLI --system "You are a Python expert"
    """)
}
