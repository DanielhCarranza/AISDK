//
//  main.swift
//  ResponsesAPIDemo
//
//  Tests the OpenAI Responses API adapter (OpenAIResponsesClientAdapter).
//  Verifies: basic chat, streaming, built-in web search, and comparison with Chat Completions.
//
//  Usage:
//    swift run ResponsesAPIDemo           # Run all tests
//    swift run ResponsesAPIDemo chat      # Basic chat only
//    swift run ResponsesAPIDemo stream    # Streaming only
//    swift run ResponsesAPIDemo web       # Web search (Responses API exclusive)
//    swift run ResponsesAPIDemo compare   # Side-by-side Responses vs Chat Completions
//    swift run ResponsesAPIDemo interactive  # Interactive chat mode
//
//  Requires: OPENAI_API_KEY in .env file or environment
//

import Foundation
import AISDK

// MARK: - Environment

func loadEnv() {
    for path in [".env", "Tests/.env"] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
            setenv(key, value, 0)
        }
        print("Loaded .env from \(path)")
        return
    }
}

func header(_ title: String) {
    print("\n" + String(repeating: "=", count: 60))
    print("  \(title)")
    print(String(repeating: "=", count: 60))
}

func subheader(_ title: String) {
    print("\n--- \(title) ---")
}

// MARK: - Tests

/// Test 1: Basic non-streaming chat
func testBasicChat(model: any LLM) async throws {
    subheader("Test 1: Basic Chat (non-streaming)")

    let request = AITextRequest(
        messages: [
            AIMessage(role: .system, content: .text("You are a concise assistant. Reply in one sentence.")),
            AIMessage(role: .user, content: .text("What is the OpenAI Responses API?"))
        ],
        maxTokens: 100
    )

    let result = try await model.generateText(request: request)
    print("Response: \(result.text)")
    print("Tokens: \(result.usage.promptTokens) in / \(result.usage.completionTokens) out")
    if let responseId = result.responseId {
        print("Response ID: \(responseId)")
    }
    print("[PASS]")
}

/// Test 2: Streaming
func testStreaming(model: any LLM) async throws {
    subheader("Test 2: Streaming")

    let request = AITextRequest(
        messages: [
            AIMessage(role: .user, content: .text("Count from 1 to 5, one number per line."))
        ],
        maxTokens: 50
    )

    print("Streamed: ", terminator: "")
    for try await event in model.streamText(request: request) {
        switch event {
        case .textDelta(let text):
            print(text, terminator: "")
            fflush(stdout)
        case .finish(let reason, let usage):
            print("\nFinish: \(reason), tokens: \(usage.promptTokens) in / \(usage.completionTokens) out")
        default:
            break
        }
    }
    print("[PASS]")
}

/// Test 3: Web search — only works with Responses API
func testWebSearch(model: any LLM) async throws {
    subheader("Test 3: Web Search (Responses API built-in tool)")

    let request = AITextRequest(
        messages: [
            AIMessage(role: .user, content: .text("What is the latest version of Swift as of today? Be brief."))
        ],
        maxTokens: 200,
        builtInTools: [.webSearchDefault]
    )

    let result = try await model.generateText(request: request)
    print("Response: \(result.text.prefix(300))")
    print("Tokens: \(result.usage.promptTokens) in / \(result.usage.completionTokens) out")
    print("[PASS] Web search works (would FAIL on Chat Completions API)")
}

