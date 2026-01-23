//
//  AIObjectRequestTests.swift
//  AISDK
//
//  Tests for AIObjectRequest
//

import Foundation
import Testing
@testable import AISDK

// MARK: - Test Schema Model

struct TestUserProfile: Codable, Sendable, JSONSchemaModel {
    @Field(description: "User's name")
    var name: String = ""

    @Field(description: "User's age")
    var age: Int = 0

    @Field(description: "User's email")
    var email: String? = nil

    init() {}

    init(name: String, age: Int, email: String? = nil) {
        self.name = name
        self.age = age
        self.email = email
    }
}

@Suite("AIObjectRequest Tests")
struct AIObjectRequestTests {
    // MARK: - Basic Initialization

    @Test("Creates request with minimal parameters")
    func testMinimalInit() {
        let schema = TestUserProfile.schema()
        let request = AIObjectRequest<TestUserProfile>(
            messages: [.user("Create a user profile")],
            schema: schema
        )

        #expect(request.messages.count == 1)
        #expect(request.messages[0].role == .user)
        #expect(request.model == nil)
        #expect(request.maxTokens == nil)
        #expect(request.temperature == nil)
        #expect(request.sensitivity == .standard)
        #expect(request.allowedProviders == nil)
        #expect(request.bufferPolicy == nil)
    }

    @Test("Creates request with all parameters")
    func testFullInit() {
        let messages = [AIMessage.user("Create a user"), AIMessage.assistant("Here's the user")]
        let allowedProviders: Set<String> = ["openai", "anthropic"]
        let bufferPolicy = StreamBufferPolicy.dropOldest(capacity: 500)
        let schema = TestUserProfile.schema()

        let request = AIObjectRequest<TestUserProfile>(
            messages: messages,
            schema: schema,
            schemaName: "UserProfile",
            strict: false,
            model: "gpt-4",
            maxTokens: 1000,
            temperature: 0.7,
            topP: 0.9,
            allowedProviders: allowedProviders,
            sensitivity: .phi,
            bufferPolicy: bufferPolicy,
            metadata: ["requestId": "test-123"]
        )

        #expect(request.messages.count == 2)
        #expect(request.model == "gpt-4")
        #expect(request.maxTokens == 1000)
        #expect(request.temperature == 0.7)
        #expect(request.topP == 0.9)
        #expect(request.sensitivity == .phi)
        #expect(request.allowedProviders == allowedProviders)
        #expect(request.bufferPolicy?.capacity == 500)
        #expect(request.metadata?["requestId"] == "test-123")
        #expect(request.schemaName == "UserProfile")
        #expect(request.strict == false)
    }

    @Test("strict defaults to true")
    func testStrictDefault() {
        let schema = TestUserProfile.schema()
        let request = AIObjectRequest<TestUserProfile>(
            messages: [.user("Create a user profile")],
            schema: schema
        )

        #expect(request.strict == true)
    }

    // MARK: - PHI Protection

    @Test("canUseProvider returns true when allowedProviders is nil")
    func testCanUseProviderWithNilAllowed() {
        let schema = TestUserProfile.schema()
        let request = AIObjectRequest<TestUserProfile>(
            messages: [.user("Create a user")],
            schema: schema
        )

        #expect(request.canUseProvider("openai") == true)
        #expect(request.canUseProvider("anthropic") == true)
        #expect(request.canUseProvider("any-provider") == true)
    }

    @Test("canUseProvider respects allowedProviders")
    func testCanUseProviderWithRestrictions() {
        let schema = TestUserProfile.schema()
        let request = AIObjectRequest<TestUserProfile>(
            messages: [.user("Create a user")],
            schema: schema,
            allowedProviders: ["openai", "anthropic"]
        )

        #expect(request.canUseProvider("openai") == true)
        #expect(request.canUseProvider("anthropic") == true)
        #expect(request.canUseProvider("google") == false)
        #expect(request.canUseProvider("unknown") == false)
    }

