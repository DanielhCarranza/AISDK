//
//  ModelSelector.swift
//  AISDKCLI
//
//  Interactive model selection with arrow key navigation
//

import Foundation
import AISDK

/// Model information for display
struct ModelInfo {
    let id: String
    let name: String
    let provider: String
    let contextWindow: Int?
    let pricing: String?
    let capabilities: [String]

    /// Short display name (without provider prefix)
    var displayName: String {
        if id.contains("/") {
            return String(id.split(separator: "/").last ?? Substring(id))
        }
        return name
    }

    /// Provider from model ID (e.g., "anthropic" from "anthropic/claude-3-5-sonnet")
    var providerFromId: String {
        if id.contains("/") {
            return String(id.split(separator: "/").first ?? "other")
        }
        return provider.lowercased()
    }
}

/// Interactive model selector with arrow key navigation
class ModelSelector {
    private let client: any ProviderClient
    private let rawMode = RawTerminalMode()

    private enum ListItem {
        case header(String)
        case model(ModelInfo)
    }

    // Popular models to show first (known good ones)
    private static let popularModels: [ModelInfo] = [
        ModelInfo(id: "anthropic/claude-3-5-sonnet", name: "Claude 3.5 Sonnet", provider: "Anthropic",
                  contextWindow: 200000, pricing: "$$", capabilities: ["reasoning", "coding", "tools"]),
        ModelInfo(id: "anthropic/claude-3-opus", name: "Claude 3 Opus", provider: "Anthropic",
                  contextWindow: 200000, pricing: "$$$", capabilities: ["reasoning", "coding", "tools"]),
        ModelInfo(id: "openai/gpt-4o", name: "GPT-4o", provider: "OpenAI",
                  contextWindow: 128000, pricing: "$$", capabilities: ["vision", "tools", "coding"]),
        ModelInfo(id: "openai/o1-preview", name: "O1 Preview", provider: "OpenAI",
                  contextWindow: 128000, pricing: "$$$", capabilities: ["reasoning"]),
        ModelInfo(id: "google/gemini-2.0-flash-exp:free", name: "Gemini 2.0 Flash", provider: "Google",
                  contextWindow: 1000000, pricing: "free", capabilities: ["vision", "tools", "fast"]),
        ModelInfo(id: "meta-llama/llama-3.3-70b-instruct", name: "Llama 3.3 70B", provider: "Meta",
                  contextWindow: 131072, pricing: "$", capabilities: ["coding", "tools"]),
        ModelInfo(id: "deepseek/deepseek-chat", name: "DeepSeek Chat", provider: "DeepSeek",
                  contextWindow: 64000, pricing: "$", capabilities: ["reasoning", "coding"]),
        ModelInfo(id: "arcee-ai/trinity-mini:free", name: "Trinity Mini", provider: "Arcee AI",
                  contextWindow: 8192, pricing: "free", capabilities: ["tools"]),
        ModelInfo(id: "nvidia/nemotron-3-nano-30b-a3b:free", name: "Nemotron 3 Nano", provider: "NVIDIA",
                  contextWindow: 8192, pricing: "free", capabilities: ["streaming"])
    ]

    init(client: any ProviderClient) {
        self.client = client
    }

    /// Select a model interactively
    /// Returns the selected model ID or nil if cancelled
    func selectModel() async -> String? {
        // Fetch available models from the provider
        let models = await fetchModels()

        if models.isEmpty {
            print(ANSIStyles.error("No models available from provider"))
            return nil
        }

        // Group models by provider
        let grouped = groupModelsByProvider(models)

        return interactiveSelect(groupedModels: grouped)
    }

    /// Fetch models from the provider
    private func fetchModels() async -> [ModelInfo] {
        let spinner = Spinner(message: "Fetching available models...")
        spinner.start()

        do {
            let modelIds = try await client.availableModels
            spinner.stop(message: ANSIStyles.success("Found \(modelIds.count) models"))

            // Convert to ModelInfo, using known info for popular models
            return modelIds.prefix(100).map { id in
                if let known = Self.popularModels.first(where: { $0.id == id }) {
                    return known
                }
                return ModelInfo(
                    id: id,
                    name: extractModelName(from: id),
                    provider: extractProvider(from: id),
                    contextWindow: nil,
                    pricing: nil,
                    capabilities: []
                )
            }
        } catch {
            spinner.stop(message: ANSIStyles.warning("Could not fetch models: \(error.localizedDescription)"))
            // Return popular models as fallback
            return Self.popularModels
        }
    }

    /// Extract model name from ID
    private func extractModelName(from id: String) -> String {
        if id.contains("/") {
            return String(id.split(separator: "/").last ?? Substring(id))
        }
        return id
    }

