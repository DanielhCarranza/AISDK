import SwiftUI
import AISDK

public struct MessageRow: View {
    let message: AIMessage

    public init(message: AIMessage) {
        self.message = message
    }

    public var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            HStack {
                if message.role == .assistant || message.role == .tool {
                    bubble
                    Spacer(minLength: 24)
                } else {
                    Spacer(minLength: 24)
                    bubble
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
            if let tree = parseTree(from: message.content.textValue) {
                HStack {
                    if message.role == .user { Spacer() }
                    GenerativeUIView(tree: tree, registry: .extended, onAction: { _ in })
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
        return try? UITree.parse(from: Data(text.utf8), validatingWith: UICatalog.extended)
    }
}