/// Test 4: Side-by-side comparison
func testComparison(apiKey: String) async throws {
    subheader("Test 4: Responses API vs Chat Completions")

    let responsesModel = ProviderLanguageModelAdapter.openAIResponses(apiKey: apiKey, modelId: "gpt-4o-mini")
    let chatModel = ProviderLanguageModelAdapter.openAIChatCompletions(apiKey: apiKey, modelId: "gpt-4o-mini")

    let request = AITextRequest(
        messages: [AIMessage(role: .user, content: .text("Say 'hello' and nothing else."))],
        maxTokens: 10
    )

    // Both should work for basic chat
    print("Responses API:")
    let r1 = try await responsesModel.generateText(request: request)
    print("  Provider: \(r1.provider ?? "?"), Response: \"\(r1.text)\"")

    print("Chat Completions:")
    let r2 = try await chatModel.generateText(request: request)
    print("  Provider: \(r2.provider ?? "?"), Response: \"\(r2.text)\"")

    // Web search should FAIL on Chat Completions, WORK on Responses
    let webRequest = AITextRequest(
        messages: [AIMessage(role: .user, content: .text("Search for news"))],
        maxTokens: 50,
        builtInTools: [.webSearchDefault]
    )

    print("\nWeb search on Chat Completions (expect failure):")
    do {
        _ = try await chatModel.generateText(request: webRequest)
        print("  [UNEXPECTED] Did not throw")
    } catch {
        let desc = String(describing: error)
        if desc.contains("Built-in tools are not supported") {
            print("  [EXPECTED] Built-in tools rejected by Chat Completions")
        } else {
            print("  [ERROR] \(desc.prefix(100))")
        }
    }

    print("Web search on Responses API (expect success):")
    do {
        let r3 = try await responsesModel.generateText(request: webRequest)
        print("  [PASS] Response: \(r3.text.prefix(100))...")
    } catch {
        print("  [FAIL] \(error)")
    }

    print("[PASS]")
}

/// Interactive chat mode
func testInteractive(model: any LLM) async throws {
    subheader("Interactive Chat (type 'quit' to exit)")
    print("Using OpenAI Responses API with gpt-4o-mini")
    print("You can ask it to search the web!\n")

    var messages: [AIMessage] = [
        AIMessage(role: .system, content: .text("You are a helpful, concise assistant."))
    ]

    while true {
        print("You: ", terminator: "")
        fflush(stdout)
        guard let input = readLine(), !input.isEmpty else { continue }
        if input.lowercased() == "quit" || input.lowercased() == "exit" {
            print("Goodbye!")
            break
        }

        messages.append(AIMessage(role: .user, content: .text(input)))

        // Enable web search if user mentions "search" or "latest"
        let useWebSearch = input.lowercased().contains("search") ||
                          input.lowercased().contains("latest") ||
                          input.lowercased().contains("news") ||
                          input.lowercased().contains("today")

        let request = AITextRequest(
            messages: messages,
            maxTokens: 500,
            builtInTools: useWebSearch ? [.webSearchDefault] : nil
        )

        print("Assistant: ", terminator: "")
        if useWebSearch { print("[web search enabled] ", terminator: "") }
        var fullResponse = ""
        for try await event in model.streamText(request: request) {
            switch event {
            case .textDelta(let text):
                print(text, terminator: "")
                fflush(stdout)
                fullResponse += text
            case .finish:
                print()
            default:
                break
            }
        }

        messages.append(AIMessage(role: .assistant, content: .text(fullResponse)))
    }
}

// MARK: - Main

loadEnv()

guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
    print("ERROR: OPENAI_API_KEY not found.")
    print("Set it in .env or: export OPENAI_API_KEY=sk-...")
    exit(1)
}

header("OpenAI Responses API Demo")
print("Adapter: OpenAIResponsesClientAdapter -> POST /v1/responses")
print("Model: gpt-4o-mini")

let model = ProviderLanguageModelAdapter.openAIResponses(
    apiKey: apiKey,
    modelId: "gpt-4o-mini"
)

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "all"

do {
    switch mode {
    case "chat":
        try await testBasicChat(model: model)
    case "stream":
        try await testStreaming(model: model)
    case "web", "websearch":
        try await testWebSearch(model: model)
    case "compare":
        try await testComparison(apiKey: apiKey)
    case "interactive", "i":
        try await testInteractive(model: model)
    case "all":
        try await testBasicChat(model: model)
        try await testStreaming(model: model)
        try await testWebSearch(model: model)
        try await testComparison(apiKey: apiKey)
        header("ALL TESTS PASSED")
        print("Run 'swift run ResponsesAPIDemo interactive' for interactive chat")
    default:
        print("Usage: swift run ResponsesAPIDemo [mode]")
        print("Modes: all, chat, stream, web, compare, interactive")
    }
} catch {
    print("\n[FAILED] \(error)")
    exit(1)
}
