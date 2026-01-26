//
//  TerminalUIRenderer.swift
//  AISDKCLI
//
//  Renderer for GenerativeUI components in terminal format
//

import Foundation
import AISDK

/// Terminal representation of GenerativeUI components
class TerminalUIRenderer {
    /// Current terminal width
    private var terminalWidth: Int

    /// Indentation level for nested components
    private var indentLevel: Int = 0

    /// Indentation string per level
    private let indentString = "  "

    init() {
        self.terminalWidth = TerminalSize.current().width
    }

    /// Refresh terminal width
    func refreshWidth() {
        terminalWidth = TerminalSize.current().width
    }

    // MARK: - UITree Rendering

    func render(tree: UITree) throws -> String {
        refreshWidth()
        indentLevel = 0
        return try renderNode(tree.rootNode, tree: tree)
    }

    private func renderNode(_ node: UINode, tree: UITree) throws -> String {
        switch node.type {
        case TextComponentDefinition.type:
            let props = try decode(TextComponentDefinition.Props.self, from: node.propsData)
            return renderText(props.content, style: mapTextStyle(props.style))

        case ButtonComponentDefinition.type:
            let props = try decode(ButtonComponentDefinition.Props.self, from: node.propsData)
            return renderButton(props.title, action: props.action, style: mapButtonStyle(props.style))

        case CardComponentDefinition.type:
            let props = try decode(CardComponentDefinition.Props.self, from: node.propsData)
            indentLevel += 1
            let childContent = try renderChildren(node, tree: tree).joined(separator: "\n")
            indentLevel -= 1
            return renderCard(title: props.title, content: childContent, footer: props.subtitle)

        case InputComponentDefinition.type:
            let props = try decode(InputComponentDefinition.Props.self, from: node.propsData)
            return renderInput(placeholder: props.placeholder ?? "", value: nil, label: props.label)

        case ListComponentDefinition.type:
            let props = try decode(ListComponentDefinition.Props.self, from: node.propsData)
            let items = try renderChildren(node, tree: tree).map { item in
                item.replacingOccurrences(of: "\n", with: " ")
            }
            return renderList(items, style: mapListStyle(props.style), maxItems: 20)

        case ImageComponentDefinition.type:
            let props = try decode(ImageComponentDefinition.Props.self, from: node.propsData)
            return renderImage(alt: props.alt ?? "Image", url: props.url)

        case StackComponentDefinition.type:
            let props = try decode(StackComponentDefinition.Props.self, from: node.propsData)
            let spacing = max(0, Int(props.spacing ?? 1))
            indentLevel += 1
            let children = try renderChildren(node, tree: tree)
            indentLevel -= 1
            let direction = mapStackDirection(props.direction)
            return renderStack(direction: direction, spacing: spacing, children: children)

        case SpacerComponentDefinition.type:
            let props = try decode(SpacerComponentDefinition.Props.self, from: node.propsData)
            let size = max(1, Int(props.size ?? 1))
            return renderSpacer(size: size)

        default:
            return renderText("Unsupported component: \(node.type)", style: .warning)
        }
    }

