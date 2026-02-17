//
//  ProgressiveJSONParser.swift
//  AISDK
//
//  Bridges LLM text deltas into SpecPatchBatch events for progressive UI rendering.
//  Accumulates text, detects Generative UI JSON, progressively parses partial JSON,
//  diffs against previous state, and emits RFC 6902 patches.
//

import Foundation
import os.log

// MARK: - ProgressiveJSONParser

/// Converts streaming text deltas containing Generative UI JSON into progressive
/// `SpecPatchBatch` events.
///
/// LLMs stream UI specifications as text (e.g., `{"root": "main", "elements": {...}}`).
/// This parser accumulates deltas, detects JSON boundaries, repairs partial JSON for
/// progressive parsing, and diffs against the previous snapshot to emit incremental patches.
///
/// ## Usage
/// ```swift
/// let parser = ProgressiveJSONParser()
/// for delta in textDeltas {
///     let batches = parser.feed(delta)
///     for batch in batches {
///         compiler.apply(batch)  // Feed into SpecStreamCompiler
///     }
/// }
/// ```
public final class ProgressiveJSONParser: @unchecked Sendable {
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.aisdk", category: "ProgressiveJSONParser")

    /// Accumulated text from all deltas
    private var buffer: String = ""

    /// Character offset where JSON object starts (nil = not yet detected)
    private var jsonStartOffset: Int?

    /// Brace depth tracker for JSON boundary detection
    private var braceDepth: Int = 0

    /// Character offset where JSON object ends (set when braceDepth returns to 0)
    private var jsonEndOffset: Int?

    /// String literal tracking
    private var inString: Bool = false
    private var escapeNext: Bool = false

    /// Last successfully parsed snapshot (for diffing)
    private var lastSnapshot: ParsedSpec?

    /// Minimum bytes of new JSON content before attempting a parse (reduces overhead)
    private var lastParseLength: Int = 0
    private static let parseThreshold = 8

    public init() {}

    // MARK: - Public API

    /// Feed a text delta chunk and receive any resulting patch batches.
    ///
    /// Returns an empty array when no new patches are generated (either no JSON detected
    /// yet, or the partial parse hasn't changed enough to produce new patches).
    public func feed(_ delta: String) -> [SpecPatchBatch] {
        lock.lock()
        defer { lock.unlock() }

        let previousBufferCount = buffer.count
        buffer += delta

        // Scan new characters for JSON boundary tracking
        var charOffset = 0
        for char in delta {
            if escapeNext {
                escapeNext = false
                charOffset += 1
                continue
            }

            if char == "\\" && inString {
                escapeNext = true
                charOffset += 1
                continue
            }

            if char == "\"" {
                inString = !inString
                charOffset += 1
                continue
            }

            if inString { charOffset += 1; continue }

            switch char {
            case "{":
                if braceDepth == 0 && jsonStartOffset == nil {
                    jsonStartOffset = previousBufferCount + charOffset
                    jsonEndOffset = nil
                }
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
                if braceDepth == 0 && jsonStartOffset != nil {
                    jsonEndOffset = previousBufferCount + charOffset + 1
                }
            default:
                break
            }
            charOffset += 1
        }

        guard let startOffset = jsonStartOffset else {
            return []
        }

        // Extract JSON fragment — trim to JSON boundary if complete
        let startIndex = buffer.index(buffer.startIndex, offsetBy: startOffset)
        let fragment: String
        if let endOffset = jsonEndOffset, endOffset <= buffer.count {
            let endIndex = buffer.index(buffer.startIndex, offsetBy: endOffset)
            fragment = String(buffer[startIndex..<endIndex])
        } else {
            fragment = String(buffer[startIndex...])
        }

        // Throttle: only parse if enough new content has arrived, or JSON is complete
        let jsonComplete = jsonEndOffset != nil
        guard fragment.count - lastParseLength >= Self.parseThreshold || jsonComplete else {
            return []
        }

        // Attempt progressive parse
        guard let newSnapshot = tryPartialParse(fragment) else {
            return []
        }

        lastParseLength = fragment.count

        // Diff against previous snapshot
        let patches = diff(old: lastSnapshot, new: newSnapshot)

        guard !patches.isEmpty else { return [] }

        lastSnapshot = newSnapshot
        let batch = SpecPatchBatch(patches: patches)
        return [batch]
    }

