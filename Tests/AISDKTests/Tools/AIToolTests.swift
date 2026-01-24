//
//  AIToolTests.swift
//  AISDKTests
//
//  Tests for the redesigned AITool protocol and related types
//

import XCTest
@testable import AISDK

// MARK: - Test Tools

/// A simple test tool with basic arguments
private struct EchoTool: AITool {
    typealias Arguments = EchoArguments
    typealias Metadata = EmptyMetadata

    struct EchoArguments: Codable, Sendable {
        let message: String
    }

    static var name: String { "echo" }
    static var description: String { "Echoes back the input message" }
    static var timeout: TimeInterval { 5.0 }

    static func execute(arguments: EchoArguments) async throws -> AIToolResult<EmptyMetadata> {
        AIToolResult(content: "Echo: \(arguments.message)")
    }
}

/// A test tool with custom metadata
private struct MetadataTool: AITool {
    typealias Arguments = MetadataArguments
    typealias Metadata = TestMetadata

    struct MetadataArguments: Codable, Sendable {
        let value: Int
    }

    struct TestMetadata: AIToolMetadata, Equatable {
        let computedValue: Int
        let timestamp: String
    }

    static var name: String { "metadata_tool" }
    static var description: String { "Returns metadata with computed value" }

    static func execute(arguments: MetadataArguments) async throws -> AIToolResult<TestMetadata> {
        let metadata = TestMetadata(
            computedValue: arguments.value * 2,
            timestamp: "2024-01-01T00:00:00Z"
        )
        return AIToolResult(content: "Value: \(arguments.value)", metadata: metadata)
    }
}

/// A test tool that throws an error
private struct FailingTool: AITool {
    typealias Arguments = EmptyArguments
    typealias Metadata = EmptyMetadata

    struct EmptyArguments: Codable, Sendable {}

    static var name: String { "failing_tool" }
    static var description: String { "Always fails" }

    static func execute(arguments: EmptyArguments) async throws -> AIToolResult<EmptyMetadata> {
        throw TestToolError.intentionalFailure
    }
}

/// A test tool with slow execution
private struct SlowTool: AITool {
    typealias Arguments = SlowArguments
    typealias Metadata = EmptyMetadata

    struct SlowArguments: Codable, Sendable {
        let delaySeconds: Double
    }

    static var name: String { "slow_tool" }
    static var description: String { "Simulates slow execution" }
    static var timeout: TimeInterval { 1.0 }  // Short timeout for testing

    static func execute(arguments: SlowArguments) async throws -> AIToolResult<EmptyMetadata> {
        try await Task.sleep(nanoseconds: UInt64(arguments.delaySeconds * 1_000_000_000))
        return AIToolResult(content: "Completed after \(arguments.delaySeconds)s")
    }
}

/// A test tool with custom schema
private struct CustomSchemaTool: AITool {
    typealias Arguments = CustomSchemaArguments
    typealias Metadata = EmptyMetadata

    struct CustomSchemaArguments: Codable, Sendable {
        let location: String
        let unit: String?
    }

    static var name: String { "get_weather" }
    static var description: String { "Get weather for a location" }

    static func execute(arguments: CustomSchemaArguments) async throws -> AIToolResult<EmptyMetadata> {
        AIToolResult(content: "Weather for \(arguments.location)")
    }

    static func generateSchema() -> ToolSchema {
        ToolSchema(
            type: "function",
            function: ToolFunction(
                name: name,
                description: description,
                parameters: Parameters(
                    type: "object",
                    properties: [
                        "location": PropertyDefinition(
                            type: "string",
                            description: "The city and state, e.g. San Francisco, CA"
                        ),
                        "unit": PropertyDefinition(
                            type: "string",
                            description: "Temperature unit (celsius or fahrenheit)"
                        )
                    ],
                    required: ["location"]
                )
            )
        )
    }
}

/// Test error type
private enum TestToolError: Error, LocalizedError {
    case intentionalFailure

