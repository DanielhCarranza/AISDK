//
//  ANSIStyles.swift
//  AISDKCLI
//
//  ANSI escape code utilities for terminal styling
//

import Foundation

/// ANSI escape code utilities for terminal styling
enum ANSIStyles {
    // MARK: - Reset

    static let reset = "\u{001B}[0m"

    // MARK: - Text Styles

    static func bold(_ text: String) -> String {
        "\u{001B}[1m\(text)\(reset)"
    }

    static func dim(_ text: String) -> String {
        "\u{001B}[2m\(text)\(reset)"
    }

    static func italic(_ text: String) -> String {
        "\u{001B}[3m\(text)\(reset)"
    }

    static func underline(_ text: String) -> String {
        "\u{001B}[4m\(text)\(reset)"
    }

    static func blink(_ text: String) -> String {
        "\u{001B}[5m\(text)\(reset)"
    }

    static func inverse(_ text: String) -> String {
        "\u{001B}[7m\(text)\(reset)"
    }

    static func strikethrough(_ text: String) -> String {
        "\u{001B}[9m\(text)\(reset)"
    }

    // MARK: - Foreground Colors

    static func black(_ text: String) -> String {
        "\u{001B}[30m\(text)\(reset)"
    }

    static func red(_ text: String) -> String {
        "\u{001B}[31m\(text)\(reset)"
    }

    static func green(_ text: String) -> String {
        "\u{001B}[32m\(text)\(reset)"
    }

    static func yellow(_ text: String) -> String {
        "\u{001B}[33m\(text)\(reset)"
    }

    static func blue(_ text: String) -> String {
        "\u{001B}[34m\(text)\(reset)"
    }

    static func magenta(_ text: String) -> String {
        "\u{001B}[35m\(text)\(reset)"
    }

    static func cyan(_ text: String) -> String {
        "\u{001B}[36m\(text)\(reset)"
    }

    static func white(_ text: String) -> String {
        "\u{001B}[37m\(text)\(reset)"
    }

    // MARK: - Bright Foreground Colors

    static func brightBlack(_ text: String) -> String {
        "\u{001B}[90m\(text)\(reset)"
    }

    static func brightRed(_ text: String) -> String {
        "\u{001B}[91m\(text)\(reset)"
    }

    static func brightGreen(_ text: String) -> String {
        "\u{001B}[92m\(text)\(reset)"
    }

    static func brightYellow(_ text: String) -> String {
        "\u{001B}[93m\(text)\(reset)"
    }

    static func brightBlue(_ text: String) -> String {
        "\u{001B}[94m\(text)\(reset)"
    }

    static func brightMagenta(_ text: String) -> String {
        "\u{001B}[95m\(text)\(reset)"
    }

    static func brightCyan(_ text: String) -> String {
        "\u{001B}[96m\(text)\(reset)"
    }

    static func brightWhite(_ text: String) -> String {
        "\u{001B}[97m\(text)\(reset)"
    }

    // MARK: - Background Colors

    static func bgBlack(_ text: String) -> String {
        "\u{001B}[40m\(text)\(reset)"
    }

    static func bgRed(_ text: String) -> String {
        "\u{001B}[41m\(text)\(reset)"
    }

    static func bgGreen(_ text: String) -> String {
        "\u{001B}[42m\(text)\(reset)"
    }

    static func bgYellow(_ text: String) -> String {
        "\u{001B}[43m\(text)\(reset)"
    }

    static func bgBlue(_ text: String) -> String {
        "\u{001B}[44m\(text)\(reset)"
    }

    static func bgMagenta(_ text: String) -> String {
        "\u{001B}[45m\(text)\(reset)"
    }

    static func bgCyan(_ text: String) -> String {
        "\u{001B}[46m\(text)\(reset)"
    }

    static func bgWhite(_ text: String) -> String {
        "\u{001B}[47m\(text)\(reset)"
    }

    // MARK: - 256 Color Support

    static func fg256(_ colorCode: Int, _ text: String) -> String {
        "\u{001B}[38;5;\(colorCode)m\(text)\(reset)"
    }

    static func bg256(_ colorCode: Int, _ text: String) -> String {
        "\u{001B}[48;5;\(colorCode)m\(text)\(reset)"
    }

    // MARK: - RGB Color Support

    static func fgRGB(_ r: Int, _ g: Int, _ b: Int, _ text: String) -> String {
        "\u{001B}[38;2;\(r);\(g);\(b)m\(text)\(reset)"
    }

