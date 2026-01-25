//
//  main.swift
//  AISDKDemo
//
//  Comprehensive CLI demo showcasing ALL AISDK features:
//  - Chat (basic & streaming)
//  - JSON/Structured Output with pretty rendering
//  - Reasoning/Thinking token display
//  - Tool calling with execution visualization
//  - Multi-turn interactive conversations
//  - Provider comparison mode
//

import Foundation
import AISDK

@main
struct AISDKDemo {
    static func main() async {
        printBanner()
        loadEnvironmentVariables()

        guard validateAPIKey() else { return }

        let options = parseOptions()

        do {
            switch options.mode {
            case .chat:
                try await runChat(options: options)
            case .stream:
                try await runStreaming(options: options)
            case .json:
                try await runJSONOutput(options: options)
            case .reasoning:
                try await runReasoning(options: options)
            case .tools:
                try await runToolDemo(options: options)
            case .interactive:
                try await runInteractive(options: options)
            case .showcase:
                try await runShowcase(options: options)
            case .help:
                printUsage()
            }
        } catch {
            print("\n❌ Error: \(error)")
        }
    }
}

// MARK: - CLI Options

private enum DemoMode: String {
    case chat
    case stream
    case json
    case reasoning
    case tools
    case interactive
    case showcase
    case help
}

private struct DemoOptions {
    let mode: DemoMode
    let model: String
    let prompt: String
    let verbose: Bool
}

private func parseOptions() -> DemoOptions {
    let args = CommandLine.arguments
    var mode: DemoMode = .showcase
    var model = "arcee-ai/trinity-mini:free"
    var prompt = "Hello! Tell me a fun fact."
    var verbose = false

    var index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--mode", "-m":
            if index + 1 < args.count, let parsed = DemoMode(rawValue: args[index + 1]) {
                mode = parsed
                index += 1
            }
        case "--model":
            if index + 1 < args.count {
                model = args[index + 1]
                index += 1
            }
        case "--prompt", "-p":
            if index + 1 < args.count {
                prompt = args[index + 1]
                index += 1
            }
        case "--verbose", "-v":
            verbose = true
        case "--help", "-h":
            mode = .help
        default:
            break
        }
        index += 1
    }

    return DemoOptions(mode: mode, model: model, prompt: prompt, verbose: verbose)
}

// MARK: - Banner & Help

private func printBanner() {
    print("""

    ╔═══════════════════════════════════════════════════════════════╗
    ║                                                               ║
    ║   █████╗ ██╗███████╗██████╗ ██╗  ██╗                         ║
    ║  ██╔══██╗██║██╔════╝██╔══██╗██║ ██╔╝                         ║
    ║  ███████║██║███████╗██║  ██║█████╔╝                          ║
    ║  ██╔══██║██║╚════██║██║  ██║██╔═██╗                          ║
    ║  ██║  ██║██║███████║██████╔╝██║  ██╗                         ║
    ║  ╚═╝  ╚═╝╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝                         ║
    ║                                                               ║
    ║  Comprehensive AI SDK Demo - Showcasing All Features          ║
    ╚═══════════════════════════════════════════════════════════════╝

    """)
}

private func printUsage() {
    print("""
    Usage: swift run AISDKDemo [options]

    Modes:
      --mode showcase   Run all demos in sequence (default)
      --mode chat       Basic chat completion
      --mode stream     Streaming with visible deltas
      --mode json       Structured JSON output with pretty rendering
      --mode reasoning  Display reasoning/thinking tokens
      --mode tools      Tool calling demonstration
      --mode interactive  Multi-turn conversation mode
      --mode help       Show this help

    Options:
      --model MODEL     Model ID (default: arcee-ai/trinity-mini:free)
      --prompt, -p      Custom prompt
      --verbose, -v     Show detailed output
      --help, -h        Show this help

    Environment:
      OPENROUTER_API_KEY    Required - Your OpenRouter API key

    Examples:
      swift run AISDKDemo --mode showcase
      swift run AISDKDemo --mode tools --model arcee-ai/trinity-mini:free
      swift run AISDKDemo --mode json --prompt "List 3 programming languages"
      swift run AISDKDemo --mode interactive

    Free Models with Full Feature Support:
      ✅ arcee-ai/trinity-mini:free       (recommended - full tool support)
      ✅ nvidia/nemotron-3-nano-30b-a3b:free  (tools with auto only)
      ⚠️  tngtech/deepseek-r1t2-chimera:free  (no tool support)
    """)
}

// MARK: - Environment