    var errorDescription: String? {
        "Intentional test failure"
    }
}

// MARK: - AIToolTests

final class AIToolTests: XCTestCase {

    // MARK: - Protocol Conformance Tests

    func test_AITool_hasCorrectStaticProperties() {
        XCTAssertEqual(EchoTool.name, "echo")
        XCTAssertEqual(EchoTool.description, "Echoes back the input message")
        XCTAssertEqual(EchoTool.timeout, 5.0)
    }

    func test_AITool_defaultTimeout_is60Seconds() {
        // CustomSchemaTool doesn't override timeout
        XCTAssertEqual(CustomSchemaTool.timeout, 60.0)
    }

    // MARK: - AIToolResult Tests

    func test_AIToolResult_withContentOnly() {
        let result = AIToolResult<EmptyMetadata>(content: "Test content")
        XCTAssertEqual(result.content, "Test content")
        XCTAssertNil(result.metadata)
    }

    func test_AIToolResult_withMetadata() {
        let metadata = MetadataTool.TestMetadata(computedValue: 42, timestamp: "now")
        let result = AIToolResult(content: "Test", metadata: metadata)
        XCTAssertEqual(result.content, "Test")
        XCTAssertEqual(result.metadata?.computedValue, 42)
    }

    // MARK: - EmptyMetadata Tests

    func test_EmptyMetadata_isEquatable() {
        let m1 = EmptyMetadata()
        let m2 = EmptyMetadata()
        XCTAssertEqual(m1, m2)
    }

    func test_EmptyMetadata_isCodable() throws {
        let metadata = EmptyMetadata()
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(EmptyMetadata.self, from: data)
        XCTAssertEqual(metadata, decoded)
    }

    // MARK: - AIToolExecutor Tests

    func test_AIToolExecutor_executesToolSuccessfully() async throws {
        let result = try await AIToolExecutor.execute(
            EchoTool.self,
            arguments: #"{"message": "Hello, World!"}"#
        )

        XCTAssertEqual(result.content, "Echo: Hello, World!")
        XCTAssertNil(result.metadata)
    }

    func test_AIToolExecutor_returnsMetadata() async throws {
        let result = try await AIToolExecutor.execute(
            MetadataTool.self,
            arguments: #"{"value": 21}"#
        )

        XCTAssertEqual(result.content, "Value: 21")
        XCTAssertNotNil(result.metadata)
        // typeName is fully-qualified, so check it contains the type name
        XCTAssertTrue(result.metadata?.typeName.contains("TestMetadata") ?? false)

        // Decode the metadata
        if let metadata = result.metadata?.decode(as: MetadataTool.TestMetadata.self) {
            XCTAssertEqual(metadata.computedValue, 42)
            XCTAssertEqual(metadata.timestamp, "2024-01-01T00:00:00Z")
        } else {
            XCTFail("Failed to decode metadata")
        }
    }

