//
//  main.swift
//  OpenRouterDemo
//
//  CLI demo for OpenRouter-backed AISDK flows
//

import Foundation
import AISDK

@main
struct OpenRouterDemo {
    static func main() async {
        print("🤖 AISDK OpenRouter Demo")
        print("=" * 40)

        loadEnvironmentVariables()

        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
              !apiKey.isEmpty else {
            print("❌ Please set OPENROUTER_API_KEY environment variable")
            print("   Option 1: Create a .env file in the root directory with:")
            print("   OPENROUTER_API_KEY=your_key_here")
            print("   ")
            print("   Option 2: Export environment variable:")
            print("   export OPENROUTER_API_KEY=your_key_here")
            print("   ")
            print("   Option 3: Run with inline environment variable:")
            print("   OPENROUTER_API_KEY=your_key_here swift run OpenRouterDemo")
            return
        }

        let options = parseOptions()
        let client = OpenRouterClient(
            apiKey: apiKey,
            appName: "AISDK-OpenRouterDemo",
            siteURL: "https://github.com/AISDK"
        )

        do {
            switch options.mode {
            case .chat:
                try await runChat(client: client, model: options.model, prompt: options.prompt)
            case .stream:
                try await runStream(client: client, model: options.model, prompt: options.prompt)
            case .json:
                try await runJSON(client: client, model: options.model)
            case .tools:
                // Use tool-capable model if user didn't specify one
                let toolModel = options.modelWasExplicit ? options.model : resolvedToolModel()
                try await runToolFlow(client: client, model: toolModel)
            case .reasoning:
                try await runReasoning(client: client, model: options.model)
            case .interactive:
                try await runInteractive(client: client, model: options.model)
            case .all:
                try await runChat(client: client, model: options.model, prompt: options.prompt)
                try await runStream(client: client, model: options.model, prompt: options.prompt)
                try await runJSON(client: client, model: options.model)
                try await runReasoning(client: client, model: options.model)
                // Use tool-capable model for tool flow in "all" mode
                let toolModel = options.modelWasExplicit ? options.model : resolvedToolModel()
                try await runToolFlow(client: client, model: toolModel)
            }
        } catch {
            print("❌ Error: \(error)")
        }
    }
}

// MARK: - CLI Options

private enum DemoMode: String {
    case chat
    case stream
    case json
    case tools
    case reasoning
    case interactive
    case all
}

private struct DemoOptions {
    let mode: DemoMode
    let model: String
    let prompt: String
    let modelWasExplicit: Bool  // True if user specified --model
}

private func parseOptions() -> DemoOptions {
    let args = CommandLine.arguments
    let defaultModel = resolvedDefaultModel()
    var mode: DemoMode = .all
    var model = defaultModel
    var prompt = "Hello! Give me a short response."
    var modelWasExplicit = false

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
                modelWasExplicit = true
                index += 1
            }
        case "--prompt", "-p":
            if index + 1 < args.count {
                prompt = args[index + 1]
                index += 1
            }
        case "--interactive":
            mode = .interactive
        case "--help", "-h":
            printUsage(defaultModel: defaultModel)
            exit(0)
        default:
            break
        }
        index += 1
    }

    return DemoOptions(mode: mode, model: model, prompt: prompt, modelWasExplicit: modelWasExplicit)
}

private func printUsage(defaultModel: String) {
    print("""
    Usage: swift run OpenRouterDemo [options]

    Options:
      --mode, -m        chat | stream | json | tools | reasoning | interactive | all (default: all)
      --model           OpenRouter model id (default: \(defaultModel))
      --prompt, -p      Prompt for chat/stream (default: "Hello! Give me a short response.")
      --interactive     Start an interactive chat session
      --help, -h        Show this help

    Environment:
      OPENROUTER_API_KEY        Required
      OPENROUTER_DEFAULT_MODEL  Optional default model id override
      OPENROUTER_TOOL_MODEL     Optional model for tool calling (default: arcee-ai/trinity-mini:free)

    Tool Calling Model Compatibility (free tier):
      ✅ arcee-ai/trinity-mini:free       Full tool support (recommended)
      ✅ nvidia/nemotron-3-nano-30b-a3b:free  Works with tool_choice: auto
      ❌ tngtech/deepseek-r1t2-chimera:free   No tool support on free tier

    Examples:
      OPENROUTER_API_KEY=... swift run OpenRouterDemo --mode chat --model tngtech/deepseek-r1t2-chimera:free
      OPENROUTER_API_KEY=... swift run OpenRouterDemo --mode stream --prompt "Count to 5."
      OPENROUTER_API_KEY=... swift run OpenRouterDemo --mode tools  # Uses Trinity Mini by default
    """)
}

private func resolvedDefaultModel() -> String {
    if let override = ProcessInfo.processInfo.environment["OPENROUTER_DEFAULT_MODEL"],
       !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return override
    }
    return "tngtech/deepseek-r1t2-chimera:free"
}

/// Returns the best model for tool calling
/// Note: DeepSeek R1T2 Chimera free tier doesn't support tool calling
/// Nemotron works with tool_choice: "auto" but not specific tool forcing
/// Trinity Mini has full tool calling support
private func resolvedToolModel() -> String {
    if let override = ProcessInfo.processInfo.environment["OPENROUTER_TOOL_MODEL"],
       !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return override
    }
    return "arcee-ai/trinity-mini:free"
}

