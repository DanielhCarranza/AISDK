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

    if let renderPath = options.renderUIJSONPath {
        renderUIJSON(at: renderPath)
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

// MARK: - UI JSON Rendering

func renderUIJSON(at path: String) {
    let expandedPath = NSString(string: path).expandingTildeInPath
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
        let tree = try UITree.parse(from: data, validatingWith: UICatalog.extended)
        let renderer = TerminalUIRenderer()
        let rendered = try renderer.render(tree: tree)
        print(rendered)
    } catch {
        print(ANSIStyles.error("Failed to render UI JSON: \(error.localizedDescription)"))
    }
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

    case .openai:
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !key.isEmpty else {
            print(ANSIStyles.error("OPENAI_API_KEY not found!"))
            print("""

            Please set your API key using one of these methods:

            \(ANSIStyles.dim("1. Environment variable:"))
               export OPENAI_API_KEY=your_key_here

            \(ANSIStyles.dim("2. Create a .env file:"))
               echo "OPENAI_API_KEY=your_key_here" > .env

            Get your API key at: \(ANSIStyles.cyan("https://platform.openai.com/api-keys"))
            """)
            return false
        }
        return true

    case .anthropic:
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !key.isEmpty else {
            print(ANSIStyles.error("ANTHROPIC_API_KEY not found!"))
            print("""

            Please set your API key using one of these methods:

            \(ANSIStyles.dim("1. Environment variable:"))
               export ANTHROPIC_API_KEY=your_key_here

            \(ANSIStyles.dim("2. Create a .env file:"))
               echo "ANTHROPIC_API_KEY=your_key_here" > .env

            Get your API key at: \(ANSIStyles.cyan("https://console.anthropic.com/"))
            """)
            return false
        }
        return true

    case .gemini:
        guard let key = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"],
              !key.isEmpty else {
            print(ANSIStyles.error("GOOGLE_API_KEY not found!"))
            print("""

            Please set your API key using one of these methods:

            \(ANSIStyles.dim("1. Environment variable:"))
               export GOOGLE_API_KEY=your_key_here

            \(ANSIStyles.dim("2. Create a .env file:"))
               echo "GOOGLE_API_KEY=your_key_here" > .env

            Get your API key at: \(ANSIStyles.cyan("https://aistudio.google.com/apikey"))
            """)
            return false
        }
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
        --provider <type>     Provider: openrouter (default), litellm, openai, anthropic, or gemini
        --model <id>          Pre-select a model (skip interactive selection)
        --system <prompt>     Set custom system prompt
        --temperature <num>   Temperature (0.0-2.0, default: 0.7)
        --max-tokens <num>    Max tokens per response (default: 4096)
        --verbose             Show detailed output (API calls, timing)
        --no-tools            Disable built-in tools
        --format <mode>       Response format: text|json|schema|ui
        --render-ui-json <p>  Render a UI JSON file and exit
        --citations           Enable citations (default on)
        --no-citations        Disable citations
        --reliable            Enable reliability/failover layer
        --video <input>       Attach a video URL, local path, or "demo" to the first message
        --thinking [budget]   Enable Anthropic extended thinking (default budget: 10000)
        --beta <features>     Enable Anthropic beta features (space-separated)
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
        /video <input>        Attach video URL, local path, or "demo" to next message

    \(ANSIStyles.bold("INPUT MODES:"))
        Single line           Press Enter to send
        Multi-line            Start with ``` to enter multi-line mode
                              End with ``` to send

    \(ANSIStyles.bold("ENVIRONMENT VARIABLES:"))
        OPENROUTER_API_KEY    Required for OpenRouter provider
        OPENAI_API_KEY        Required for OpenAI provider (Responses API testing)
        ANTHROPIC_API_KEY     Required for Anthropic provider
        GOOGLE_API_KEY        Required for Gemini provider
        LITELLM_BASE_URL      LiteLLM server URL (default: http://localhost:4000)
        LITELLM_API_KEY       Optional API key for LiteLLM
        TAVILY_API_KEY        Required for web_search tool

    \(ANSIStyles.bold("OPENAI TESTING COMMANDS:")) (use --provider openai)
        /websearch on|off     Toggle web search tool
        /code on|off          Toggle code interpreter tool
        /store on|off         Toggle response storage
        /continue <id>        Continue from previous response ID
        /files                List uploaded files

    \(ANSIStyles.bold("EXAMPLES:"))
        swift run AISDKCLI
        swift run AISDKCLI --provider litellm
        swift run AISDKCLI --provider openai --model gpt-4o-mini
        swift run AISDKCLI --model anthropic/claude-3-5-sonnet
        swift run AISDKCLI --system "You are a Python expert"
        swift run AISDKCLI --provider gemini --video demo
        swift run AISDKCLI --video https://example.com/clip.mp4
    """)
}
