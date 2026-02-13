//
//  ComputerUseAction.swift
//  AISDK
//
//  Unified, provider-agnostic computer use action types
//

import Foundation

/// A unified, provider-agnostic computer use action.
/// Provider adapters translate between this enum and wire format.
public enum ComputerUseAction: Sendable, Equatable {
    case screenshot
    case click(x: Int, y: Int, button: ClickButton = .left)
    case doubleClick(x: Int, y: Int)
    case tripleClick(x: Int, y: Int)
    case type(text: String)
    case keypress(keys: [String])
    case scroll(x: Int, y: Int, scrollX: Int? = nil, scrollY: Int? = nil,
                direction: ScrollDirection? = nil, amount: Int? = nil)
    case move(x: Int, y: Int)
    case drag(path: [Coordinate])
    case wait(durationMs: Int? = nil)
    case cursorPosition
    case zoom(region: [Int]) // [x1, y1, x2, y2]

    public enum ClickButton: String, Sendable, Equatable, Codable {
        case left, right, middle, back, forward, wheel
    }

    public enum ScrollDirection: String, Sendable, Equatable, Codable {
        case up, down, left, right
    }

    public struct Coordinate: Sendable, Equatable, Codable {
        public let x: Int
        public let y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    public struct SafetyCheck: Sendable, Equatable, Codable {
        public let id: String
        public let code: String
        public let message: String

        public init(id: String, code: String, message: String) {
            self.id = id
            self.code = code
            self.message = message
        }
    }
}

/// Represents a complete computer use tool call from the model.
public struct ComputerUseToolCall: Sendable, Equatable {
    /// Tool call ID for result correlation
    public let id: String
    /// OpenAI-specific call_id (nil for Anthropic)
    public let callId: String?
    /// The parsed action
    public let action: ComputerUseAction
    /// Safety checks from the provider (OpenAI only; empty for Anthropic)
    public let safetyChecks: [ComputerUseAction.SafetyCheck]

    public init(
        id: String,
        callId: String? = nil,
        action: ComputerUseAction,
        safetyChecks: [ComputerUseAction.SafetyCheck] = []
    ) {
        self.id = id
        self.callId = callId
        self.action = action
        self.safetyChecks = safetyChecks
    }
}

// MARK: - Provider Parsing

extension ComputerUseAction {
    /// Parse from Anthropic tool_use arguments.
    ///
    /// Anthropic sends computer actions as `tool_use` blocks with `name: "computer"`
    /// and an `action` field in the arguments.
    static func fromAnthropic(_ arguments: [String: Any]) -> ComputerUseAction? {
        guard let actionStr = arguments["action"] as? String else { return nil }

        switch actionStr {
        case "screenshot":
            return .screenshot

        case "left_click":
            guard let coord = arguments["coordinate"] as? [Int], coord.count == 2 else { return nil }
            return .click(x: coord[0], y: coord[1], button: .left)

        case "right_click":
            guard let coord = arguments["coordinate"] as? [Int], coord.count == 2 else { return nil }
            return .click(x: coord[0], y: coord[1], button: .right)

        case "middle_click":
            guard let coord = arguments["coordinate"] as? [Int], coord.count == 2 else { return nil }
            return .click(x: coord[0], y: coord[1], button: .middle)

        case "double_click":
            guard let coord = arguments["coordinate"] as? [Int], coord.count == 2 else { return nil }
            return .doubleClick(x: coord[0], y: coord[1])

        case "triple_click":
            guard let coord = arguments["coordinate"] as? [Int], coord.count == 2 else { return nil }
            return .tripleClick(x: coord[0], y: coord[1])

        case "type":
            guard let text = arguments["text"] as? String else { return nil }
            return .type(text: text)

        case "key":
            guard let text = arguments["text"] as? String else { return nil }
            return .keypress(keys: text.components(separatedBy: "+"))

        case "scroll":
            guard let coord = arguments["coordinate"] as? [Int], coord.count == 2 else { return nil }
            let direction: ScrollDirection?
            if let dirStr = arguments["direction"] as? String {
                direction = ScrollDirection(rawValue: dirStr)
            } else {
                direction = nil
            }
            let amount = arguments["amount"] as? Int
            return .scroll(x: coord[0], y: coord[1], direction: direction, amount: amount)

        case "mouse_move":
            guard let coord = arguments["coordinate"] as? [Int], coord.count == 2 else { return nil }
            return .move(x: coord[0], y: coord[1])

        case "left_click_drag":
            guard let startCoord = arguments["start_coordinate"] as? [Int], startCoord.count == 2,
                  let endCoord = arguments["coordinate"] as? [Int], endCoord.count == 2 else { return nil }
            return .drag(path: [
                Coordinate(x: startCoord[0], y: startCoord[1]),
                Coordinate(x: endCoord[0], y: endCoord[1])
            ])

        case "wait":
            let durationMs = arguments["duration"] as? Int
            return .wait(durationMs: durationMs)

        case "cursor_position":
            return .cursorPosition

        case "zoom":
            guard let region = arguments["region"] as? [Int] else { return nil }
            return .zoom(region: region)

        default:
            return nil
        }
    }

    /// Parse from OpenAI computer_call action.
    static func fromOpenAI(type: String, x: Int?, y: Int?, button: String?,
                           text: String?, keys: [String]?, scrollX: Int?, scrollY: Int?,
                           path: [(x: Int, y: Int)]?, ms: Int?) -> ComputerUseAction? {
        switch type {
        case "screenshot":
            return .screenshot

        case "click":
            guard let x = x, let y = y else { return nil }
            let btn = ClickButton(rawValue: button ?? "left") ?? .left
            return .click(x: x, y: y, button: btn)

        case "double_click":
            guard let x = x, let y = y else { return nil }
            return .doubleClick(x: x, y: y)

        case "type":
            guard let text = text else { return nil }
            return .type(text: text)

        case "keypress":
            guard let keys = keys else { return nil }
            return .keypress(keys: keys)

        case "scroll":
            guard let x = x, let y = y else { return nil }
            return .scroll(x: x, y: y, scrollX: scrollX, scrollY: scrollY)

        case "move":
            guard let x = x, let y = y else { return nil }
            return .move(x: x, y: y)

        case "drag":
            guard let pathPoints = path else { return nil }
            return .drag(path: pathPoints.map { Coordinate(x: $0.x, y: $0.y) })

        case "wait":
            return .wait(durationMs: ms)

        case "cursor_position":
            return .cursorPosition

        default:
            return nil
        }
    }
}

// MARK: - Internal Encoding Helpers

/// Internal payload for encoding OpenAI computer_call arguments through the ToolCallResult pipeline.
struct ComputerUseOpenAIPayload: Codable {
    let actionType: String
    let x: Int?
    let y: Int?
    let button: String?
    let text: String?
    let keys: [String]?
    let scrollX: Int?
    let scrollY: Int?
    let path: [[String: Int]]?
    let ms: Int?
    let safetyChecks: [[String: String]]?
    let callId: String?
    /// The original response item ID (e.g. "cu_...") needed for multi-turn re-serialization
    let responseItemId: String?
}
