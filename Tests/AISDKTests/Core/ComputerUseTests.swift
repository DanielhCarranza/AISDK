//
//  ComputerUseTests.swift
//  AISDKTests
//
//  Tests for ComputerUse core types: config, action parsing, result encoding
//

import XCTest
@testable import AISDK

final class ComputerUseTests: XCTestCase {

    // MARK: - ComputerUseConfig Tests

    func testComputerUseConfigCreation() {
        let config = BuiltInTool.ComputerUseConfig(
            displayWidth: 1920,
            displayHeight: 1080,
            environment: .mac
        )
        XCTAssertEqual(config.displayWidth, 1920)
        XCTAssertEqual(config.displayHeight, 1080)
        XCTAssertEqual(config.environment, .mac)
        XCTAssertNil(config.displayNumber)
        XCTAssertNil(config.enableZoom)
    }

    func testComputerUseConfigDefaults() {
        let config = BuiltInTool.ComputerUseConfig()
        XCTAssertEqual(config.displayWidth, 1024)
        XCTAssertEqual(config.displayHeight, 768)
        XCTAssertNil(config.environment)
    }

    func testComputerUseConfigCodable() throws {
        let config = BuiltInTool.ComputerUseConfig(
            displayWidth: 1280,
            displayHeight: 720,
            environment: .browser,
            displayNumber: 1,
            enableZoom: true
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(BuiltInTool.ComputerUseConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testComputerUseEnvironmentCodable() throws {
        let environments: [BuiltInTool.ComputerUseEnvironment] = [.browser, .mac, .windows, .ubuntu, .linux]
        for env in environments {
            let data = try JSONEncoder().encode(env)
            let decoded = try JSONDecoder().decode(BuiltInTool.ComputerUseEnvironment.self, from: data)
            XCTAssertEqual(decoded, env)
        }
    }

    func testBuiltInToolComputerUseKind() {
        let tool = BuiltInTool.computerUse(BuiltInTool.ComputerUseConfig())
        XCTAssertEqual(tool.kind, "computerUse")
    }

    func testBuiltInToolComputerUseDefaultKind() {
        let tool = BuiltInTool.computerUseDefault
        XCTAssertEqual(tool.kind, "computerUse")
    }

    func testBuiltInToolComputerUseConfig() {
        let config = BuiltInTool.ComputerUseConfig(displayWidth: 1920, displayHeight: 1080)
        let tool = BuiltInTool.computerUse(config)

        if case .computerUse(let value) = tool {
            XCTAssertEqual(value, config)
        } else {
            XCTFail("Expected computerUse with config")
        }
    }

    // MARK: - ComputerUseAction Anthropic Parsing

    func testFromAnthropicScreenshot() {
        let action = ComputerUseAction.fromAnthropic(["action": "screenshot"])
        XCTAssertEqual(action, .screenshot)
    }

    func testFromAnthropicLeftClick() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "left_click",
            "coordinate": [100, 200]
        ])
        XCTAssertEqual(action, .click(x: 100, y: 200, button: .left))
    }