    static func bgRGB(_ r: Int, _ g: Int, _ b: Int, _ text: String) -> String {
        "\u{001B}[48;2;\(r);\(g);\(b)m\(text)\(reset)"
    }

    // MARK: - Cursor Control

    static func moveCursor(up: Int) -> String {
        "\u{001B}[\(up)A"
    }

    static func moveCursor(down: Int) -> String {
        "\u{001B}[\(down)B"
    }

    static func moveCursor(right: Int) -> String {
        "\u{001B}[\(right)C"
    }

    static func moveCursor(left: Int) -> String {
        "\u{001B}[\(left)D"
    }

    static func moveCursor(row: Int, col: Int) -> String {
        "\u{001B}[\(row);\(col)H"
    }

    static let saveCursor = "\u{001B}[s"
    static let restoreCursor = "\u{001B}[u"
    static let hideCursor = "\u{001B}[?25l"
    static let showCursor = "\u{001B}[?25h"

    // MARK: - Line Control

    static let clearLine = "\u{001B}[2K"
    static let clearLineFromCursor = "\u{001B}[K"
    static let clearLineToStart = "\u{001B}[1K"
    static let carriageReturn = "\r"

    /// Clear current line and return to start
    static func clearCurrentLine() {
        print("\r\u{001B}[K", terminator: "")
        fflush(stdout)
    }

    // MARK: - Screen Control

    static let clearScreen = "\u{001B}[2J"
    static let clearScreenFromCursor = "\u{001B}[J"
    static let clearScreenToStart = "\u{001B}[1J"

    /// Clear screen and move cursor to top-left
    static func resetScreen() {
        print("\u{001B}[2J\u{001B}[H", terminator: "")
        fflush(stdout)
    }

    // MARK: - Semantic Styles

    /// Success message (green)
    static func success(_ text: String) -> String {
        green("✓ \(text)")
    }

    /// Error message (red)
    static func error(_ text: String) -> String {
        red("✗ \(text)")
    }

    /// Warning message (yellow)
    static func warning(_ text: String) -> String {
        yellow("⚠ \(text)")
    }

    /// Info message (blue)
    static func info(_ text: String) -> String {
        blue("ℹ \(text)")
    }

    /// Highlight (cyan background)
    static func highlight(_ text: String) -> String {
        "\u{001B}[46m\u{001B}[30m \(text) \(reset)"
    }

    /// Selected item (inverse)
    static func selected(_ text: String) -> String {
        inverse(text)
    }

    // MARK: - Box Drawing

    /// Draw a box around text
    static func box(_ content: String, width: Int? = nil) -> String {
        let lines = content.components(separatedBy: "\n")
        let maxWidth = width ?? (lines.map { stripANSI($0).count }.max() ?? 0)
        let boxWidth = maxWidth + 2

        var result = "┌" + String(repeating: "─", count: boxWidth) + "┐\n"

        for line in lines {
            let strippedLine = stripANSI(line)
            let padding = boxWidth - strippedLine.count - 2
            result += "│ \(line)\(String(repeating: " ", count: max(0, padding))) │\n"
        }

        result += "└" + String(repeating: "─", count: boxWidth) + "┘"
        return result
    }

    /// Draw a double-line box around text
    static func doubleBox(_ content: String, width: Int? = nil) -> String {
        let lines = content.components(separatedBy: "\n")
        let maxWidth = width ?? (lines.map { stripANSI($0).count }.max() ?? 0)
        let boxWidth = maxWidth + 2

        var result = "╔" + String(repeating: "═", count: boxWidth) + "╗\n"

        for line in lines {
            let strippedLine = stripANSI(line)
            let padding = boxWidth - strippedLine.count - 2
            result += "║ \(line)\(String(repeating: " ", count: max(0, padding))) ║\n"
        }

        result += "╚" + String(repeating: "═", count: boxWidth) + "╝"
        return result
    }

    // MARK: - Helper

    /// Strip ANSI escape codes from text (for calculating true width)
    static func stripANSI(_ text: String) -> String {
        // Match ANSI escape sequences: ESC [ ... m (and other codes)
        let pattern = "\\u001B\\[[0-9;]*[A-Za-z]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    // MARK: - Spinner Animation

    static let spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    static let spinnerFrames2 = ["◐", "◓", "◑", "◒"]
    static let spinnerFrames3 = ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]
}

// MARK: - String Extension for Repeating

extension String {
    static func * (lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}