    private func renderChildren(_ node: UINode, tree: UITree) throws -> [String] {
        var rendered: [String] = []
        for key in node.childKeys {
            guard let child = tree.nodes[key] else { continue }
            let childRendered = try renderNode(child, tree: tree)
            rendered.append(childRendered)
        }
        return rendered
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    private func mapTextStyle(_ style: String?) -> TextStyle {
        switch style?.lowercased() {
        case "title":
            return .title
        case "headline":
            return .subtitle
        case "subheadline":
            return .body
        case "caption":
            return .caption
        default:
            return .body
        }
    }

    private func mapButtonStyle(_ style: String?) -> ButtonStyle {
        switch style?.lowercased() {
        case "secondary":
            return .secondary
        case "destructive":
            return .destructive
        case "plain":
            return .ghost
        default:
            return .primary
        }
    }

    private func mapListStyle(_ style: UIListStyle?) -> ListStyle {
        switch style {
        case .ordered:
            return .numbered
        case .plain:
            return .bullet
        case .unordered, .none:
            return .bullet
        }
    }

    private func mapStackDirection(_ direction: StackDirection) -> TerminalStackDirection {
        switch direction {
        case .horizontal:
            return .horizontal
        case .vertical:
            return .vertical
        }
    }

    // MARK: - Core 8 Component Renderers

    /// Render a text component
    func renderText(_ text: String, style: TextStyle = .body) -> String {
        let styled: String
        switch style {
        case .title:
            styled = ANSIStyles.bold(ANSIStyles.cyan(text))
        case .subtitle:
            styled = ANSIStyles.bold(text)
        case .body:
            styled = text
        case .caption:
            styled = ANSIStyles.dim(text)
        case .code:
            styled = ANSIStyles.cyan(text)
        case .error:
            styled = ANSIStyles.red(text)
        case .success:
            styled = ANSIStyles.green(text)
        case .warning:
            styled = ANSIStyles.yellow(text)
        }
        return indent(styled)
    }

    /// Render a button component
    func renderButton(_ label: String, action: String? = nil, style: ButtonStyle = .primary) -> String {
        let styled: String
        switch style {
        case .primary:
            styled = "[ " + ANSIStyles.bold(ANSIStyles.cyan(label)) + " ]"
        case .secondary:
            styled = "[ " + label + " ]"
        case .destructive:
            styled = "[ " + ANSIStyles.red(label) + " ]"
        case .ghost:
            styled = "  " + ANSIStyles.underline(label) + "  "
        }

        if let action = action {
            return indent(styled + ANSIStyles.dim(" → \(action)"))
        }
        return indent(styled)
    }

    /// Render a card component
    func renderCard(title: String? = nil, content: String, footer: String? = nil) -> String {
        let width = min(60, terminalWidth - 4 - (indentLevel * 2))
        var lines: [String] = []

        // Top border
        lines.append("┌" + String(repeating: "─", count: width - 2) + "┐")

        // Title
        if let title = title {
            let titleLine = " " + ANSIStyles.bold(title)
            lines.append("│" + padRight(titleLine, width: width - 2) + "│")
            lines.append("├" + String(repeating: "─", count: width - 2) + "┤")
        }

        // Content
        let contentLines = wrapText(content, maxWidth: width - 4)
        for line in contentLines {
            lines.append("│ " + padRight(line, width: width - 4) + " │")
        }

        // Footer
        if let footer = footer {
            lines.append("├" + String(repeating: "─", count: width - 2) + "┤")
            let footerLine = " " + ANSIStyles.dim(footer)
            lines.append("│" + padRight(footerLine, width: width - 2) + "│")
        }

        // Bottom border
        lines.append("└" + String(repeating: "─", count: width - 2) + "┘")

        return lines.map { indent($0) }.joined(separator: "\n")
    }

    /// Render an input component
    func renderInput(placeholder: String, value: String? = nil, label: String? = nil) -> String {
        var lines: [String] = []

        if let label = label {
            lines.append(ANSIStyles.dim(label))
        }

        let displayValue = value ?? ANSIStyles.dim(placeholder)
        let inputLine = "> " + displayValue + ANSIStyles.blink("_")

        lines.append(inputLine)
        lines.append(ANSIStyles.dim(String(repeating: "─", count: min(40, terminalWidth - 4))))

        return lines.map { indent($0) }.joined(separator: "\n")
    }

    /// Render a list component
    func renderList(_ items: [String], style: ListStyle = .bullet, maxItems: Int = 10) -> String {
        var lines: [String] = []

        for (index, item) in items.prefix(maxItems).enumerated() {
            let marker: String
            switch style {
            case .bullet:
                marker = ANSIStyles.cyan("•")
            case .numbered:
                marker = ANSIStyles.cyan("\(index + 1).")
            case .checkbox(let checked):
                let isChecked = index < checked.count && checked[index]
                marker = isChecked ? ANSIStyles.green("☑") : ANSIStyles.dim("☐")
            case .arrow:
                marker = ANSIStyles.cyan("→")
            }

            lines.append("\(marker) \(item)")
        }

        if items.count > maxItems {
            lines.append(ANSIStyles.dim("  ... and \(items.count - maxItems) more"))
        }

        return lines.map { indent($0) }.joined(separator: "\n")
    }

    /// Render an image component (placeholder in terminal)
    func renderImage(alt: String, url: String? = nil) -> String {
        var lines: [String] = []

        lines.append("┌" + String(repeating: "─", count: 30) + "┐")
        lines.append("│" + padCenter(ANSIStyles.dim("🖼"), width: 30) + "│")
        lines.append("│" + padCenter(ANSIStyles.italic("[Image]"), width: 30) + "│")
        lines.append("│" + padCenter(alt, width: 30) + "│")
        lines.append("└" + String(repeating: "─", count: 30) + "┘")

        if let url = url {
            lines.append(ANSIStyles.dim("  URL: \(url.prefix(40))..."))
        }

        return lines.map { indent($0) }.joined(separator: "\n")
    }

    /// Render a stack (vertical or horizontal group)
    func renderStack(direction: TerminalStackDirection, spacing: Int = 1, children: [String]) -> String {
        switch direction {
        case .vertical:
            let spacer = String(repeating: "\n", count: spacing)
            return children.joined(separator: spacer)

        case .horizontal:
            // For horizontal, we try to arrange side by side if space permits
            // This is simplified - true horizontal layout is complex in terminal
            let separator = String(repeating: " ", count: spacing)
            return children.joined(separator: separator)
        }
    }

    /// Render a spacer
    func renderSpacer(size: Int = 1) -> String {
        return String(repeating: "\n", count: size)
    }

    // MARK: - Additional Components

    /// Render a table
    func renderTable(headers: [String], rows: [[String]]) -> String {
        guard !headers.isEmpty else { return "" }

        // Calculate column widths
        var colWidths = headers.map { $0.count }
        for row in rows {
            for (index, cell) in row.enumerated() where index < colWidths.count {
                colWidths[index] = max(colWidths[index], cell.count)
            }
        }

        // Cap widths
        let maxWidth = (terminalWidth - 4 - (headers.count * 3)) / headers.count
        colWidths = colWidths.map { min($0, maxWidth) }

        var lines: [String] = []

        // Header separator
        let separator = "┼" + colWidths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┼") + "┼"
        let topBorder = "┌" + colWidths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┬") + "┐"
        let bottomBorder = "└" + colWidths.map { String(repeating: "─", count: $0 + 2) }.joined(separator: "┴") + "┘"

        lines.append(topBorder)

        // Headers
        var headerLine = "│"
        for (index, header) in headers.enumerated() {
            let padded = " " + padRight(ANSIStyles.bold(header), width: colWidths[index]) + " "
            headerLine += padded + "│"
        }
        lines.append(headerLine)
        lines.append(separator.replacingOccurrences(of: "┼", with: "├").replacingOccurrences(of: "┼", with: "┤"))

        // Rows
        for row in rows {
            var rowLine = "│"
            for (index, cell) in row.enumerated() where index < colWidths.count {
                let padded = " " + padRight(cell, width: colWidths[index]) + " "
                rowLine += padded + "│"
            }
            lines.append(rowLine)
        }

        lines.append(bottomBorder)

        return lines.map { indent($0) }.joined(separator: "\n")
    }

    /// Render a progress bar
    func renderProgressBar(value: Double, label: String? = nil) -> String {
        let width = min(40, terminalWidth - 10)
        let filled = Int(value * Double(width))
        let empty = width - filled

        let bar = ANSIStyles.green(String(repeating: "█", count: filled)) +
                  ANSIStyles.dim(String(repeating: "░", count: empty))

        let percentage = Int(value * 100)

        var result = "[\(bar)] \(percentage)%"
        if let label = label {
            result = ANSIStyles.dim(label) + "\n" + result
        }

        return indent(result)
    }

    /// Render a divider
    func renderDivider(style: DividerStyle = .solid) -> String {
        let width = terminalWidth - (indentLevel * 2) - 2
        let char: String
        switch style {
        case .solid:
            char = "─"
        case .dashed:
            char = "╌"
        case .dotted:
            char = "┄"
        case .double:
            char = "═"
        }
        return indent(ANSIStyles.dim(String(repeating: char, count: width)))
    }

    /// Render a badge/tag
    func renderBadge(_ text: String, style: BadgeStyle = .default) -> String {
        let styled: String
        switch style {
        case .default:
            styled = ANSIStyles.inverse(" \(text) ")
        case .success:
            styled = ANSIStyles.bgGreen(ANSIStyles.white(" \(text) "))
        case .warning:
            styled = ANSIStyles.bgYellow(ANSIStyles.black(" \(text) "))
        case .error:
            styled = ANSIStyles.bgRed(ANSIStyles.white(" \(text) "))
        case .info:
            styled = ANSIStyles.bgBlue(ANSIStyles.white(" \(text) "))
        }
        return styled
    }

    // MARK: - Helper Methods

    /// Increase indentation level
    func pushIndent() {
        indentLevel += 1
    }

    /// Decrease indentation level
    func popIndent() {
        indentLevel = max(0, indentLevel - 1)
    }

    /// Apply current indentation
    private func indent(_ text: String) -> String {
        let indent = String(repeating: indentString, count: indentLevel)
        return indent + text
    }

    /// Pad string to right
    private func padRight(_ text: String, width: Int) -> String {
        let stripped = ANSIStyles.stripANSI(text)
        let padding = max(0, width - stripped.count)
        return text + String(repeating: " ", count: padding)
    }

    /// Pad string to center
    private func padCenter(_ text: String, width: Int) -> String {
        let stripped = ANSIStyles.stripANSI(text)
        let totalPadding = max(0, width - stripped.count)
        let leftPadding = totalPadding / 2
        let rightPadding = totalPadding - leftPadding
        return String(repeating: " ", count: leftPadding) + text + String(repeating: " ", count: rightPadding)
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

// MARK: - Style Enums

enum TextStyle {
    case title, subtitle, body, caption, code, error, success, warning
}

enum ButtonStyle {
    case primary, secondary, destructive, ghost
}

enum ListStyle {
    case bullet
    case numbered
    case checkbox([Bool])
    case arrow
}

enum TerminalStackDirection {
    case vertical, horizontal
}

enum DividerStyle {
    case solid, dashed, dotted, double
}

enum BadgeStyle {
    case `default`, success, warning, error, info
}
