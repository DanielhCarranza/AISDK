import SwiftUI
import AISDK

public struct MessageRow: View {
    let message: AIMessage
    var onStateChange: ((UIStateChangeEvent) -> Void)?

    public init(message: AIMessage, onStateChange: ((UIStateChangeEvent) -> Void)? = nil) {
        self.message = message
        self.onStateChange = onStateChange
    }

    private var parsedTree: UITree? {
        parseTree(from: message.content.textValue)
    }

    public var body: some View {
        let tree = parsedTree
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            // Hide the raw text bubble when we have a rendered UI card
            if tree == nil {
                HStack {
                    if message.role == .assistant || message.role == .tool {
                        bubble
                        Spacer(minLength: 24)
                    } else {
                        Spacer(minLength: 24)
                        bubble
                    }
                }
            }
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                ForEach(toolCalls, id: \.id) { call in
                    HStack {
                        if message.role == .user { Spacer() }
                        Text("Tool: \(call.name)")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        if message.role != .user { Spacer() }
                    }
                }
            }
            if let tree {
                HStack {
                    if message.role == .user { Spacer() }
                    GenerativeUIView(tree: tree, registry: .extended, onAction: { action in
                        // Forward actions as state change events if handler is present
                        if let handler = onStateChange {
                            // Parse "key:value" format from interactive components
                            let componentName: String
                            let statePath: String
                            if let colonIdx = action.firstIndex(of: ":") {
                                componentName = String(action[action.startIndex..<colonIdx])
                                statePath = "/state/\(componentName)"
                            } else {
                                componentName = action
                                statePath = "/state/lastAction"
                            }
                            let event = UIStateChangeEvent(
                                componentName: componentName,
                                path: statePath,
                                value: SpecValue(action)
                            )
                            handler(event)
                        }
                    })
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    if message.role != .user { Spacer() }
                }
            }
        }
    }

    private var bubble: some View {
        Text(message.content.textValue.isEmpty ? "(empty)" : message.content.textValue)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            .blue
        case .assistant:
            Color(white: 0.9)
        case .tool:
            .orange.opacity(0.2)
        case .system:
            .purple.opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }

    private func parseTree(from text: String) -> UITree? {
        guard text.contains("\"root\""), text.contains("\"elements\"") else { return nil }
        // Try raw text first
        if let tree = try? UITree.parse(from: Data(text.utf8), validatingWith: UICatalog.extended) {
            return tree
        }
        // Strip markdown fences (```json ... ``` or ``` ... ```)
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let tree = try? UITree.parse(from: Data(stripped.utf8), validatingWith: UICatalog.extended) {
            return tree
        }
        // Try extracting JSON between first { and last }
        guard let start = stripped.firstIndex(of: "{"),
              let end = stripped.lastIndex(of: "}") else { return nil }
        let jsonSlice = String(stripped[start...end])
        return try? UITree.parse(from: Data(jsonSlice.utf8), validatingWith: UICatalog.extended)
    }
}
