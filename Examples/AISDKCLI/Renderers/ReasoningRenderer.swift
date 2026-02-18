//
//  ReasoningRenderer.swift
//  AISDKCLI
//
//  Renderer for displaying AI reasoning/thinking content
//

import Foundation

/// Display mode for reasoning content
enum ReasoningDisplayMode {
    /// Show thinking inline as it streams
    case inline

    /// Show collapsed status "[Thinking... N tokens]"
    case collapsed

    /// Show in a separate box after completion
    case boxed

    /// Hide thinking entirely, just show final answer
    case hidden
}

/// Renderer for AI reasoning/thinking content (o1, claude thinking, etc.)
class ReasoningRenderer {
    /// Current display mode
    var mode: ReasoningDisplayMode = .inline

    /// Buffer for thinking content
    private var thinkingBuffer: String = ""

    /// Estimated token count
    private var tokenCount: Int = 0

    /// Whether we're currently receiving thinking content
    private var isThinking = false

    /// Lock for thread safety
    private let lock = NSLock()

    /// Spinner for collapsed mode
    private var spinner: Spinner?

    init(mode: ReasoningDisplayMode = .inline) {
        self.mode = mode
    }

    // MARK: - Public Methods

    /// Called when thinking phase starts
    func startThinking() {
        lock.lock()
        defer { lock.unlock() }

        isThinking = true
        thinkingBuffer = ""
        tokenCount = 0

        switch mode {
        case .inline:
            print(ANSIStyles.dim("┌─ Thinking ") + ANSIStyles.dim(String(repeating: "─", count: 50)))

        case .collapsed:
            spinner = Spinner(message: "Thinking...", frames: ANSIStyles.spinnerFrames3)
            spinner?.start()

        case .boxed:
            print(ANSIStyles.dim("[Thinking...]"))

        case .hidden:
            break
        }
    }

    /// Append thinking content
    func appendThinking(_ text: String) {
        lock.lock()
        defer { lock.unlock() }

        thinkingBuffer += text

        // Rough token estimate (4 chars = 1 token average)
        tokenCount = thinkingBuffer.count / 4

        switch mode {
        case .inline:
            // Print inline with dim styling
            print(ANSIStyles.dim(text), terminator: "")
            fflush(stdout)

        case .collapsed:
            // Update spinner with token count
            spinner?.update(message: "Thinking... (\(tokenCount) tokens)")

        case .boxed, .hidden:
            // Accumulate silently
            break
        }
    }

    /// Called when thinking phase ends
    func finishThinking() {
        lock.lock()
        defer { lock.unlock() }

        isThinking = false

        switch mode {
        case .inline:
            print("")
            print(ANSIStyles.dim("└" + String(repeating: "─", count: 60) + " (\(tokenCount) tokens)"))
            print("")

        case .collapsed:
            spinner?.stop(message: ANSIStyles.dim("[Thinking completed: \(tokenCount) tokens]"))
            spinner = nil

        case .boxed:
            ANSIStyles.clearCurrentLine()
            printThinkingBox()

        case .hidden:
            // Show minimal indicator
            if tokenCount > 0 {
                print(ANSIStyles.dim("[Thought for \(tokenCount) tokens]"))
            }
        }
    }

    /// Get the accumulated thinking content
    func getThinkingContent() -> String {
        lock.lock()
        defer { lock.unlock() }
        return thinkingBuffer
    }

    /// Reset for a new response
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        isThinking = false
        thinkingBuffer = ""
        tokenCount = 0
        spinner?.stop()
        spinner = nil
    }

    // MARK: - Private Methods

    /// Print thinking content in a box
    private func printThinkingBox() {
        let maxWidth = min(70, TerminalSize.current().width - 4)
        let lines = wrapText(thinkingBuffer, maxWidth: maxWidth - 4)

        print(ANSIStyles.dim("┌─ Thinking ") + ANSIStyles.dim(String(repeating: "─", count: maxWidth - 12)) + ANSIStyles.dim("┐"))

        for line in lines.prefix(15) {  // Limit to 15 lines
            let paddedLine = line.padding(toLength: maxWidth - 4, withPad: " ", startingAt: 0)
            print(ANSIStyles.dim("│ \(paddedLine) │"))
        }

        if lines.count > 15 {
            print(ANSIStyles.dim("│ ... (\(lines.count - 15) more lines)".padding(toLength: maxWidth - 2, withPad: " ", startingAt: 0) + "│"))
        }

        print(ANSIStyles.dim("└" + String(repeating: "─", count: maxWidth - 17) + " (\(tokenCount) tokens) ─┘"))
        print("")
    }

    /// Wrap text to specified width
    private func wrapText(_ text: String, maxWidth: Int) -> [String] {
        var lines: [String] = []
        let paragraphs = text.components(separatedBy: "\n")

        for paragraph in paragraphs {
            if paragraph.isEmpty {
                lines.append("")
                continue
            }

            var currentLine = ""
            let words = paragraph.components(separatedBy: " ")

            for word in words {
                if currentLine.isEmpty {
                    currentLine = word
                } else if currentLine.count + 1 + word.count <= maxWidth {
                    currentLine += " " + word
                } else {
                    lines.append(currentLine)
                    currentLine = word
                }
            }

            if !currentLine.isEmpty {
                lines.append(currentLine)
            }
        }

        return lines
    }
}

// MARK: - Thinking Content Parser

/// Parser for extracting thinking content from model responses
class ThinkingContentParser {
    /// Parse thinking content from response that uses <think> tags
    static func parseThinkingTags(_ content: String) -> (thinking: String?, answer: String) {
        // Look for <think>...</think> or <thinking>...</thinking>
        let patterns = [
            "<think>(.*?)</think>",
            "<thinking>(.*?)</thinking>",
            "\\[THINKING\\](.*?)\\[/THINKING\\]"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) {
                if let thinkingRange = Range(match.range(at: 1), in: content) {
                    let thinking = String(content[thinkingRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let answer = regex.stringByReplacingMatches(
                        in: content, range: NSRange(content.startIndex..., in: content),
                        withTemplate: ""
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (thinking, answer)
                }
            }
        }

        return (nil, content)
    }

    /// Check if content appears to contain thinking markers
    static func hasThinkingMarkers(_ content: String) -> Bool {
        return content.contains("<think>") ||
               content.contains("<thinking>") ||
               content.contains("[THINKING]")
    }
}
