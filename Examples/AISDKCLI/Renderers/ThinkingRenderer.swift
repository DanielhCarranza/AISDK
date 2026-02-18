import Foundation
import AISDK

/// Renders extended thinking blocks in the terminal
final class ThinkingRenderer {

    private var isThinkingBlock = false
    private var thinkingContent = ""
    private var collapsed = true

    /// Handle a thinking delta during streaming
    func renderThinkingDelta(_ thinking: String) {
        if !isThinkingBlock {
            isThinkingBlock = true
            print("\n\(ANSIStyles.dim("🧠 Thinking..."))", terminator: "")
        }

        thinkingContent += thinking

        if collapsed {
            let snippet = thinkingContent.suffix(60)
            print("\r\(ANSIStyles.dim("   \(snippet)..."))", terminator: "")
            fflush(stdout)
        }
    }

    /// Render a complete thinking block
    func renderThinkingComplete(_ block: AnthropicThinkingBlock) {
        isThinkingBlock = false

        print("\r\(String(repeating: " ", count: 80))\r", terminator: "")

        print("\n\(ANSIStyles.dim("┌─ 🧠 Thinking ─────────────────────────────────────┐"))")

        let lines = block.thinking.components(separatedBy: .newlines)
        let maxLines = collapsed ? 5 : lines.count

        for line in lines.prefix(maxLines) {
            let truncated = line.prefix(70)
            print("\(ANSIStyles.dim("│ \(truncated)"))")
        }

        if lines.count > maxLines {
            print("\(ANSIStyles.dim("│ ... (\(lines.count - maxLines) more lines)"))")
        }

        print("\(ANSIStyles.dim("└────────────────────────────────────────────────────┘"))")
        print("")

        thinkingContent = ""
    }

    /// Toggle collapsed/expanded view
    func toggleCollapsed() {
        collapsed.toggle()
        print("Thinking view: \(collapsed ? "collapsed" : "expanded")")
    }
}
