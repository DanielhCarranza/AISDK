//
//  ToolCallRenderer.swift
//  AISDKCLI
//
//  Renderer for displaying tool calls and their results
//

import Foundation

/// Status of a tool call
enum ToolCallStatus {
    case started
    case executing
    case completed(result: String)
    case failed(error: String)
}

/// Information about a tool call
struct ToolCallInfo {
    let id: String
    let name: String
    var arguments: String
    var status: ToolCallStatus
    var startTime: Date
    var endTime: Date?
}

/// Renderer for tool calls and their execution
class ToolCallRenderer {
    /// Active tool calls by ID
    private var activeCalls: [String: ToolCallInfo] = [:]

    /// Completed tool calls (for summary)
    private var completedCalls: [ToolCallInfo] = []

    /// Whether to show verbose output
    var verbose: Bool = false

    /// Spinner for executing tools
    private var spinners: [String: Spinner] = [:]

    // MARK: - Tool Call Lifecycle

    /// Called when a tool call starts
    func startToolCall(id: String, name: String) {
        // Prevent duplicate start calls for the same tool
        if activeCalls[id] != nil {
            return
        }

        let info = ToolCallInfo(
            id: id,
            name: name,
            arguments: "",
            status: .started,
            startTime: Date()
        )
        activeCalls[id] = info

        print("")
        print(ANSIStyles.cyan("⚙️  Tool Call: ") + ANSIStyles.bold(name))
        print(ANSIStyles.dim("   ID: \(id.prefix(12))..."))
    }

    /// Append arguments delta to a tool call
    func appendArguments(id: String, delta: String) {
        guard var info = activeCalls[id] else { return }
        info.arguments += delta
        activeCalls[id] = info
    }

    /// Called when tool call arguments are complete, before execution
    func toolCallReady(id: String, name: String, arguments: String) {
        guard var info = activeCalls[id] else {
            // Create new info if startToolCall wasn't called
            let newInfo = ToolCallInfo(
                id: id,
                name: name,
                arguments: arguments,
                status: .executing,
                startTime: Date()
            )
            activeCalls[id] = newInfo
            print("")
            print(ANSIStyles.cyan("⚙️  Tool Call: ") + ANSIStyles.bold(name))
            print(ANSIStyles.dim("   ID: \(id.prefix(12))..."))
            printArguments(arguments)
            return
        }

        // Prevent duplicate ready calls - if already executing, skip
        if case .executing = info.status {
            return
        }

        info.arguments = arguments
        info.status = .executing
        activeCalls[id] = info

        printArguments(arguments)
    }

    /// Show that tool is executing
    func showExecuting(id: String) {
        guard var info = activeCalls[id] else { return }
        info.status = .executing
        activeCalls[id] = info

        let spinner = Spinner(message: "Executing \(info.name)...")
        spinners[id] = spinner
        spinner.start()
    }

    /// Called when tool execution completes with result
    func showResult(id: String, result: String) {
        // Stop spinner if running
        spinners[id]?.stop()
        spinners.removeValue(forKey: id)

        guard var info = activeCalls[id] else {
            // Just show the result without tracking
            print(ANSIStyles.green("   ✓ Result: ") + formatResult(result))
            return
        }

        info.status = .completed(result: result)
        info.endTime = Date()
        activeCalls.removeValue(forKey: id)
        completedCalls.append(info)

        let duration = info.endTime!.timeIntervalSince(info.startTime)

        print(ANSIStyles.green("   ✓ Result: ") + formatResult(result))

        if verbose {
            print(ANSIStyles.dim("   Duration: \(String(format: "%.2f", duration))s"))
        }
    }

    /// Called when tool execution fails
    func showError(id: String, error: String) {
        // Stop spinner if running
        spinners[id]?.stop()
        spinners.removeValue(forKey: id)

        guard var info = activeCalls[id] else {
            print(ANSIStyles.red("   ✗ Error: ") + error)
            return
        }

        info.status = .failed(error: error)
        info.endTime = Date()
        activeCalls.removeValue(forKey: id)
        completedCalls.append(info)

        print(ANSIStyles.red("   ✗ Error: ") + error)
    }

    // MARK: - Display Helpers

    /// Format and print arguments
    private func printArguments(_ arguments: String) {
        print(ANSIStyles.dim("   Arguments:"))

        // Try to pretty-print JSON
        if let data = arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            for line in prettyString.components(separatedBy: "\n") {
                print("     " + ANSIStyles.yellow(line))
            }
        } else {
            // Fallback: show raw arguments
            let truncated = arguments.count > 200 ? String(arguments.prefix(200)) + "..." : arguments
            print("     " + ANSIStyles.yellow(truncated))
        }
    }

    /// Format result for display
    private func formatResult(_ result: String) -> String {
        // Truncate if too long
        let maxLength = verbose ? 500 : 150
        let truncated = result.count > maxLength
            ? String(result.prefix(maxLength)) + "..."
            : result

        // Try to format as JSON if it looks like JSON
        if result.hasPrefix("{") || result.hasPrefix("["),
           let data = truncated.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            if let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                // For multi-line JSON, return formatted
                if prettyString.contains("\n") {
                    return "\n     " + prettyString.components(separatedBy: "\n").joined(separator: "\n     ")
                }
            }
        }

        return truncated
    }

    // MARK: - Summary

    /// Get summary of all tool calls in this session
    func getSummary() -> String {
        guard !completedCalls.isEmpty else {
            return "No tool calls made"
        }

        var summary = "Tool Calls Summary:\n"
        for call in completedCalls {
            let status: String
            switch call.status {
            case .completed:
                status = ANSIStyles.green("✓")
            case .failed:
                status = ANSIStyles.red("✗")
            default:
                status = "?"
            }

            let duration = call.endTime.map { $0.timeIntervalSince(call.startTime) } ?? 0
            summary += "  \(status) \(call.name) (\(String(format: "%.2fs", duration)))\n"
        }
        return summary
    }

    /// Reset for a new conversation
    func reset() {
        for (_, spinner) in spinners {
            spinner.stop()
        }
        spinners.removeAll()
        activeCalls.removeAll()
        completedCalls.removeAll()
    }
}

// MARK: - Tool Call Box Renderer

/// Renders tool calls in a box format
class ToolCallBoxRenderer {
    /// Render a tool call in a box
    static func renderToolCall(name: String, arguments: String, result: String?) -> String {
        var lines: [String] = []

        lines.append("┌─ Tool: \(name) " + String(repeating: "─", count: max(0, 50 - name.count)))
        lines.append("│")

        // Arguments section
        lines.append("│ \(ANSIStyles.dim("Arguments:"))")
        if let data = arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            for line in prettyString.components(separatedBy: "\n") {
                lines.append("│   \(ANSIStyles.yellow(line))")
            }
        } else {
            lines.append("│   \(ANSIStyles.yellow(arguments))")
        }

        // Result section (if available)
        if let result = result {
            lines.append("│")
            lines.append("│ \(ANSIStyles.dim("Result:"))")
            let resultLines = result.components(separatedBy: "\n")
            for line in resultLines.prefix(10) {
                lines.append("│   \(ANSIStyles.green(line))")
            }
            if resultLines.count > 10 {
                lines.append("│   ... (\(resultLines.count - 10) more lines)")
            }
        }

        lines.append("│")
        lines.append("└" + String(repeating: "─", count: 60))

        return lines.joined(separator: "\n")
    }
}