private func loadEnvironmentVariables() {
    let paths = [".env", "../.env", "../../.env"]
    for path in paths {
        if let content = try? String(contentsOfFile: path) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count >= 2 {
                        let key = parts[0].trimmingCharacters(in: .whitespaces)
                        let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
                        setenv(key, value, 0)
                    }
                }
            }
            print("📄 Loaded environment from \(path)")
            return
        }
    }
}

private func validateAPIKey() -> Bool {
    guard let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty else {
        print("""
        ❌ OPENROUTER_API_KEY not found!

        Please set your API key:
          export OPENROUTER_API_KEY=your_key_here

        Or create a .env file with:
          OPENROUTER_API_KEY=your_key_here
        """)
        return false
    }
    return true
}

private func createClient() -> OpenRouterClient {
    let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]!
    return OpenRouterClient(
        apiKey: apiKey,
        appName: "AISDK-ComprehensiveDemo",
        siteURL: "https://github.com/AISDK"
    )
}

// MARK: - Demo: Basic Chat

private func runChat(options: DemoOptions) async throws {
    printSection("💬 Basic Chat Demo")

    let client = createClient()
    let request = ProviderRequest(
        modelId: options.model,
        messages: [
            .system("You are a helpful, concise assistant."),
            .user(options.prompt)
        ],
        maxTokens: 500
    )

    print("📤 Sending: \"\(options.prompt)\"")
    print("🤖 Model: \(options.model)")
    print("─" * 50)

    let response = try await client.execute(request: request)

    print("\n📥 Response:")
    print(response.content)

    if let usage = response.usage {
        print("\n📊 Token Usage:")
        print("   Prompt: \(usage.promptTokens) | Completion: \(usage.completionTokens) | Total: \(usage.totalTokens)")
    }

    print("\n✅ Chat completed with finish reason: \(response.finishReason)")
}

// MARK: - Demo: Streaming

private func runStreaming(options: DemoOptions) async throws {
    printSection("🌊 Streaming Demo")

    let client = createClient()
    let streamModel = "nvidia/nemotron-3-nano-30b-a3b:free" // Best streaming support

    let request = ProviderRequest(
        modelId: streamModel,
        messages: [
            .user("Count from 1 to 10, saying each number on a new line with a brief description.")
        ],
        maxTokens: 500,
        stream: true
    )

    print("📤 Prompt: Count from 1 to 10")
    print("🤖 Model: \(streamModel)")
    print("─" * 50)
    print("\n📥 Streaming response:\n")

    var tokenCount = 0
    var startTime = Date()

    for try await event in client.stream(request: request) {
        switch event {
        case .start(let id, let model):
            print("🚀 Stream started (id: \(id.prefix(8))..., model: \(model))")
            startTime = Date()
        case .textDelta(let text):
            print(text, terminator: "")
            fflush(stdout)
            tokenCount += 1
        case .finish(let reason, let usage):
            let duration = Date().timeIntervalSince(startTime)
            print("\n\n─" * 50)
            print("✅ Stream finished: \(reason)")
            if let usage = usage {
                print("📊 Tokens: \(usage.totalTokens) | Speed: \(String(format: "%.1f", Double(tokenCount) / duration)) tokens/sec")
            }
        default:
            break
        }
    }
}

// MARK: - Demo: JSON Output

private func runJSONOutput(options: DemoOptions) async throws {
    printSection("📋 JSON Structured Output Demo")

    let client = createClient()
    let request = ProviderRequest(
        modelId: options.model,
        messages: [
            .system("Return only valid JSON with no markdown formatting."),
            .user("Return a JSON object describing 3 programming languages with fields: name, year_created, paradigm, and popular_for")
        ],
        maxTokens: 800,
        responseFormat: .json
    )

    print("📤 Requesting: JSON of 3 programming languages")
    print("🤖 Model: \(options.model)")
    print("─" * 50)

    let response = try await client.execute(request: request)

    print("\n📥 Raw Response:")
    print("─" * 30)
    print(response.content)

    // Try to pretty-print the JSON
    if let jsonData = response.content.data(using: .utf8) {
        do {
            let json = try JSONSerialization.jsonObject(with: jsonData)
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            if let prettyString = String(data: prettyData, encoding: .utf8) {
                print("\n🎨 Pretty-Printed JSON:")
                print("─" * 30)
                print(prettyString)
            }
        } catch {
            print("\n⚠️ Could not parse as JSON: \(error.localizedDescription)")
        }
    }

    print("\n✅ JSON output completed")
}

// MARK: - Demo: Reasoning