    func testFromAnthropicRightClick() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "right_click",
            "coordinate": [50, 75]
        ])
        XCTAssertEqual(action, .click(x: 50, y: 75, button: .right))
    }

    func testFromAnthropicMiddleClick() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "middle_click",
            "coordinate": [50, 75]
        ])
        XCTAssertEqual(action, .click(x: 50, y: 75, button: .middle))
    }

    func testFromAnthropicDoubleClick() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "double_click",
            "coordinate": [300, 400]
        ])
        XCTAssertEqual(action, .doubleClick(x: 300, y: 400))
    }

    func testFromAnthropicTripleClick() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "triple_click",
            "coordinate": [10, 20]
        ])
        XCTAssertEqual(action, .tripleClick(x: 10, y: 20))
    }

    func testFromAnthropicType() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "type",
            "text": "Hello world"
        ])
        XCTAssertEqual(action, .type(text: "Hello world"))
    }

    func testFromAnthropicKeypress() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "key",
            "text": "ctrl+c"
        ])
        XCTAssertEqual(action, .keypress(keys: ["ctrl", "c"]))
    }

    func testFromAnthropicScroll() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "scroll",
            "coordinate": [500, 500],
            "direction": "down",
            "amount": 3
        ])
        XCTAssertEqual(action, .scroll(x: 500, y: 500, direction: .down, amount: 3))
    }

    func testFromAnthropicMouseMove() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "mouse_move",
            "coordinate": [800, 600]
        ])
        XCTAssertEqual(action, .move(x: 800, y: 600))
    }

    func testFromAnthropicDrag() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "left_click_drag",
            "start_coordinate": [100, 100],
            "coordinate": [200, 200]
        ])
        XCTAssertEqual(action, .drag(path: [
            ComputerUseAction.Coordinate(x: 100, y: 100),
            ComputerUseAction.Coordinate(x: 200, y: 200)
        ]))
    }

    func testFromAnthropicWait() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "wait",
            "duration": 1000
        ])
        XCTAssertEqual(action, .wait(durationMs: 1000))
    }

    func testFromAnthropicCursorPosition() {
        let action = ComputerUseAction.fromAnthropic(["action": "cursor_position"])
        XCTAssertEqual(action, .cursorPosition)
    }

    func testFromAnthropicZoom() {
        let action = ComputerUseAction.fromAnthropic([
            "action": "zoom",
            "region": [0, 0, 500, 500]
        ])
        XCTAssertEqual(action, .zoom(region: [0, 0, 500, 500]))
    }

    func testFromAnthropicUnknownAction() {
        let action = ComputerUseAction.fromAnthropic(["action": "fly"])
        XCTAssertNil(action)
    }

    func testFromAnthropicMissingAction() {
        let action = ComputerUseAction.fromAnthropic(["coordinate": [1, 2]])
        XCTAssertNil(action)
    }

    func testFromAnthropicMissingCoordinate() {
        let action = ComputerUseAction.fromAnthropic(["action": "left_click"])
        XCTAssertNil(action)
    }

    // MARK: - ComputerUseAction OpenAI Parsing

    func testFromOpenAIScreenshot() {
        let action = ComputerUseAction.fromOpenAI(
            type: "screenshot", x: nil, y: nil, button: nil,
            text: nil, keys: nil, scrollX: nil, scrollY: nil,
            path: nil, ms: nil
        )
        XCTAssertEqual(action, .screenshot)
    }

    func testFromOpenAIClick() {
        let action = ComputerUseAction.fromOpenAI(
            type: "click", x: 150, y: 250, button: "left",
            text: nil, keys: nil, scrollX: nil, scrollY: nil,
            path: nil, ms: nil
        )
        XCTAssertEqual(action, .click(x: 150, y: 250, button: .left))
    }

    func testFromOpenAIClickRightButton() {
        let action = ComputerUseAction.fromOpenAI(
            type: "click", x: 150, y: 250, button: "right",
            text: nil, keys: nil, scrollX: nil, scrollY: nil,
            path: nil, ms: nil
        )
        XCTAssertEqual(action, .click(x: 150, y: 250, button: .right))
    }

    func testFromOpenAIDoubleClick() {
        let action = ComputerUseAction.fromOpenAI(
            type: "double_click", x: 100, y: 200, button: nil,
            text: nil, keys: nil, scrollX: nil, scrollY: nil,
            path: nil, ms: nil
        )
        XCTAssertEqual(action, .doubleClick(x: 100, y: 200))
    }

    func testFromOpenAIType() {
        let action = ComputerUseAction.fromOpenAI(
            type: "type", x: nil, y: nil, button: nil,
            text: "test input", keys: nil, scrollX: nil, scrollY: nil,
            path: nil, ms: nil
        )
        XCTAssertEqual(action, .type(text: "test input"))
    }

    func testFromOpenAIKeypress() {
        let action = ComputerUseAction.fromOpenAI(
            type: "keypress", x: nil, y: nil, button: nil,
            text: nil, keys: ["Enter", "Tab"], scrollX: nil, scrollY: nil,
            path: nil, ms: nil
        )
        XCTAssertEqual(action, .keypress(keys: ["Enter", "Tab"]))
    }

    func testFromOpenAIScroll() {
        let action = ComputerUseAction.fromOpenAI(
            type: "scroll", x: 400, y: 300, button: nil,
            text: nil, keys: nil, scrollX: 0, scrollY: -3,
            path: nil, ms: nil
        )
        XCTAssertEqual(action, .scroll(x: 400, y: 300, scrollX: 0, scrollY: -3))
    }

    func testFromOpenAIMove() {
        let action = ComputerUseAction.fromOpenAI(
            type: "move", x: 600, y: 400, button: nil,
            text: nil, keys: nil, scrollX: nil, scrollY: nil,
            path: nil, ms: nil
        )
        XCTAssertEqual(action, .move(x: 600, y: 400))
    }

    func testFromOpenAIDrag() {
        let action = ComputerUseAction.fromOpenAI(
            type: "drag", x: nil, y: nil, button: nil,
            text: nil, keys: nil, scrollX: nil, scrollY: nil,
            path: [(x: 10, y: 10), (x: 50, y: 50), (x: 100, y: 100)],
            ms: nil
        )
        XCTAssertEqual(action, .drag(path: [
            ComputerUseAction.Coordinate(x: 10, y: 10),
            ComputerUseAction.Coordinate(x: 50, y: 50),
            ComputerUseAction.Coordinate(x: 100, y: 100)
        ]))
    }

    func testFromOpenAIWait() {
        let action = ComputerUseAction.fromOpenAI(
            type: "wait", x: nil, y: nil, button: nil,
            text: nil, keys: nil, scrollX: nil, scrollY: nil,
            path: nil, ms: 2000
        )
        XCTAssertEqual(action, .wait(durationMs: 2000))
    }

    func testFromOpenAICursorPosition() {
        let action = ComputerUseAction.fromOpenAI(
            type: "cursor_position", x: nil, y: nil, button: nil,
            text: nil, keys: nil, scrollX: nil, scrollY: nil,
            path: nil, ms: nil
        )
        XCTAssertEqual(action, .cursorPosition)
    }

    func testFromOpenAIUnknownType() {
        let action = ComputerUseAction.fromOpenAI(
            type: "teleport", x: nil, y: nil, button: nil,
            text: nil, keys: nil, scrollX: nil, scrollY: nil,
            path: nil, ms: nil
        )
        XCTAssertNil(action)
    }

    // MARK: - ComputerUseToolCall Tests

    func testComputerUseToolCallCreation() {
        let call = ComputerUseToolCall(
            id: "call_123",
            callId: "cid_456",
            action: .screenshot,
            safetyChecks: [
                ComputerUseAction.SafetyCheck(id: "sc_1", code: "malicious_url", message: "URL detected")
            ]
        )
        XCTAssertEqual(call.id, "call_123")
        XCTAssertEqual(call.callId, "cid_456")
        XCTAssertEqual(call.action, .screenshot)
        XCTAssertEqual(call.safetyChecks.count, 1)
        XCTAssertEqual(call.safetyChecks[0].code, "malicious_url")
    }

    func testComputerUseToolCallDefaults() {
        let call = ComputerUseToolCall(id: "call_1", action: .screenshot)
        XCTAssertNil(call.callId)
        XCTAssertTrue(call.safetyChecks.isEmpty)
    }

    // MARK: - ComputerUseResult Tests

    func testComputerUseResultScreenshot() {
        let result = ComputerUseResult.screenshot("base64data", mediaType: .png)
        XCTAssertEqual(result.screenshot, "base64data")
        XCTAssertEqual(result.mediaType, .png)
        XCTAssertNil(result.text)
        XCTAssertFalse(result.isError)
    }

    func testComputerUseResultError() {
        let result = ComputerUseResult.error("Something went wrong")
        XCTAssertNil(result.screenshot)
        XCTAssertEqual(result.text, "Something went wrong")
        XCTAssertTrue(result.isError)
    }

    func testComputerUseResultFullInit() {
        let result = ComputerUseResult(
            screenshot: "base64",
            mediaType: .jpeg,
            text: "Cursor at (100, 200)",
            isError: false
        )
        XCTAssertEqual(result.screenshot, "base64")
        XCTAssertEqual(result.mediaType, .jpeg)
        XCTAssertEqual(result.text, "Cursor at (100, 200)")
        XCTAssertFalse(result.isError)
    }

    func testImageMediaTypeRawValues() {
        XCTAssertEqual(ComputerUseResult.ImageMediaType.png.rawValue, "image/png")
        XCTAssertEqual(ComputerUseResult.ImageMediaType.jpeg.rawValue, "image/jpeg")
        XCTAssertEqual(ComputerUseResult.ImageMediaType.gif.rawValue, "image/gif")
        XCTAssertEqual(ComputerUseResult.ImageMediaType.webp.rawValue, "image/webp")
    }

    // MARK: - ComputerUseResultPayload Encoding

    func testComputerUseResultPayloadRoundTrip() throws {
        let payload = ComputerUseResultPayload(
            type: "__computer_use_result__",
            screenshot: "base64screenshot",
            mediaType: "image/png",
            text: nil,
            isError: false,
            callId: "call_123"
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ComputerUseResultPayload.self, from: data)
        XCTAssertEqual(decoded.type, "__computer_use_result__")
        XCTAssertEqual(decoded.screenshot, "base64screenshot")
        XCTAssertEqual(decoded.mediaType, "image/png")
        XCTAssertNil(decoded.text)
        XCTAssertFalse(decoded.isError)
        XCTAssertEqual(decoded.callId, "call_123")
    }

    // MARK: - ComputerUseOpenAIPayload Encoding

    func testComputerUseOpenAIPayloadRoundTrip() throws {
        let payload = ComputerUseOpenAIPayload(
            actionType: "click",
            x: 100, y: 200,
            button: "left",
            text: nil, keys: nil,
            scrollX: nil, scrollY: nil,
            path: nil, ms: nil,
            safetyChecks: [["id": "sc_1", "code": "warn", "message": "test"]],
            callId: "cid_789"
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ComputerUseOpenAIPayload.self, from: data)
        XCTAssertEqual(decoded.actionType, "click")
        XCTAssertEqual(decoded.x, 100)
        XCTAssertEqual(decoded.y, 200)
        XCTAssertEqual(decoded.button, "left")
        XCTAssertEqual(decoded.callId, "cid_789")
        XCTAssertEqual(decoded.safetyChecks?.first?["id"], "sc_1")
    }

    // MARK: - AIStreamEvent Computer Use

    func testStreamEventComputerUseAction() {
        let call = ComputerUseToolCall(id: "call_1", action: .click(x: 10, y: 20))
        let event = AIStreamEvent.computerUseAction(call)

        if case .computerUseAction(let received) = event {
            XCTAssertEqual(received.id, "call_1")
            XCTAssertEqual(received.action, .click(x: 10, y: 20, button: .left))
        } else {
            XCTFail("Expected computerUseAction event")
        }
    }

    func testStreamEventComputerUseEventType() {
        let call = ComputerUseToolCall(id: "call_1", action: .screenshot)
        let event = AIStreamEvent.computerUseAction(call)
        XCTAssertEqual(event.eventType, "computerUseAction")
    }

    // MARK: - AgentError Computer Use

    func testAgentErrorComputerUseHandlerNotConfigured() {
        let error = AgentError.computerUseHandlerNotConfigured
        XCTAssertTrue(error.localizedDescription.contains("computerUseHandler"))
    }
}
