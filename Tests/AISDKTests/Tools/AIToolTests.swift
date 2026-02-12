//
//  AIToolTests.swift
//  AISDKTests
//
//  Tests for the instance-based AITool protocol and registry.
//

import XCTest
@testable import AISDK

// MARK: - Test Tools

private struct EchoTool: AITool {
    let name = "echo"
    let description = "Echoes back the input message"

    @AIParameter(description: "LegacyMessage to echo")
    var message: String = ""

    init() {}

    func execute() async throws -> AIToolResult {
        AIToolResult(content: "Echo: \(message)")
    }
}

private struct MetadataTool: AITool {
    struct TestMetadata: ToolMetadata, Equatable {
        let computedValue: Int
        let timestamp: String
    }

    let name = "metadata_tool"
    let description = "Returns metadata with computed value"

    @AIParameter(description: "Input value")
    var value: Int = 0

    init() {}

    func execute() async throws -> AIToolResult {
        let metadata = TestMetadata(
            computedValue: value * 2,
            timestamp: "2024-01-01T00:00:00Z"
        )
        return AIToolResult(content: "Value: \(value)", metadata: metadata)
    }
}

private struct EnumTool: AITool {
    enum Unit: String, Codable, CaseIterable {
        case celsius
        case fahrenheit
    }

    let name = "enum_tool"
    let description = "Uses enum parameters"

    @AIParameter(description: "Temperature unit")
    var unit: Unit = .celsius

    init() {}

    func execute() async throws -> AIToolResult {
        AIToolResult(content: "Unit: \(unit.rawValue)")
    }
}

// MARK: - AIToolTests

final class AIToolTests: XCTestCase {

    func testAIToolResultContentOnly() {
        let result = AIToolResult(content: "Test content")
        XCTAssertEqual(result.content, "Test content")
        XCTAssertNil(result.metadata)
        XCTAssertNil(result.artifacts)
    }

    func testAIToolResultWithMetadata() {
        let metadata = MetadataTool.TestMetadata(computedValue: 42, timestamp: "now")
        let result = AIToolResult(content: "Test", metadata: metadata)
        XCTAssertEqual(result.content, "Test")
        XCTAssertEqual(result.metadata as? MetadataTool.TestMetadata, metadata)
    }

    func testSchemaGenerationFromAIParameter() {
        let schema = EchoTool.jsonSchema()
        XCTAssertEqual(schema.function?.name, "echo")
        XCTAssertNotNil(schema.function?.parameters.properties["message"])
    }

    func testEnumInferenceInSchema() {
        let schema = EnumTool.jsonSchema()
        let unitProperty = schema.function?.parameters.properties["unit"]
        XCTAssertEqual(unitProperty?.enumValues, ["celsius", "fahrenheit"])
    }

    func testRegistryExecuteByName() async throws {
        let registry = AIToolRegistry()
        registry.register(EchoTool.self)

        let result = try await registry.execute(
            name: "echo",
            arguments: #"{"message": "Hello"}"#
        )

        XCTAssertEqual(result.content, "Echo: Hello")
    }

    func testRegistryExecuteDecodesSnakeCase() async throws {
        let registry = AIToolRegistry()
        registry.register(EchoTool.self)

        let result = try await registry.execute(
            name: "echo",
            arguments: #"{"message": "Snake"}"#
        )

        XCTAssertEqual(result.content, "Echo: Snake")
    }

    func testRegistryIsThreadSafe() async throws {
        let registry = AIToolRegistry()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    registry.register(EchoTool.self)
                    registry.register(MetadataTool.self)
                }
            }
        }

        XCTAssertEqual(registry.registeredNames.count, 2)
    }
}
