//
//  InputReader.swift
//  AISDKCLI
//
//  Enhanced input reading with multi-line support
//

import Foundation

/// Enhanced input reader with multi-line support
class InputReader {
    /// The username to display in prompts
    var username: String

    /// Whether we're in multi-line mode (started with ```)
    private var isMultiLine = false

    /// Buffer for multi-line input
    private var multiLineBuffer: [String] = []

    init(username: String = "You") {
        self.username = username
    }

    /// Read a line of input with support for multi-line mode
    /// Returns nil on EOF (Ctrl+D) or signal interrupt
    func readInput() -> String? {
        if isMultiLine {
            return readMultiLineContinuation()
        } else {
            return readSingleLine()
        }
    }

    /// Get the prompt string to display
    func getPrompt() -> String {
        if isMultiLine {
            return ANSIStyles.dim("... ")
        } else {
            return "\(ANSIStyles.green(username))> "
        }
    }

    /// Read a single line of input
    private func readSingleLine() -> String? {
        print(getPrompt(), terminator: "")
        fflush(stdout)

        guard let line = readLine() else {
            return nil
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Check for multi-line start
        if trimmed == "```" || trimmed.hasPrefix("```") {
            isMultiLine = true
            multiLineBuffer = []

            // If there's content after ```, add it
            let afterBackticks = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if !afterBackticks.isEmpty {
                multiLineBuffer.append(afterBackticks)
            }

            return readMultiLineContinuation()
        }

        return line
    }

    /// Read continuation of multi-line input
    private func readMultiLineContinuation() -> String? {
        while true {
            print(getPrompt(), terminator: "")
            fflush(stdout)

            guard let line = readLine() else {
                // EOF in multi-line mode - return what we have
                let result = multiLineBuffer.joined(separator: "\n")
                isMultiLine = false
                multiLineBuffer = []
                return result.isEmpty ? nil : result
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for multi-line end
            if trimmed == "```" || trimmed.hasSuffix("```") {
                // If there's content before ```, add it
                if trimmed.hasSuffix("```") && trimmed != "```" {
                    let beforeBackticks = String(trimmed.dropLast(3)).trimmingCharacters(in: .whitespaces)
                    if !beforeBackticks.isEmpty {
                        multiLineBuffer.append(beforeBackticks)
                    }
                }

                let result = multiLineBuffer.joined(separator: "\n")
                isMultiLine = false
                multiLineBuffer = []
                return result
            }

            multiLineBuffer.append(line)
        }
    }

    /// Cancel multi-line mode without returning content
    func cancelMultiLine() {
        isMultiLine = false
        multiLineBuffer = []
    }

    /// Check if currently in multi-line mode
    var inMultiLineMode: Bool {
        isMultiLine
    }
}

/// Spinner animation for showing progress
class Spinner {
    private let frames: [String]
    private var frameIndex = 0
    private var isRunning = false
    private var task: Task<Void, Never>?
    private let message: String
    private let interval: TimeInterval

    init(message: String = "", frames: [String] = ANSIStyles.spinnerFrames, interval: TimeInterval = 0.08) {
        self.message = message
        self.frames = frames
        self.interval = interval
    }

    /// Start the spinner animation
    func start() {
        guard !isRunning else { return }
        isRunning = true

        task = Task {
            while isRunning {
                let frame = frames[frameIndex % frames.count]
                ANSIStyles.clearCurrentLine()
                print("\(ANSIStyles.cyan(frame)) \(message)", terminator: "")
                fflush(stdout)
                frameIndex += 1

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// Stop the spinner and clear the line
    func stop(message: String? = nil) {
        isRunning = false
        task?.cancel()
        task = nil
        ANSIStyles.clearCurrentLine()
        if let msg = message {
            print(msg)
        }
    }

    /// Update the spinner message without stopping
    func update(message: String) {
        ANSIStyles.clearCurrentLine()
        let frame = frames[frameIndex % frames.count]
        print("\(ANSIStyles.cyan(frame)) \(message)", terminator: "")
        fflush(stdout)
    }
}

/// Progress bar for showing completion status
class ProgressBar {
    let total: Int
    let width: Int
    private var current = 0
    private let filledChar: Character
    private let emptyChar: Character

    init(total: Int, width: Int = 30, filledChar: Character = "█", emptyChar: Character = "░") {
        self.total = total
        self.width = width
        self.filledChar = filledChar
        self.emptyChar = emptyChar
    }

    /// Update progress
    func update(_ value: Int, message: String = "") {
        current = min(max(0, value), total)
        render(message: message)
    }

    /// Increment progress by 1
    func increment(message: String = "") {
        update(current + 1, message: message)
    }

    private func render(message: String) {
        let progress = total > 0 ? Double(current) / Double(total) : 0
        let filled = Int(progress * Double(width))
        let empty = width - filled

        let bar = String(repeating: filledChar, count: filled) + String(repeating: emptyChar, count: empty)
        let percentage = Int(progress * 100)

        ANSIStyles.clearCurrentLine()
        print("\(ANSIStyles.cyan("["))\(ANSIStyles.green(bar))\(ANSIStyles.cyan("]")) \(percentage)% \(message)", terminator: "")
        fflush(stdout)
    }

    func complete(message: String = "Done") {
        current = total
        ANSIStyles.clearCurrentLine()
        print(ANSIStyles.success(message))
    }
}
