//
//  UIToolTests.swift
//  AISDKTests
//
//  Tests for UITool protocol, UIToolPhase, and UIToolResultMetadata.
//

import XCTest
@testable import AISDK

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Test UITools

private struct SimpleUITool: UITool {
    let name = "simple_ui"
    let description = "A simple UI tool for testing"

    @Parameter(description: "Input value")
    var input: String = ""

    init() {}

    func execute() async throws -> ToolResult {
        ToolResult(content: "Result: \(input)")
    }

    var body: some View {
        Text("Simple: \(input)")
    }
}

private struct FailingUITool: UITool {
    struct ToolError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    let name = "failing_ui"
    let description = "A UI tool that fails"

    init() {}

    func execute() async throws -> ToolResult {
        throw ToolError(message: "Intentional failure")
    }

    var body: some View {
        Text("Should not render")
    }
}

// MARK: - UIToolPhase Tests

final class UIToolPhaseTests: XCTestCase {

    func testLoadingPhase() {
        let phase = UIToolPhase.loading
        if case .loading = phase {
            // Success
        } else {
            XCTFail("Expected loading phase")
        }
    }

    func testExecutingPhaseWithProgress() {
        let phase = UIToolPhase.executing(progress: 0.5)
        if case .executing(let progress) = phase {
            XCTAssertEqual(progress, 0.5)
        } else {
            XCTFail("Expected executing phase")
        }
    }

    func testExecutingPhaseWithNilProgress() {
        let phase = UIToolPhase.executing(progress: nil)
        if case .executing(let progress) = phase {
            XCTAssertNil(progress)
        } else {
            XCTFail("Expected executing phase")
        }
    }

    func testCompletePhase() {
        let result = ToolResult(content: "test result")
        let phase = UIToolPhase.complete(result: result)
        if case .complete(let r) = phase {
            XCTAssertEqual(r.content, "test result")
        } else {
            XCTFail("Expected complete phase")
        }
    }

    func testErrorPhase() {
        let error = NSError(domain: "test", code: 42)
        let phase = UIToolPhase.error(error)
        if case .error(let e) = phase {
            XCTAssertEqual((e as NSError).code, 42)
        } else {
            XCTFail("Expected error phase")
        }
    }
}

// MARK: - UIToolResultMetadata Tests

final class UIToolResultMetadataTests: XCTestCase {

    func testMetadataInitialization() {
        let metadata = UIToolResultMetadata(toolTypeName: "WeatherTool")
        XCTAssertEqual(metadata.toolTypeName, "WeatherTool")
        XCTAssertTrue(metadata.hasUIView)
    }

    func testMetadataWithoutUIView() {
        let metadata = UIToolResultMetadata(toolTypeName: "DataTool", hasUIView: false)
        XCTAssertEqual(metadata.toolTypeName, "DataTool")
        XCTAssertFalse(metadata.hasUIView)
    }

    func testMetadataCodable() throws {
        let original = UIToolResultMetadata(toolTypeName: "TestTool", hasUIView: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UIToolResultMetadata.self, from: data)
        XCTAssertEqual(decoded.toolTypeName, original.toolTypeName)
        XCTAssertEqual(decoded.hasUIView, original.hasUIView)
    }

    func testMetadataAttachedToToolResult() {
        let metadata = UIToolResultMetadata(toolTypeName: "ChartTool")
        let result = ToolResult(content: "chart data", metadata: metadata)
        XCTAssertNotNil(result.metadata)

        let uiMeta = result.metadata as? UIToolResultMetadata
        XCTAssertNotNil(uiMeta)
        XCTAssertEqual(uiMeta?.toolTypeName, "ChartTool")
        XCTAssertTrue(uiMeta?.hasUIView ?? false)
    }
}

// MARK: - UITool Protocol Tests

final class UIToolProtocolTests: XCTestCase {

    func testUIToolConformsToTool() {
        let tool: any Tool = SimpleUITool()
        XCTAssertEqual(tool.name, "simple_ui")
        XCTAssertEqual(tool.description, "A simple UI tool for testing")
    }

    func testUIToolDefaultToolResultIsNil() {
        let tool = SimpleUITool()
        XCTAssertNil(tool.toolResult)
    }

    func testUIToolExecution() async throws {
        var tool = SimpleUITool()
        _ = try tool.validateAndSetParameters(
            try JSONEncoder().encode(["input": "hello"])
        )
        let result = try await tool.execute()
        XCTAssertEqual(result.content, "Result: hello")
    }

    func testUIToolIsDetectable() {
        let tool: any Tool = SimpleUITool()
        XCTAssertTrue(tool is any UITool)
    }

    func testNonUIToolIsNotDetectable() {
        // Regular Tool should not be detected as UITool
        struct PlainTool: Tool {
            let name = "plain"
            let description = "plain tool"
            init() {}
            func execute() async throws -> ToolResult {
                ToolResult(content: "plain")
            }
        }
        let tool: any Tool = PlainTool()
        XCTAssertFalse(tool is any UITool)
    }

    func testFailingUIToolThrows() async {
        let tool = FailingUITool()
        do {
            _ = try await tool.execute()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Intentional failure"))
        }
    }

    func testUIToolSchemaGeneration() {
        let schema = SimpleUITool.jsonSchema()
        XCTAssertNotNil(schema)
    }
}

#endif