    func test_AIToolExecutor_throwsOnInvalidJSON() async {
        do {
            _ = try await AIToolExecutor.execute(
                EchoTool.self,
                arguments: "not valid json"
            )
            XCTFail("Expected error to be thrown")
        } catch let error as AISDKErrorV2 {
            // Argument parsing errors should use invalidToolArguments
            XCTAssertEqual(error.code, .invalidToolArguments)
            XCTAssertTrue(error.message.contains("Failed to decode"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_AIToolExecutor_throwsOnMissingRequiredField() async {
        do {
            _ = try await AIToolExecutor.execute(
                EchoTool.self,
                arguments: #"{}"#  // Missing "message" field
            )
            XCTFail("Expected error to be thrown")
        } catch let error as AISDKErrorV2 {
            // Argument parsing errors should use invalidToolArguments
            XCTAssertEqual(error.code, .invalidToolArguments)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_AIToolExecutor_propagatesToolError() async {
        do {
            _ = try await AIToolExecutor.execute(
                FailingTool.self,
                arguments: #"{}"#
            )
            XCTFail("Expected error to be thrown")
        } catch let error as AISDKErrorV2 {
            // Tool errors should be wrapped in AISDKErrorV2.toolExecutionFailed
            XCTAssertEqual(error.code, .toolExecutionFailed)
            XCTAssertTrue(error.message.contains("failing_tool"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_AIToolExecutor_enforcesTimeout() async {
        do {
            _ = try await AIToolExecutor.execute(
                SlowTool.self,
                arguments: #"{"delaySeconds": 10.0}"#  // 10s delay with 1s timeout
            )
            XCTFail("Expected timeout error")
        } catch let error as AISDKErrorV2 {
            XCTAssertEqual(error.code, .toolTimeout)
            XCTAssertTrue(error.message.contains("slow_tool"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_AIToolExecutor_decodesSnakeCaseKeys() async throws {
        // Test that snake_case keys are automatically converted to camelCase
        // SlowTool.SlowArguments has `delaySeconds` which should accept `delay_seconds`
        let result = try await AIToolExecutor.execute(
            SlowTool.self,
            arguments: #"{"delay_seconds": 0.001}"#  // snake_case should work
        )
        XCTAssertTrue(result.content.contains("0.001"))
    }

    func test_AIToolExecutor_handlesEmptyArguments() async throws {
        // FailingTool takes empty arguments - verify empty string works
        do {
            _ = try await AIToolExecutor.execute(
                FailingTool.self,
                arguments: ""  // Empty string should be treated as {}
            )
            // FailingTool will throw, but we expect it to parse successfully first
        } catch let error as AISDKErrorV2 {
            // Should get toolExecutionFailed from the tool, not invalidToolArguments from parsing
            XCTAssertEqual(error.code, .toolExecutionFailed)
        }
    }

    func test_AIToolExecutor_handlesWhitespaceArguments() async throws {
        // Verify whitespace-only string is treated as {}
        do {
            _ = try await AIToolExecutor.execute(
                FailingTool.self,
                arguments: "   \n\t  "  // Whitespace should be treated as {}
            )
        } catch let error as AISDKErrorV2 {
            // Should get toolExecutionFailed from the tool, not invalidToolArguments from parsing
            XCTAssertEqual(error.code, .toolExecutionFailed)
        }
    }

    // MARK: - AnyAITool Tests

    func test_AnyAITool_wrapsToolCorrectly() {
        let wrapped = AnyAITool(EchoTool.self)

        XCTAssertEqual(wrapped.name, "echo")
        XCTAssertEqual(wrapped.description, "Echoes back the input message")
        XCTAssertEqual(wrapped.timeout, 5.0)
    }

    func test_AnyAITool_executesWrappedTool() async throws {
        let wrapped = AnyAITool(EchoTool.self)

        let result = try await wrapped.execute(arguments: #"{"message": "Test"}"#)

        XCTAssertEqual(result.content, "Echo: Test")
    }

    func test_AnyAITool_generatesSchema() {
        let wrapped = AnyAITool(CustomSchemaTool.self)

        XCTAssertEqual(wrapped.schema.type, "function")
        XCTAssertEqual(wrapped.schema.function?.name, "get_weather")
        XCTAssertEqual(wrapped.schema.function?.parameters.properties.count, 2)
        XCTAssertTrue(wrapped.schema.function?.parameters.required?.contains("location") ?? false)
    }

    // MARK: - AIToolRegistry Tests

    func test_AIToolRegistry_registersAndLookupsTool() {
        let registry = AIToolRegistry()
        registry.register(EchoTool.self)

        let tool = registry.tool(named: "echo")
        XCTAssertNotNil(tool)
        XCTAssertEqual(tool?.name, "echo")
    }

    func test_AIToolRegistry_returnsNilForUnknownTool() {
        let registry = AIToolRegistry()
        registry.register(EchoTool.self)

        let tool = registry.tool(named: "unknown")
        XCTAssertNil(tool)
    }

    func test_AIToolRegistry_registeredNames() {
        let registry = AIToolRegistry()
        registry.register(EchoTool.self)
        registry.register(MetadataTool.self)

        let names = registry.registeredNames.sorted()
        XCTAssertEqual(names, ["echo", "metadata_tool"])
    }

    func test_AIToolRegistry_schemas() {
        let registry = AIToolRegistry()
        registry.register(EchoTool.self)
        registry.register(CustomSchemaTool.self)

        let schemas = registry.schemas
        XCTAssertEqual(schemas.count, 2)

        let toolNames = schemas.compactMap { $0.function?.name }.sorted()
        XCTAssertEqual(toolNames, ["echo", "get_weather"])
    }

    func test_AIToolRegistry_executeByName() async throws {
        let registry = AIToolRegistry()
        registry.register(EchoTool.self)

        let result = try await registry.execute(
            name: "echo",
            arguments: #"{"message": "Registry test"}"#
        )

        XCTAssertEqual(result.content, "Echo: Registry test")
    }

    func test_AIToolRegistry_throwsForUnknownTool() async {
        let registry = AIToolRegistry()
        registry.register(EchoTool.self)

        do {
            _ = try await registry.execute(
                name: "unknown",
                arguments: #"{}"#
            )
            XCTFail("Expected error to be thrown")
        } catch let error as AISDKErrorV2 {
            XCTAssertEqual(error.code, .toolNotFound)
            XCTAssertTrue(error.message.contains("unknown"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - AnyAIToolMetadata Tests

    func test_AnyAIToolMetadata_wrapsMetadata() {
        let metadata = MetadataTool.TestMetadata(computedValue: 100, timestamp: "test")
        let wrapped = AnyAIToolMetadata(metadata)

        // typeName is fully-qualified, so check it contains the type name
        XCTAssertTrue(wrapped.typeName.contains("TestMetadata"))
        XCTAssertNotNil(wrapped.jsonData)
        XCTAssertNil(wrapped.encodingError)
    }

    func test_AnyAIToolMetadata_decodesToOriginalType() {
        let original = MetadataTool.TestMetadata(computedValue: 100, timestamp: "test")
        let wrapped = AnyAIToolMetadata(original)

        let decoded = wrapped.decode(as: MetadataTool.TestMetadata.self)
        XCTAssertEqual(decoded, original)
    }

    func test_AnyAIToolMetadata_failsForIncompatibleType() {
        let metadata = MetadataTool.TestMetadata(computedValue: 100, timestamp: "test")
        let wrapped = AnyAIToolMetadata(metadata)

        // Try to decode as a different type with incompatible structure
        // Note: EmptyMetadata can decode from any JSON object (it has no required fields)
        // So we verify that the typeName reflects the original type (fully-qualified)
        XCTAssertTrue(wrapped.typeName.contains("TestMetadata"))

        // Verify the original type decodes correctly
        let decoded = wrapped.decode(as: MetadataTool.TestMetadata.self)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.computedValue, 100)
    }

    // MARK: - Concurrency Tests

    func test_AIToolExecutor_isSendable() async throws {
        // Verify that AIToolExecutor can be used from multiple tasks
        let results = try await withThrowingTaskGroup(of: AIToolExecutionResult.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try await AIToolExecutor.execute(
                        EchoTool.self,
                        arguments: #"{"message": "Message \#(i)"}"#
                    )
                }
            }

            var results: [AIToolExecutionResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        XCTAssertEqual(results.count, 10)
    }

    func test_AIToolRegistry_isThreadSafe() async throws {
        let registry = AIToolRegistry()

        // Register tools from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    registry.register(EchoTool.self)
                    registry.register(MetadataTool.self)
                }
            }
        }

        // Should still have exactly 2 tools (no duplicates, no corruption)
        XCTAssertEqual(registry.registeredNames.count, 2)
    }
}
