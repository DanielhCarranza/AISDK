import SwiftUI
import AISDK

/// Renders agent activity (thinking, tool calls) with collapse-after-completion.
///
/// During streaming: shows all activity parts inline (thinking text, tool call status).
/// After completion: auto-collapses to a summary row that can be expanded.
/// Matches the pattern used by Claude, ChatGPT, and Grok.
struct AgentActivityView: View {
    let accumulator: AIStreamAccumulator
    @State private var isExpanded = false

    var body: some View {
        if accumulator.hasActivity {
            if accumulator.isComplete && !isExpanded {
                collapsedSummary
            } else {
                expandedActivity
            }
        }
    }

    // MARK: - Collapsed Summary

    private var collapsedSummary: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(accumulator.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Activity

    private var expandedActivity: some View {
        VStack(alignment: .leading, spacing: 6) {
            if accumulator.isComplete {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(accumulator.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            ForEach(accumulator.parts) { part in
                switch part {
                case .thinking(_, let text, let duration):
                    ThinkingRow(text: text, duration: duration, isStreaming: !accumulator.isComplete)
                case .toolCall(_, let call):
                    ToolCallRow(call: call)
                case .text, .source, .file:
                    EmptyView()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Thinking Row

private struct ThinkingRow: View {
    let text: String
    let duration: TimeInterval?
    let isStreaming: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isStreaming && duration == nil {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "brain")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }

            if let duration {
                Text("Thought for \(String(format: "%.1f", duration))s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Thinking")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if !text.isEmpty && (isStreaming || duration == nil) {
            Text(text.suffix(200))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(3)
                .padding(.leading, 20)
        }
    }
}

// MARK: - Tool Call Row

private struct ToolCallRow: View {
    let call: AIToolCallPart

    var body: some View {
        HStack(spacing: 6) {
            statusIcon
                .frame(width: 14, height: 14)

            Text(call.toolName)
                .font(.caption)
                .fontWeight(.medium)

            statusLabel
                .font(.caption2)

            Spacer()
        }

        if case .outputAvailable = call.state, let output = call.output {
            Text(output.prefix(120))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .padding(.leading, 20)
        }

        if case .outputError = call.state, let error = call.errorText {
            Text(error)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
                .padding(.leading, 20)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch call.state {
        case .inputStreaming:
            ProgressView()
                .scaleEffect(0.6)
        case .inputAvailable:
            ProgressView()
                .scaleEffect(0.6)
        case .outputAvailable:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .outputError:
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch call.state {
        case .inputStreaming:
            Text("building args...")
                .foregroundStyle(.secondary)
        case .inputAvailable:
            Text("running...")
                .foregroundStyle(.secondary)
        case .outputAvailable:
            if let duration = call.durationSeconds {
                Text(String(format: "%.1fs", duration))
                    .foregroundStyle(.secondary)
            }
        case .outputError:
            Text("failed")
                .foregroundStyle(.red)
        }
    }
}