// MARK: - Demo Routines

private func runChat(client: OpenRouterClient, model: String, prompt: String) async throws {
    print("\n📝 Chat (\(model))")
    let request = ProviderRequest(
        modelId: model,
        messages: [
            .system("You are a helpful assistant. Keep responses brief."),
            .user(prompt)
        ],
        maxTokens: 200
    )

    let response = try await client.execute(request: request)
    print("✅ Response: \(response.content)")
}

private func runStream(client: OpenRouterClient, model: String, prompt: String) async throws {
    print("\n🔄 Stream (\(model))")
    let request = ProviderRequest(
        modelId: model,
        messages: [
            .user(prompt)
        ],
        maxTokens: 200,
        stream: true
    )

    print("📡 Streaming: ", terminator: "")
    for try await event in client.stream(request: request) {
        switch event {
        case .textDelta(let text):
            print(text, terminator: "")
            fflush(stdout)
        case .finish:
            print("")
        default:
            break
        }
    }
}

private func runJSON(client: OpenRouterClient, model: String) async throws {
    print("\n🧾 JSON Output (\(model))")
    let request = ProviderRequest(
        modelId: model,
        messages: [
            .system("Return only JSON, no code fences."),
            .user("Return {\"city\": \"Boston\", \"temp_c\": 21, \"unit\": \"celsius\"}.")
        ],
        maxTokens: 120,
        responseFormat: .json
    )

    let response = try await client.execute(request: request)
    print("✅ Raw: \(response.content)")
}

private func runReasoning(client: OpenRouterClient, model: String) async throws {
    print("\n🧠 Reasoning (\(model))")
    print("ℹ️  Note: We do not request chain-of-thought. Only a short justification.")
    let request = ProviderRequest(
        modelId: model,
        messages: [
            .system("Provide a short justification. Do not reveal chain-of-thought."),
            .user("If a train travels 60 miles in 1.5 hours, what is its average speed?")
        ],
        maxTokens: 120
    )

    let response = try await client.execute(request: request)
    print("✅ Response: \(response.content)")
}

private func runToolFlow(client: OpenRouterClient, model: String) async throws {
    print("\n🛠️ Tool Flow (\(model))")

    let tool = ProviderJSONValue.object([
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

    // Use tool_choice: "auto" for broader model compatibility
    // Note: Forcing a specific tool with .tool(name:) only works on some models
    // (e.g., Trinity Mini supports it, but Nemotron and DeepSeek free tiers don't)
    let request = ProviderRequest(
        modelId: model,
        messages: [
            .system("You must use the get_weather tool to answer. Do not respond with text."),
            .user("What is the weather in Boston? Use celsius.")
        ],
        maxTokens: 200,
        tools: [tool],
        toolChoice: .auto
    )

    let response = try await client.execute(request: request)
    guard let toolCall = response.toolCalls.first else {
        print("⚠️  No tool call returned. Model may not support tools.")
        return
    }

    print("✅ Tool call: \(toolCall.arguments)")

    let toolResult = "Weather in Boston: 21°C, clear skies"
    let followupRequest = ProviderRequest(
        modelId: model,
        messages: [
            .system("You are a helpful assistant."),
            .user("Call get_weather with city=Boston and unit=celsius."),
            .assistant(
                "",
                toolCalls: [AIMessage.ToolCall(id: toolCall.id, name: toolCall.name, arguments: toolCall.arguments)]
            ),
            .tool(toolResult, toolCallId: toolCall.id)
        ],
        maxTokens: 120,
        tools: [tool]
    )

    let followup = try await client.execute(request: followupRequest)
    print("✅ Final response: \(followup.content)")
}

private func runInteractive(client: OpenRouterClient, model: String) async throws {
    print("\n💬 Interactive Mode (\(model))")
    print("Type 'quit' to exit.")

    var messages: [AIMessage] = [
        .system("You are a helpful assistant. Keep responses concise.")
    ]

    while true {
        print("\n👤 You: ", terminator: "")
        guard let input = readLine(), !input.isEmpty else { continue }
        if input.lowercased() == "quit" { break }

        messages.append(.user(input))
        let request = ProviderRequest(
            modelId: model,
            messages: messages,
            maxTokens: 300,
            stream: true
        )

        var reply = ""
        print("🤖 Assistant: ", terminator: "")
        for try await event in client.stream(request: request) {
            switch event {
            case .textDelta(let text):
                reply += text
                print(text, terminator: "")
                fflush(stdout)
            case .finish:
                print("")
            default:
                break
            }
        }

        messages.append(.assistant(reply))
    }
}

// MARK: - Environment Loading

private func loadEnvironmentVariables() {
    let envPath = ".env"
    if let envContent = try? String(contentsOfFile: envPath) {
        for line in envContent.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                let parts = trimmedLine.components(separatedBy: "=")
                if parts.count >= 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
                    setenv(key, value, 0)
                }
            }
        }
        print("📄 Loaded environment variables from .env file")
    }
}

// MARK: - String Extension

private extension String {
    static func *(lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}
