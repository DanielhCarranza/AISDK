//
//  ReasoningDisplay.swift
//  AISDKTestRunner
//
//  Cursor-style reasoning display for showing LLM thinking process
//

import Foundation

/// Display mode for reasoning/thinking tokens
public enum ReasoningMode: String {
    /// Show thinking inline as it streams
    case inline
    /// Show collapsed "[Thinking... N tokens]"
    case collapsed
    /// Side-by-side display (thinking | answer)
    case split
}

/// Cursor-style reasoning display utility
public final class ReasoningDisplay: @unchecked Sendable {
    public let mode: ReasoningMode
    private var thinkingBuffer: String = ""
    private var tokenCount: Int = 0
    private let lock = NSLock()

    public init(mode: ReasoningMode = .inline) {
        self.mode = mode
    }

    // MARK: - Display Methods

    /// Display a thinking/reasoning chunk
    public func displayThinking(_ text: String) {
        lock.lock()
        defer { lock.unlock() }

        thinkingBuffer += text
        tokenCount += text.split(separator: " ").count

        switch mode {
        case .inline:
            printInline(text)
        case .collapsed:
            printCollapsed()
        case .split:
            printSplit(text)
        }
    }

    /// Stream a thinking chunk character by character
    public func streamThinking(_ text: String) async {
        for char in text {
            lock.lock()
            thinkingBuffer.append(char)
            if char == " " { tokenCount += 1 }
            lock.unlock()

            switch mode {
            case .inline:
                print(char, terminator: "")
                fflush(stdout)
            case .collapsed:
                printCollapsed()
            case .split:
                // For split mode, buffer and update periodically
                break
            }

            // Small delay for visual effect
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }

    /// Call when thinking is complete, before the final answer
    public func finishThinking() {
        lock.lock()
        let finalTokenCount = tokenCount
        let buffer = thinkingBuffer
        lock.unlock()

        switch mode {
        case .inline:
            print("\n") // End the inline thinking section
            printThinkingBox(buffer)
        case .collapsed:
            // Clear the line and show final collapsed state
            clearLine()
            print("[Thinking completed: \(finalTokenCount) tokens]")
        case .split:
            printThinkingBox(buffer)
        }

        resetBuffer()
    }

    /// Reset the thinking buffer for a new session
    public func resetBuffer() {
        lock.lock()
        thinkingBuffer = ""
        tokenCount = 0
        lock.unlock()
    }

    // MARK: - Private Display Methods

    private func printInline(_ text: String) {
        // Clear line and print thinking with prefix
        clearLine()
        let truncated = String(thinkingBuffer.suffix(60))
        print("Thinking: \(truncated)", terminator: "")
        fflush(stdout)
    }

    private func printCollapsed() {
        clearLine()
        print("[Thinking... \(tokenCount) tokens]", terminator: "")
        fflush(stdout)
    }

    private func printSplit(_ text: String) {
        // For split mode, we accumulate and show in a box
        // This is a simplified version - real implementation would use ncurses
        clearLine()
        let lines = thinkingBuffer.split(separator: "\n")
        let lastLine = lines.last.map(String.init) ?? ""
        let truncated = String(lastLine.suffix(40))
        print("| Thinking: \(truncated)", terminator: "")
        fflush(stdout)
    }

    private func clearLine() {
        // ANSI escape code to clear current line and return to start
        print("\r\u{1B}[K", terminator: "")
    }

    private func printThinkingBox(_ content: String) {
        let lines = content.components(separatedBy: "\n")
        let maxWidth = min(70, lines.map { $0.count }.max() ?? 40)
        let width = max(maxWidth, 40)

        print("\n[THINKING]")
        print("+" + String(repeating: "-", count: width + 2) + "+")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let padded = trimmed.padding(toLength: width, withPad: " ", startingAt: 0)
                print("| \(padded) |")
            }
        }

        print("+" + String(repeating: "-", count: width + 2) + "+")
        print("[END THINKING]\n")
    }

    // MARK: - Static Display Helpers

    /// Display reasoning for streaming responses with thinking support
    public static func displayStreamingReasoning(
        _ stream: AsyncThrowingStream<StreamEvent, Error>,
        mode: ReasoningMode = .inline
    ) async throws -> String {
        let display = ReasoningDisplay(mode: mode)
        var responseText = ""
        var hasThinking = false

        for try await event in stream {
            switch event {
            case .thinkingDelta(let text):
                hasThinking = true
                display.displayThinking(text)
            case .textDelta(let text):
                if hasThinking {
                    display.finishThinking()
                    hasThinking = false
                }
                print(text, terminator: "")
                fflush(stdout)
                responseText += text
            case .finish:
                if hasThinking {
                    display.finishThinking()
                }
                print("")
            default:
                break
            }
        }

        return responseText
    }
}

// MARK: - Stream Event Types (for reasoning display)

public enum StreamEvent {
    case start(id: String, model: String)
    case thinkingDelta(String)
    case textDelta(String)
    case toolCall(name: String, arguments: String)
    case finish(reason: String)
}
