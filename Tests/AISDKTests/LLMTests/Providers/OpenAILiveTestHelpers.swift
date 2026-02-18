//
//  OpenAILiveTestHelpers.swift
//  AISDKTests
//
//  Helpers for OpenAI real API tests
//

import XCTest
@testable import AISDK

public enum OpenAILiveTestHelpers {
    public static let defaultModel = "gpt-4o-mini"

    public static func shouldUseRealAPI() -> Bool {
        let useReal = ProcessInfo.processInfo.environment["USE_REAL_API"] == "true"
        let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        return useReal && !key.isEmpty
    }

    public static func requireAPIKey() throws -> String {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY not set")
        }
        return key
    }

    public static func skipIfUnavailable() throws {
        if !shouldUseRealAPI() {
            throw XCTSkip("Real API tests disabled. Set USE_REAL_API=true and OPENAI_API_KEY.")
        }
    }
}

public extension XCTestCase {
    func assertValidResponse(_ response: ResponseObject, file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(response.id.isEmpty, "Response ID should be present", file: file, line: line)
        XCTAssertTrue(response.status.isFinal || response.status.isProcessing, "Response should have a valid status", file: file, line: line)
    }

    func assertStreamHasContent(_ chunks: [ResponseChunk], file: StaticString = #file, line: UInt = #line) {
        let hasText = chunks.contains { $0.delta?.outputText?.isEmpty == false }
        XCTAssertTrue(hasText, "Stream should include text deltas", file: file, line: line)
    }
}