    /// Reset all parser state. Call between agent turns.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        buffer = ""
        jsonStartOffset = nil
        jsonEndOffset = nil
        braceDepth = 0
        inString = false
        escapeNext = false
        lastSnapshot = nil
        lastParseLength = 0
    }

    // MARK: - Partial JSON Parsing

    /// Attempt to parse a potentially incomplete JSON fragment.
    private func tryPartialParse(_ fragment: String) -> ParsedSpec? {
        // Try complete parse first
        if let spec = parseComplete(fragment) {
            return spec
        }

        // Repair incomplete JSON and retry
        let repaired = repairJSON(fragment)
        return parseComplete(repaired)
    }

    /// Parse a complete JSON string into a ParsedSpec.
    private func parseComplete(_ json: String) -> ParsedSpec? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return extractSpec(from: obj)
    }

    /// Extract a ParsedSpec from a parsed JSON dictionary.
    /// Detects both UISpec format (`root`/`elements`) and flat element lists.
    private func extractSpec(from obj: [String: Any]) -> ParsedSpec? {
        var root: String?
        var elements: [String: ParsedElement] = [:]
        var state: [String: SpecValue] = [:]

        // Extract root
        if let r = obj["root"] as? String {
            root = r
        }

        // Extract elements
        if let elems = obj["elements"] as? [String: Any] {
            for (key, value) in elems {
                if let elemDict = value as? [String: Any],
                   let element = parseElement(from: elemDict) {
                    elements[key] = element
                }
            }
        }

        // Extract state
        if let stateDict = obj["state"] as? [String: Any] {
            for (key, value) in stateDict {
                state[key] = anyToSpecValue(value)
            }
        }

        // Must have at least root or elements to be considered a UI spec
        guard root != nil || !elements.isEmpty else {
            return nil
        }

        return ParsedSpec(root: root, elements: elements, state: state)
    }

    /// Parse a single element from its JSON dictionary.
    private func parseElement(from dict: [String: Any]) -> ParsedElement? {
        guard let type = dict["type"] as? String else { return nil }

        var props: [String: SpecValue] = [:]
        if let propsDict = dict["props"] as? [String: Any] {
            for (key, value) in propsDict {
                props[key] = anyToSpecValue(value)
            }
        }

        var children: [String]?
        if let childArray = dict["children"] as? [String] {
            children = childArray
        }

        return ParsedElement(type: type, props: props, children: children)
    }

    // MARK: - JSON Repair

    /// Repair incomplete JSON by closing open structures.
    private func repairJSON(_ fragment: String) -> String {
        var result = fragment
        var openBraces = 0
        var openBrackets = 0
        var inStr = false
        var escape = false
        var lastNonWhitespace: Character?

        for char in result {
            if escape { escape = false; lastNonWhitespace = char; continue }
            if char == "\\" && inStr { escape = true; lastNonWhitespace = char; continue }
            if char == "\"" { inStr = !inStr; lastNonWhitespace = char; continue }
            if inStr { lastNonWhitespace = char; continue }

            if !char.isWhitespace {
                lastNonWhitespace = char
            }

            switch char {
            case "{": openBraces += 1
            case "}": openBraces -= 1
            case "[": openBrackets += 1
            case "]": openBrackets -= 1
            default: break
            }
        }

        // Close open string
        if inStr {
            result += "\""
        }

        // Remove trailing comma or colon (invalid before closing)
        if let last = lastNonWhitespace, (last == "," || last == ":") {
            if let idx = result.lastIndex(where: { $0 == last }) {
                // Only remove if it's the last non-whitespace
                let after = result[result.index(after: idx)...]
                if after.allSatisfy(\.isWhitespace) {
                    result = String(result[..<idx])
                }
            }
        }

        // Close brackets then braces
        for _ in 0..<max(0, openBrackets) { result += "]" }
        for _ in 0..<max(0, openBraces) { result += "}" }

        return result
    }

    // MARK: - Diffing

    /// Diff two spec snapshots and produce RFC 6902 patches.
    private func diff(old: ParsedSpec?, new: ParsedSpec) -> [SpecPatch] {
        var patches: [SpecPatch] = []
        let old = old ?? ParsedSpec(root: nil, elements: [:], state: [:])

        // Root
        if old.root != new.root, let newRoot = new.root {
            let op: SpecPatch.Operation = old.root == nil ? .add : .replace
            patches.append(SpecPatch(op: op, path: "/root", value: SpecValue(newRoot)))
        }

        // Elements: added or changed
        for (key, newElement) in new.elements {
            if let oldElement = old.elements[key] {
                if oldElement != newElement {
                    patches.append(SpecPatch(
                        op: .replace,
                        path: "/elements/\(key)",
                        value: elementToSpecValue(newElement)
                    ))
                }
            } else {
                patches.append(SpecPatch(
                    op: .add,
                    path: "/elements/\(key)",
                    value: elementToSpecValue(newElement)
                ))
            }
        }

        // Elements: removed
        for key in old.elements.keys where new.elements[key] == nil {
            patches.append(SpecPatch(op: .remove, path: "/elements/\(key)"))
        }

        // State: added or changed
        for (key, newValue) in new.state {
            if let oldValue = old.state[key], oldValue == newValue { continue }
            let op: SpecPatch.Operation = old.state[key] == nil ? .add : .replace
            patches.append(SpecPatch(op: op, path: "/state/\(key)", value: newValue))
        }

        // State: removed
        for key in old.state.keys where new.state[key] == nil {
            patches.append(SpecPatch(op: .remove, path: "/state/\(key)"))
        }

        return patches
    }

    // MARK: - Helpers

    /// Convert a ParsedElement to a SpecValue dictionary matching SpecStreamCompiler's format.
    private func elementToSpecValue(_ element: ParsedElement) -> SpecValue {
        var dict: [String: SpecValue] = [:]
        dict["type"] = SpecValue(element.type)

        if !element.props.isEmpty {
            dict["props"] = SpecValue(element.props)
        }

        if let children = element.children {
            dict["children"] = SpecValue(children.map { SpecValue($0) })
        }

        return SpecValue(dict)
    }

    /// Convert an arbitrary JSON value to SpecValue.
    private func anyToSpecValue(_ value: Any) -> SpecValue {
        switch value {
        case let s as String:
            return SpecValue(s)
        case let b as Bool:
            return SpecValue(b)
        case let i as Int:
            return SpecValue(i)
        case let d as Double:
            return SpecValue(d)
        case let arr as [Any]:
            return SpecValue(arr.map { anyToSpecValue($0) })
        case let dict as [String: Any]:
            var result: [String: SpecValue] = [:]
            for (k, v) in dict { result[k] = anyToSpecValue(v) }
            return SpecValue(result)
        case is NSNull:
            return .null
        default:
            return SpecValue("\(value)")
        }
    }
}

// MARK: - Internal Types

/// A snapshot of the parsed UI spec for diffing.
struct ParsedSpec: Equatable {
    let root: String?
    let elements: [String: ParsedElement]
    let state: [String: SpecValue]
}

/// A parsed UI element for diffing.
struct ParsedElement: Equatable {
    let type: String
    let props: [String: SpecValue]
    let children: [String]?
}
