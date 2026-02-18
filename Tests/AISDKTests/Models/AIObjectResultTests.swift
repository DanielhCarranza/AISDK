//
//  AIObjectResultTests.swift
//  AISDK
//
//  Tests for AIObjectResult
//

import Testing
@testable import AISDK

// MARK: - Test Models

struct TestPerson: Codable, Sendable, Equatable {
    let name: String
    let age: Int
}

struct TestAddress: Codable, Sendable, Equatable {
    let street: String
    let city: String
}

@Suite("AIObjectResult Tests")
struct AIObjectResultTests {
    // MARK: - Basic Initialization

    @Test("Creates result with minimal parameters")
    func testMinimalInit() {
        let person = TestPerson(name: "John", age: 30)
        let result = AIObjectResult(object: person)

        #expect(result.object == person)
        #expect(result.usage == .zero)
        #expect(result.finishReason == .stop)
        #expect(result.requestId == nil)
        #expect(result.model == nil)
        #expect(result.provider == nil)
        #expect(result.rawJSON == nil)
    }

    @Test("Creates result with all parameters")
    func testFullInit() {
        let person = TestPerson(name: "Jane", age: 25)
        let usage = AIUsage(promptTokens: 100, completionTokens: 50)

        let result = AIObjectResult(
            object: person,
            usage: usage,
            finishReason: .stop,
            requestId: "req-123",
            model: "gpt-4",
            provider: "openai",
            rawJSON: "{\"name\":\"Jane\",\"age\":25}"
        )

        #expect(result.object == person)
        #expect(result.usage.promptTokens == 100)
        #expect(result.usage.completionTokens == 50)
        #expect(result.finishReason == .stop)
        #expect(result.requestId == "req-123")
        #expect(result.model == "gpt-4")
        #expect(result.provider == "openai")
        #expect(result.rawJSON == "{\"name\":\"Jane\",\"age\":25}")
    }

    // MARK: - Helper Properties

    @Test("completedNormally checks finish reason")
    func testCompletedNormally() {
        let person = TestPerson(name: "Test", age: 20)

        let stopResult = AIObjectResult(object: person, finishReason: .stop)
        let lengthResult = AIObjectResult(object: person, finishReason: .length)
        let errorResult = AIObjectResult(object: person, finishReason: .error)

        #expect(stopResult.completedNormally == true)
        #expect(lengthResult.completedNormally == false)
        #expect(errorResult.completedNormally == false)
    }

    @Test("wasTruncated checks for length finish reason")
    func testWasTruncated() {
        let person = TestPerson(name: "Test", age: 20)

        let normalResult = AIObjectResult(object: person, finishReason: .stop)
        let truncatedResult = AIObjectResult(object: person, finishReason: .length)

        #expect(normalResult.wasTruncated == false)
        #expect(truncatedResult.wasTruncated == true)
    }

    @Test("totalTokens returns correct sum")
    func testTotalTokens() {
        let person = TestPerson(name: "Test", age: 20)
        let usage = AIUsage(promptTokens: 100, completionTokens: 50)
        let result = AIObjectResult(object: person, usage: usage)

        #expect(result.totalTokens == 150)
    }

    // MARK: - Map Transformation

    @Test("map transforms object to new type and clears rawJSON")
    func testMap() throws {
        let person = TestPerson(name: "John", age: 30)
        let usage = AIUsage(promptTokens: 10, completionTokens: 20)
        let originalResult = AIObjectResult(
            object: person,
            usage: usage,
            finishReason: .stop,
            requestId: "req-123",
            model: "gpt-4",
            provider: "openai",
            rawJSON: "{\"name\":\"John\",\"age\":30}"
        )

        let mappedResult = originalResult.map { person in
            TestAddress(street: "\(person.name) Street", city: "Test City")
        }

        #expect(mappedResult.object.street == "John Street")
        #expect(mappedResult.object.city == "Test City")
        // Metadata should be preserved (except rawJSON which is cleared)
        #expect(mappedResult.usage == usage)
        #expect(mappedResult.finishReason == .stop)
        #expect(mappedResult.requestId == "req-123")
        #expect(mappedResult.model == "gpt-4")
        #expect(mappedResult.provider == "openai")
        // rawJSON is cleared since it no longer matches the transformed object
        #expect(mappedResult.rawJSON == nil)
    }

    // MARK: - Equatable

    @Test("Results with Equatable objects are equatable")
    func testEquatable() {
        let person1 = TestPerson(name: "John", age: 30)
        let person2 = TestPerson(name: "John", age: 30)
        let person3 = TestPerson(name: "Jane", age: 25)

        let result1 = AIObjectResult(object: person1, finishReason: .stop)
        let result2 = AIObjectResult(object: person2, finishReason: .stop)
        let result3 = AIObjectResult(object: person3, finishReason: .stop)

        #expect(result1 == result2)
        #expect(result1 != result3)
    }

    // MARK: - Various Finish Reasons

    @Test("All finish reasons are handled")
    func testAllFinishReasons() {
        let person = TestPerson(name: "Test", age: 20)
        let reasons: [AIFinishReason] = [
            .stop, .length, .toolCalls, .contentFilter, .error, .cancelled, .unknown
        ]

        for reason in reasons {
            let result = AIObjectResult(object: person, finishReason: reason)
            #expect(result.finishReason == reason)
        }
    }
}