    /// Extract provider from model ID
    private func extractProvider(from id: String) -> String {
        if id.contains("/") {
            let provider = String(id.split(separator: "/").first ?? "other")
            return provider.capitalized
        }
        return "Other"
    }

    /// Group models by provider
    private func groupModelsByProvider(_ models: [ModelInfo]) -> [(provider: String, models: [ModelInfo])] {
        var groups: [String: [ModelInfo]] = [:]

        for model in models {
            let provider = model.providerFromId.capitalized
            groups[provider, default: []].append(model)
        }

        // Sort providers: Popular ones first, then alphabetically
        let popularProviders = ["Anthropic", "Openai", "Google", "Meta", "Deepseek"]
        let sortedGroups = groups.sorted { a, b in
            let aIndex = popularProviders.firstIndex(of: a.key) ?? 999
            let bIndex = popularProviders.firstIndex(of: b.key) ?? 999
            if aIndex != bIndex {
                return aIndex < bIndex
            }
            return a.key < b.key
        }

        return sortedGroups.map { (provider: $0.key, models: $0.value) }
    }

    /// Interactive selection with arrow keys
    private func interactiveSelect(groupedModels: [(provider: String, models: [ModelInfo])]) -> String? {
        // Flatten into a list with group headers
        var items: [ListItem] = []
        for group in groupedModels {
            items.append(.header(group.provider))
            for model in group.models {
                items.append(.model(model))
            }
        }

        // Find selectable indices (only models, not headers)
        let selectableIndices = items.enumerated().compactMap { index, item -> Int? in
            if case .model = item { return index }
            return nil
        }

        guard !selectableIndices.isEmpty else {
            print(ANSIStyles.error("No models to select"))
            return nil
        }

        var selectedIndex = 0  // Index into selectableIndices
        var scrollOffset = 0
        let termSize = TerminalSize.current()
        let maxVisibleItems = max(5, termSize.height - 12)  // Leave room for header/footer

        rawMode.enable()
        defer {
            rawMode.disable()
            print(ANSIStyles.showCursor)
        }

        print(ANSIStyles.hideCursor)

        while true {
            renderList(items: items, selectableIndices: selectableIndices,
                       selectedIndex: selectedIndex, scrollOffset: scrollOffset,
                       maxVisible: maxVisibleItems)

            guard let key = KeyCode.read() else { continue }

            switch key {
            case .up:
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    // Adjust scroll if needed
                    let actualIndex = selectableIndices[selectedIndex]
                    if actualIndex < scrollOffset {
                        scrollOffset = max(0, actualIndex - 2)
                    }
                }

            case .down:
                if selectedIndex < selectableIndices.count - 1 {
                    selectedIndex += 1
                    // Adjust scroll if needed
                    let actualIndex = selectableIndices[selectedIndex]
                    if actualIndex >= scrollOffset + maxVisibleItems {
                        scrollOffset = actualIndex - maxVisibleItems + 3
                    }
                }

            case .enter:
                let actualIndex = selectableIndices[selectedIndex]
                if case .model(let model) = items[actualIndex] {
                    clearSelection(itemCount: min(items.count, maxVisibleItems) + 10)
                    print(ANSIStyles.green("✓ ") + ANSIStyles.bold(ANSIStyles.green(model.id)))
                    return model.id
                }

            case .char("q"), .escape, .ctrlC:
                clearSelection(itemCount: min(items.count, maxVisibleItems) + 10)
                print(ANSIStyles.warning("Model selection cancelled"))
                return nil

            case .pageUp:
                selectedIndex = max(0, selectedIndex - 5)
                let actualIndex = selectableIndices[selectedIndex]
                scrollOffset = max(0, actualIndex - 2)

            case .pageDown:
                selectedIndex = min(selectableIndices.count - 1, selectedIndex + 5)
                let actualIndex = selectableIndices[selectedIndex]
                if actualIndex >= scrollOffset + maxVisibleItems {
                    scrollOffset = actualIndex - maxVisibleItems + 3
                }

            case .home:
                selectedIndex = 0
                scrollOffset = 0

            case .end:
                selectedIndex = selectableIndices.count - 1
                let actualIndex = selectableIndices[selectedIndex]
                scrollOffset = max(0, actualIndex - maxVisibleItems + 3)

            default:
                break
            }
        }
    }

    /// Render the model list
    private func renderList(items: [ListItem], selectableIndices: [Int],
                            selectedIndex: Int, scrollOffset: Int, maxVisible: Int) {
        // Move cursor to start
        print("\r", terminator: "")

        // Get the currently selected model for the header
        let selectedActualIndex = selectableIndices[selectedIndex]
        var selectedModel: ModelInfo?
        if selectedActualIndex < items.count,
           case .model(let model) = items[selectedActualIndex] {
            selectedModel = model
        }

        let headerLines: [String]
        if let model = selectedModel {
            let maxLineLength = 64
            let displayName = model.displayName.count > maxLineLength
                ? String(model.displayName.prefix(maxLineLength - 3)) + "..."
                : model.displayName
            let idLine = model.id.count > maxLineLength
                ? String(model.id.prefix(maxLineLength - 3)) + "..."
                : model.id

            var detailParts: [String] = [model.providerFromId.capitalized]
            if let ctx = model.contextWindow {
                let ctxStr = ctx >= 1_000_000 ? "\(ctx / 1_000_000)M ctx" : "\(ctx / 1000)K ctx"
                detailParts.append(ctxStr)
            }
            if let price = model.pricing {
                detailParts.append("price \(price)")
            }
            if !model.capabilities.isEmpty {
                detailParts.append(model.capabilities.prefix(3).joined(separator: ", "))
            }

            headerLines = [
                "Selected: " + ANSIStyles.cyan(displayName),
                ANSIStyles.dim(idLine),
                ANSIStyles.dim(detailParts.joined(separator: " • "))
            ]
        } else {
            headerLines = ["Select a model..."]
        }

        let headerText = headerLines.joined(separator: "\n")
        let headerLineCount = headerLines.count + 2
        print(ANSIStyles.doubleBox(headerText, width: 72))
        print("")

        let endOffset = min(items.count, scrollOffset + maxVisible)

        for i in scrollOffset..<endOffset {
            // Re-cast items since we need proper typing
            let item = items[i]

            switch item {
            case .header(let provider):
                print("  \(ANSIStyles.bold(ANSIStyles.cyan(provider)))")

            case .model(let model):
                let isSelected = i == selectedActualIndex
                let prefix = isSelected ? ANSIStyles.green("  ▸ ") : "    "
                let name = model.displayName

                var extras: [String] = []
                if let ctx = model.contextWindow {
                    let ctxStr = ctx >= 1000000 ? "\(ctx/1000000)M" : "\(ctx/1000)K"
                    extras.append(ANSIStyles.dim("(\(ctxStr) ctx)"))
                }
                if let price = model.pricing {
                    extras.append(ANSIStyles.yellow(price))
                }
                if !model.capabilities.isEmpty {
                    extras.append(ANSIStyles.dim(model.capabilities.prefix(3).joined(separator: ", ")))
                }

                let extrasStr = extras.isEmpty ? "" : " " + extras.joined(separator: " ")

                if isSelected {
                    print("\(prefix)\(ANSIStyles.bold(ANSIStyles.green(name)))\(extrasStr)")
                } else {
                    print("\(prefix)\(name)\(extrasStr)")
                }
            }
        }

        // Show scroll indicators
        if scrollOffset > 0 {
            print(ANSIStyles.dim("  ↑ more above"))
        }
        if endOffset < items.count {
            print(ANSIStyles.dim("  ↓ more below"))
        }

        print("")
        print(ANSIStyles.dim("↑/↓ navigate • Enter to select • q to quit • Page Up/Down fast scroll"))

        // Move cursor back up for next render
        let scrollIndicatorCount = (scrollOffset > 0 ? 1 : 0) + (endOffset < items.count ? 1 : 0)
        let footerLines = 2 + scrollIndicatorCount
        let linesToClear = headerLineCount + 1 + (endOffset - scrollOffset) + footerLines
        print("\u{001B}[\(linesToClear)A", terminator: "")
        fflush(stdout)
    }

    /// Clear the selection UI
    private func clearSelection(itemCount: Int) {
        for _ in 0..<itemCount {
            print(ANSIStyles.clearLine)
        }
        // Move back up
        print("\u{001B}[\(itemCount)A", terminator: "")
        fflush(stdout)
    }
}

// MARK: - Simplified Model Selector (non-interactive fallback)

/// Simple numbered list model selector for non-TTY environments
func selectModelSimple(client: any ProviderClient) async -> String? {
    print("\n\(ANSIStyles.bold("Available Models:"))\n")

    let models: [String]
    do {
        models = Array(try await client.availableModels.prefix(20))
    } catch {
        print(ANSIStyles.warning("Could not fetch models, using defaults"))
        models = [
            "anthropic/claude-3-5-sonnet",
            "openai/gpt-4o",
            "google/gemini-2.0-flash-exp:free",
            "meta-llama/llama-3.3-70b-instruct",
            "arcee-ai/trinity-mini:free"
        ]
    }

    for (index, model) in models.enumerated() {
        print("  \(ANSIStyles.cyan("[\(index + 1)]")) \(model)")
    }

    print("\nEnter number (1-\(models.count)) or model ID: ", terminator: "")
    fflush(stdout)

    guard let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
        return nil
    }

    // Check if it's a number
    if let num = Int(input), num >= 1, num <= models.count {
        return models[num - 1]
    }

    // Otherwise treat as model ID
    return input
}