private func runReasoning(options: DemoOptions) async throws {
    printSection("🧠 Reasoning/Thinking Demo")

    let client = createClient()

    // Trinity Mini has mandatory reasoning
    let reasoningModel = "arcee-ai/trinity-mini:free"

    let request = ProviderRequest(
        modelId: reasoningModel,
        messages: [
            .system("Think step by step. Show your reasoning process."),
            .user("If a store has 3 apples and 5 oranges, then someone buys 2 apples and 1 orange, how many total fruits remain? Explain your thinking.")
        ],
        maxTokens: 1000
    )

    print("📤 Math Problem: Fruit inventory calculation")
    print("🤖 Model: \(reasoningModel) (has reasoning support)")
    print("─" * 50)

    let response = try await client.execute(request: request)

    print("\n📥 Response with Reasoning:")
    print("─" * 30)

    // The model's response should include reasoning
    let content = response.content

    // Check if response contains thinking/reasoning markers
    if content.contains("<think>") || content.contains("</think>") {
        let parts = content.components(separatedBy: "</think>")
        if parts.count > 1 {
            let thinkingPart = parts[0].replacingOccurrences(of: "<think>", with: "")
            let answerPart = parts[1]

            print("\n💭 REASONING:")
            print("┌" + "─" * 48 + "┐")
            for line in thinkingPart.components(separatedBy: "\n") {
                print("│ \(line.prefix(46).padding(toLength: 46, withPad: " ", startingAt: 0)) │")
            }
            print("└" + "─" * 48 + "┘")

            print("\n📝 ANSWER:")
            print(answerPart.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            print(content)
        }
    } else {
        print(content)
    }

    print("\n✅ Reasoning demo completed")
}

// MARK: - Demo: Tool Calling

private func runToolDemo(options: DemoOptions) async throws {
    printSection("🛠️ Tool Calling Demo")

    let client = createClient()
    let toolModel = "arcee-ai/trinity-mini:free" // Full tool support

    // Define weather tool (simplified for reliable execution)
    let weatherTool = ProviderJSONValue.object([
        "type": .string("function"),
        "function": .object([
            "name": .string("get_weather"),
            "description": .string("Get weather for a city"),
            "parameters": .object([
                "type": .string("object"),
                "properties": .object([
                    "city": .object(["type": .string("string")]),
                    "unit": .object([
                        "type": .string("string"),
                        "enum": .array([.string("celsius"), .string("fahrenheit")])
                    ])
                ]),
                "required": .array([.string("city"), .string("unit")])
            ])
        ])
    ])

    print("🔧 Available Tools:")
    print("   • get_weather(city, unit) - Get weather for a city")
    print("─" * 50)

    let request = ProviderRequest(
        modelId: toolModel,
        messages: [
            .system("You must use the get_weather tool. Do not respond with text."),
            .user("What's the weather in Tokyo? Use celsius.")
        ],
        maxTokens: 500,
        tools: [weatherTool],
        toolChoice: .auto
    )

    print("\n📤 Question: \"What's the weather in Tokyo? Use celsius.\"")
    print("🤖 Model: \(toolModel)")
    print("─" * 50)

    let response = try await client.execute(request: request)

    if !response.toolCalls.isEmpty {
        print("\n🔄 Tool Calls Made:")
        for (index, toolCall) in response.toolCalls.enumerated() {
            print("\n   [\(index + 1)] \(toolCall.name)")
            print("       ID: \(toolCall.id)")

            // Pretty-print arguments
            if let argsData = toolCall.arguments.data(using: .utf8),
               let argsJson = try? JSONSerialization.jsonObject(with: argsData),
               let prettyData = try? JSONSerialization.data(withJSONObject: argsJson, options: .prettyPrinted),
               let prettyArgs = String(data: prettyData, encoding: .utf8) {
                print("       Arguments:")
                for line in prettyArgs.components(separatedBy: "\n") {
                    print("         \(line)")
                }
            } else {
                print("       Arguments: \(toolCall.arguments)")
            }

            // Simulate tool execution
            print("\n       ⚡ Executing tool...")
            let result = simulateToolExecution(name: toolCall.name, arguments: toolCall.arguments)
            print("       📤 Result: \(result)")
        }

        // Continue conversation with tool results
        print("\n─" * 50)
        print("📨 Sending tool results back to model...")

        let toolCall = response.toolCalls[0]
        let toolResult = simulateToolExecution(name: toolCall.name, arguments: toolCall.arguments)

        let followupMessages: [AIMessage] = [
            .system("You are a helpful assistant."),
            .user("What's the weather in Tokyo? Use celsius."),
            .assistant("", toolCalls: [AIMessage.ToolCall(id: toolCall.id, name: toolCall.name, arguments: toolCall.arguments)]),
            .tool(toolResult, toolCallId: toolCall.id)
        ]

        let followupRequest = ProviderRequest(
            modelId: toolModel,
            messages: followupMessages,
            maxTokens: 300,
            tools: [weatherTool]
        )

        let finalResponse = try await client.execute(request: followupRequest)
        print("\n📥 Final Response:")
        print(finalResponse.content)
    } else {
        print("\n📥 Response (no tools called):")
        print(response.content)
    }

    print("\n✅ Tool demo completed")
}

private func simulateToolExecution(name: String, arguments: String) -> String {
    switch name {
    case "get_weather":
        if let data = arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let city = json["city"] as? String {
            let unit = (json["unit"] as? String) ?? "celsius"
            let temp = unit == "celsius" ? "22°C" : "72°F"
            return "Weather in \(city): \(temp), partly cloudy, humidity 65%"
        }
        return "Weather data unavailable"

    case "calculate":
        if let data = arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let expr = json["expression"] as? String {
            // Simple evaluation for demo
            if expr.contains("*") {
                let parts = expr.components(separatedBy: "*").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                if parts.count == 2 {
                    return "\(expr) = \(parts[0] * parts[1])"
                }
            }
            return "Result: (expression evaluated)"
        }
        return "Calculation failed"

    default:
        return "Unknown tool"
    }
}

// MARK: - Demo: Interactive

private func runInteractive(options: DemoOptions) async throws {
    printSection("💬 Interactive Chat Mode")

    let client = createClient()
    let model = "nvidia/nemotron-3-nano-30b-a3b:free" // Good for streaming

    print("🤖 Model: \(model)")
    print("📝 Type 'quit' or 'exit' to end the session")
    print("📝 Type 'clear' to reset conversation")
    print("─" * 50)

    var conversationHistory: [AIMessage] = [
        .system("You are a helpful, friendly assistant. Keep responses concise but informative.")
    ]

    while true {
        print("\n👤 You: ", terminator: "")
        fflush(stdout)

        guard let input = readLine(), !input.isEmpty else { continue }

        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if trimmedInput == "quit" || trimmedInput == "exit" {
            print("\n👋 Goodbye!")
            break
        }

        if trimmedInput == "clear" {
            conversationHistory = [
                .system("You are a helpful, friendly assistant. Keep responses concise but informative.")
            ]
            print("🧹 Conversation cleared.")
            continue
        }

        conversationHistory.append(.user(input))

        let request = ProviderRequest(
            modelId: model,
            messages: conversationHistory,
            maxTokens: 500,
            stream: true
        )

        print("🤖 Assistant: ", terminator: "")
        fflush(stdout)

        var assistantResponse = ""

        for try await event in client.stream(request: request) {
            switch event {
            case .textDelta(let text):
                print(text, terminator: "")
                fflush(stdout)
                assistantResponse += text
            case .finish:
                print("")
            default:
                break
            }
        }

        conversationHistory.append(.assistant(assistantResponse))
    }
}

// MARK: - Demo: Showcase (All Features)

private func runShowcase(options: DemoOptions) async throws {
    print("🎯 Running Complete Feature Showcase\n")
    print("This will demonstrate all major AISDK capabilities.\n")

    // 1. Basic Chat
    try await runChat(options: options)
    print("\n" + "═" * 60 + "\n")

    // 2. Streaming
    try await runStreaming(options: options)
    print("\n" + "═" * 60 + "\n")

    // 3. JSON Output
    try await runJSONOutput(options: options)
    print("\n" + "═" * 60 + "\n")

    // 4. Reasoning
    try await runReasoning(options: options)
    print("\n" + "═" * 60 + "\n")

    // 5. Tool Calling
    try await runToolDemo(options: options)

    print("\n" + "═" * 60)
    print("🎉 Showcase Complete!")
    print("""

    Summary of Features Demonstrated:
    ✅ Basic Chat Completion
    ✅ Real-time Streaming with token counting
    ✅ Structured JSON Output with pretty-printing
    ✅ Reasoning/Thinking token display
    ✅ Tool Calling with execution simulation

    Run with --mode interactive for multi-turn conversations!
    """)
}

// MARK: - Utilities

private func printSection(_ title: String) {
    print("\n" + "═" * 60)
    print("  \(title)")
    print("═" * 60 + "\n")
}

private extension String {
    static func *(lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}