    // MARK: - Request Transformations

    @Test("withSensitivity creates new request with updated sensitivity")
    func testWithSensitivity() {
        let schema = TestUserProfile.schema()
        let original = AIObjectRequest<TestUserProfile>(
            messages: [.user("Test")],
            schema: schema,
            model: "gpt-4",
            sensitivity: .standard
        )

        let updated = original.withSensitivity(.phi)

        #expect(updated.sensitivity == .phi)
        #expect(updated.model == "gpt-4")
        #expect(updated.messages.count == 1)
        #expect(original.sensitivity == .standard) // Original unchanged
    }

    @Test("withAllowedProviders creates new request with provider restrictions")
    func testWithAllowedProviders() {
        let schema = TestUserProfile.schema()
        let original = AIObjectRequest<TestUserProfile>(
            messages: [.user("Test")],
            schema: schema,
            sensitivity: .phi
        )

        let providers: Set<String> = ["openai"]
        let updated = original.withAllowedProviders(providers)

        #expect(updated.allowedProviders == providers)
        #expect(updated.sensitivity == .phi)
        #expect(original.allowedProviders == nil) // Original unchanged
    }

    @Test("withBufferPolicy creates new request with buffer policy")
    func testWithBufferPolicy() {
        let schema = TestUserProfile.schema()
        let original = AIObjectRequest<TestUserProfile>(
            messages: [.user("Test")],
            schema: schema
        )
        let policy = StreamBufferPolicy.dropNewest(capacity: 2000)

        let updated = original.withBufferPolicy(policy)

        #expect(updated.bufferPolicy?.capacity == 2000)
        #expect(updated.bufferPolicy == .dropNewest(capacity: 2000))
        #expect(original.bufferPolicy == nil) // Original unchanged
    }

    // MARK: - Schema Name Sanitization

    @Test("effectiveSchemaName uses custom name when provided")
    func testEffectiveSchemaNameCustom() {
        let schema = TestUserProfile.schema()
        let request = AIObjectRequest<TestUserProfile>(
            messages: [.user("Test")],
            schema: schema,
            schemaName: "MyCustomSchema"
        )

        #expect(request.effectiveSchemaName == "MyCustomSchema")
    }

    @Test("effectiveSchemaName sanitizes type name")
    func testEffectiveSchemaNameFromType() {
        let schema = TestUserProfile.schema()
        let request = AIObjectRequest<TestUserProfile>(
            messages: [.user("Test")],
            schema: schema
        )

        // Should remove generic syntax and module prefixes
        let schemaName = request.effectiveSchemaName
        #expect(!schemaName.contains("<"))
        #expect(!schemaName.contains(">"))
        #expect(!schemaName.contains("."))
        #expect(!schemaName.isEmpty)
    }

    @Test("effectiveSchemaName sanitizes invalid characters")
    func testEffectiveSchemaNameSanitization() {
        let schema = TestUserProfile.schema()
        let request = AIObjectRequest<TestUserProfile>(
            messages: [.user("Test")],
            schema: schema,
            schemaName: "My<Generic>.Type With Spaces"
        )

        let schemaName = request.effectiveSchemaName
        #expect(!schemaName.contains("<"))
        #expect(!schemaName.contains(">"))
        #expect(!schemaName.contains("."))
        #expect(!schemaName.contains(" "))
        // After sanitization, invalid chars are removed and only last component after dot is kept
        // "Type With Spaces" becomes "Type_With_Spaces"
        #expect(schemaName.contains("Type"))
    }

    @Test("effectiveSchemaName truncates to 64 characters")
    func testEffectiveSchemaNameTruncation() {
        let schema = TestUserProfile.schema()
        let longName = String(repeating: "A", count: 100)
        let request = AIObjectRequest<TestUserProfile>(
            messages: [.user("Test")],
            schema: schema,
            schemaName: longName
        )

        #expect(request.effectiveSchemaName.count <= 64)
    }
}
