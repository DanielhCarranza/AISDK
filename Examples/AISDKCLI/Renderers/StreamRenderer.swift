//
//  StreamRenderer.swift
//  AISDKCLI
//
//  Real-time streaming text renderer
//

import Foundation

/// Real-time streaming text renderer
class StreamRenderer {
    /// Buffer for accumulated text
    private var buffer: String = ""

    /// Current line being rendered
    private var currentLine: String = ""

    /// Whether we're in a code block
    private var inCodeBlock = false

    /// Code block language (if any)
    private var codeLanguage: String?

    /// Line count for the current response
    private var lineCount = 0

    /// Character count for the current response
    private var charCount = 0

    /// Whether markdown rendering is enabled
    var markdownEnabled = true

    /// Reset the renderer for a new response
    func reset() {
        buffer = ""
        currentLine = ""
        inCodeBlock = false
        codeLanguage = nil
        lineCount = 0
        charCount = 0
    }

    /// Append and render text delta
    func append(_ text: String) {
        buffer += text
        charCount += text.count

        for char in text {
            if char == "\n" {
                flushCurrentLine()
                lineCount += 1
            } else {
                currentLine.append(char)
            }
        }

        // Print inline (partial line)
        if !currentLine.isEmpty {
            printPartialLine()
        }
    }

    /// Flush the current line to output
    private func flushCurrentLine() {
        if markdownEnabled {
            let rendered = renderMarkdown(currentLine)
            // Clear partial line and print full line
            ANSIStyles.clearCurrentLine()
            print(rendered)
        } else {
            ANSIStyles.clearCurrentLine()
            print(currentLine)
        }
        currentLine = ""
    }

    /// Print partial line (for streaming effect)
    private func printPartialLine() {
        if markdownEnabled {
            let rendered = renderMarkdownPartial(currentLine)
            ANSIStyles.clearCurrentLine()
            print(rendered, terminator: "")
        } else {
            ANSIStyles.clearCurrentLine()
            print(currentLine, terminator: "")
        }
        fflush(stdout)
    }

    /// Finish rendering (flush any remaining content)
    func finish() {
        if !currentLine.isEmpty {
            flushCurrentLine()
        }
        print("") // Ensure newline at end
    }

    /// Get statistics about the rendered content
    func getStats() -> (lines: Int, chars: Int) {
        return (lineCount, charCount)
    }

    // MARK: - Markdown Rendering

    /// Render markdown for a complete line
    private func renderMarkdown(_ line: String) -> String {
        var result = line

        // Check for code block markers
        if line.hasPrefix("```") {
            if inCodeBlock {
                inCodeBlock = false
                codeLanguage = nil
                return ANSIStyles.dim("```")
            } else {
                inCodeBlock = true
                codeLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                let lang = codeLanguage?.isEmpty == false ? " \(codeLanguage!)" : ""
                return ANSIStyles.dim("```\(lang)")
            }
        }

        // In code block - syntax highlight
        if inCodeBlock {
            return ANSIStyles.cyan(result)
        }

        // Inline code
        result = applyInlineCode(result)

        // Bold
        result = applyBold(result)

        // Italic
        result = applyItalic(result)

        // Headers
        result = applyHeaders(result)

        // Lists
        result = applyLists(result)

        // Links (simplified)
        result = applyLinks(result)

        return result
    }

    /// Render markdown for partial line (simpler, no multi-char patterns)
    private func renderMarkdownPartial(_ line: String) -> String {
        if inCodeBlock {
            return ANSIStyles.cyan(line)
        }
        return line
    }

    /// Apply inline code formatting (`code`)
    private func applyInlineCode(_ text: String) -> String {
        var result = ""
        var inCode = false
        var i = text.startIndex

        while i < text.endIndex {
            let char = text[i]
            if char == "`" {
                inCode.toggle()
                if inCode {
                    result += ANSIStyles.bgBlack(ANSIStyles.cyan(""))
                } else {
                    result += ANSIStyles.reset
                }
            } else if inCode {
                result += ANSIStyles.cyan(String(char))
            } else {
                result += String(char)
            }
            i = text.index(after: i)
        }

        return result
    }

    /// Apply bold formatting (**bold**)
    private func applyBold(_ text: String) -> String {
        var result = text
        let pattern = "\\*\\*(.+?)\\*\\*"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range,
                withTemplate: ANSIStyles.bold("$1")
            )
        }
        return result
    }

    /// Apply italic formatting (*italic*)
    private func applyItalic(_ text: String) -> String {
        var result = text
        // Match single * but not ** (already handled)
        let pattern = "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range,
                withTemplate: ANSIStyles.italic("$1")
            )
        }
        return result
    }

    /// Apply header formatting (# Header)
    private func applyHeaders(_ text: String) -> String {
        if text.hasPrefix("### ") {
            return ANSIStyles.bold(ANSIStyles.yellow(String(text.dropFirst(4))))
        } else if text.hasPrefix("## ") {
            return ANSIStyles.bold(ANSIStyles.cyan(String(text.dropFirst(3))))
        } else if text.hasPrefix("# ") {
            return ANSIStyles.bold(ANSIStyles.magenta(String(text.dropFirst(2))))
        }
        return text
    }

    /// Apply list formatting (- item, * item, 1. item)
    private func applyLists(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let indent = String(text.prefix(while: { $0 == " " }))

        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let content = String(trimmed.dropFirst(2))
            return "\(indent)\(ANSIStyles.cyan("•")) \(content)"
        }

        // Numbered list
        let numPattern = "^(\\d+)\\.\\s+"
        if let regex = try? NSRegularExpression(pattern: numPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            if let numRange = Range(match.range(at: 1), in: trimmed) {
                let num = String(trimmed[numRange])
                let content = trimmed.replacingCharacters(in: Range(match.range, in: trimmed)!, with: "")
                return "\(indent)\(ANSIStyles.cyan(num + ".")) \(content)"
            }
        }

        return text
    }

    /// Apply link formatting [text](url)
    private func applyLinks(_ text: String) -> String {
        var result = text
        let pattern = "\\[(.+?)\\]\\((.+?)\\)"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range,
                withTemplate: ANSIStyles.underline(ANSIStyles.blue("$1")) + " " + ANSIStyles.dim("($2)")
            )
        }
        return result
    }
}
