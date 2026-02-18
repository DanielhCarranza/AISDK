//
//  BuiltInToolTests.swift
//  AISDKTests
//
//  Tests for core BuiltInTool types and AITextRequest integration
//

import XCTest
@testable import AISDK

final class BuiltInToolTests: XCTestCase {

    func testWebSearchDefaultCreation() {
        let tool = BuiltInTool.webSearchDefault
        XCTAssertEqual(tool.kind, "webSearch")
    }

    func testWebSearchWithConfig() {
        let location = BuiltInTool.UserLocation(city: "Austin", region: "TX", country: "US", timezone: "America/Chicago")
        let config = BuiltInTool.WebSearchConfig(
            maxUses: 2,
            searchContextSize: "high",
            allowedDomains: ["example.com"],
            blockedDomains: ["ads.example.com"],
            userLocation: location
        )
        let tool = BuiltInTool.webSearch(config)

        if case .webSearch(let value) = tool {
            XCTAssertEqual(value, config)
        } else {
            XCTFail("Expected webSearch with config")
        }
    }

    func testCodeExecutionDefault() {
        let tool = BuiltInTool.codeExecutionDefault
        XCTAssertEqual(tool.kind, "codeExecution")
    }

    func testCodeExecutionWithConfig() {
        let config = BuiltInTool.CodeExecutionConfig(containerId: "container-1", fileIds: ["file-1"])
        let tool = BuiltInTool.codeExecution(config)

        if case .codeExecution(let value) = tool {
            XCTAssertEqual(value, config)
        } else {
            XCTFail("Expected codeExecution with config")
        }
    }

    func testFileSearchRequiresConfig() {
        let config = BuiltInTool.FileSearchConfig(vectorStoreIds: ["vs_123"], maxNumResults: 5, scoreThreshold: 0.75)
        let tool = BuiltInTool.fileSearch(config)

        if case .fileSearch(let value) = tool {
            XCTAssertEqual(value.vectorStoreIds, ["vs_123"])
            XCTAssertEqual(value.maxNumResults, 5)
            XCTAssertEqual(value.scoreThreshold, 0.75)
        } else {
            XCTFail("Expected fileSearch with config")
        }
    }

    func testImageGenerationDefault() {
        let tool = BuiltInTool.imageGenerationDefault
        XCTAssertEqual(tool.kind, "imageGeneration")
    }

    func testImageGenerationWithConfig() {
        let config = BuiltInTool.ImageGenerationConfig(quality: "high", size: "1024x1024", background: "transparent", outputFormat: "png", partialImages: 2)
        let tool = BuiltInTool.imageGeneration(config)

        if case .imageGeneration(let value) = tool {
            XCTAssertEqual(value, config)
        } else {
            XCTFail("Expected imageGeneration with config")
        }
    }

    func testUrlContext() {
        let tool = BuiltInTool.urlContext
        XCTAssertEqual(tool.kind, "urlContext")
    }

    func testKindDeduplication() {
        let tools: [BuiltInTool] = [
            .webSearchDefault,
            .webSearch(BuiltInTool.WebSearchConfig())
        ]
        let kinds = Set(tools.map { $0.kind })
        XCTAssertEqual(kinds.count, 1)
    }

    func testHashable() {
        let tools: Set<BuiltInTool> = [
            .webSearchDefault,
            .webSearch(BuiltInTool.WebSearchConfig())
        ]
        XCTAssertEqual(tools.count, 2)
    }

    func testAITextRequestWithBuiltInTools() {
        let request = AITextRequest(
            messages: [.user("Hello")],
            builtInTools: [.webSearchDefault, .codeExecutionDefault]
        )
        XCTAssertEqual(request.builtInTools?.count, 2)
    }

    func testWithBuiltInToolsCopyMethod() {
        let request = AITextRequest(messages: [.user("Hello")])
        let updated = request.withBuiltInTools([.codeExecutionDefault])
        XCTAssertEqual(updated.builtInTools?.first?.kind, "codeExecution")
    }

    func testBuiltInToolsDefaultNil() {
        let request = AITextRequest(messages: [.user("Hello")])
        XCTAssertNil(request.builtInTools)
    }

    func testWebSearchConfigCodable() throws {
        let config = BuiltInTool.WebSearchConfig(
            maxUses: 2,
            searchContextSize: "medium",
            allowedDomains: ["example.com"],
            blockedDomains: ["ads.example.com"],
            userLocation: BuiltInTool.UserLocation(city: "Austin", region: "TX", country: "US", timezone: "America/Chicago")
        )
        let decoded = try roundTrip(config)
        XCTAssertEqual(decoded, config)
    }

    func testUserLocationCodable() throws {
        let location = BuiltInTool.UserLocation(city: "Paris", region: "IDF", country: "FR", timezone: "Europe/Paris")
        let decoded = try roundTrip(location)
        XCTAssertEqual(decoded, location)
    }

    func testCodeExecutionConfigCodable() throws {
        let config = BuiltInTool.CodeExecutionConfig(containerId: "c1", fileIds: ["f1", "f2"])
        let decoded = try roundTrip(config)
        XCTAssertEqual(decoded, config)
    }

    func testFileSearchConfigCodable() throws {
        let config = BuiltInTool.FileSearchConfig(vectorStoreIds: ["vs1", "vs2"], maxNumResults: 4, scoreThreshold: 0.6)
        let decoded = try roundTrip(config)
        XCTAssertEqual(decoded, config)
    }

    func testImageGenerationConfigCodable() throws {
        let config = BuiltInTool.ImageGenerationConfig(quality: "low", size: "auto", background: "opaque", outputFormat: "webp", partialImages: 1)
        let decoded = try roundTrip(config)
        XCTAssertEqual(decoded, config)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
