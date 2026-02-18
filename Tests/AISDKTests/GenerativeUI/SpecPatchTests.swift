//
//  SpecPatchTests.swift
//  AISDKTests
//
//  Tests for SpecPatch and SpecValue types
//

import Testing
import Foundation
@testable import AISDK

// MARK: - SpecValue Tests

@Suite("SpecValue")
struct SpecValueTests {
    @Test("Encodes and decodes string")
    func stringRoundTrip() throws {
        let original = SpecValue("hello")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpecValue.self, from: data)
        #expect(decoded == original)
        #expect(decoded.stringValue == "hello")
    }

    @Test("Encodes and decodes integer")
    func intRoundTrip() throws {
        let original = SpecValue(42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpecValue.self, from: data)
        #expect(decoded == original)
        #expect(decoded.intValue == 42)
    }

    @Test("Encodes and decodes double")
    func doubleRoundTrip() throws {
        let original = SpecValue(3.14)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpecValue.self, from: data)
        #expect(decoded.doubleValue != nil)
    }

    @Test("Encodes and decodes bool")
    func boolRoundTrip() throws {
        let original = SpecValue(true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpecValue.self, from: data)
        #expect(decoded == original)
        #expect(decoded.boolValue == true)
    }

    @Test("Encodes and decodes null")
    func nullRoundTrip() throws {
        let original = SpecValue.null
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpecValue.self, from: data)
        #expect(decoded == original)
        #expect(decoded.isNull)
    }

    @Test("Encodes and decodes array")
    func arrayRoundTrip() throws {
        let original = SpecValue([SpecValue("a"), SpecValue(1)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpecValue.self, from: data)
        #expect(decoded.arrayValue?.count == 2)
    }

    @Test("Encodes and decodes dictionary")
    func dictRoundTrip() throws {
        let original = SpecValue(["key": SpecValue("value"), "num": SpecValue(42)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpecValue.self, from: data)
        #expect(decoded.dictionaryValue?["key"]?.stringValue == "value")
        #expect(decoded.dictionaryValue?["num"]?.intValue == 42)
    }

    @Test("Supports literal expressions")
    func literals() {
        let s: SpecValue = "hello"
        #expect(s.stringValue == "hello")

        let i: SpecValue = 42
        #expect(i.intValue == 42)

        let b: SpecValue = true
        #expect(b.boolValue == true)

        let n: SpecValue = nil
        #expect(n.isNull)
    }

    @Test("Equality for different types returns false")
    func inequalityAcrossTypes() {
        #expect(SpecValue("42") != SpecValue(42))
        #expect(SpecValue(true) != SpecValue(1))
    }
}

// MARK: - SpecPatch Tests

@Suite("SpecPatch")
struct SpecPatchTests {
    @Test("Encodes add operation")
    func encodeAdd() throws {
        let patch = SpecPatch(
            op: .add,
            path: "/elements/metric",
            value: SpecValue(["type": SpecValue("Metric"), "props": SpecValue(["value": SpecValue(42)])])
        )
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SpecPatch.self, from: data)
        #expect(decoded.op == .add)
        #expect(decoded.path == "/elements/metric")
        #expect(decoded.value != nil)
        #expect(decoded.from == nil)
    }

    @Test("Encodes remove operation")
    func encodeRemove() throws {
        let patch = SpecPatch(op: .remove, path: "/elements/old")
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SpecPatch.self, from: data)
        #expect(decoded.op == .remove)
        #expect(decoded.path == "/elements/old")
        #expect(decoded.value == nil)
    }

    @Test("Encodes replace operation")
    func encodeReplace() throws {
        let patch = SpecPatch(op: .replace, path: "/state/revenue", value: SpecValue(12345))
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SpecPatch.self, from: data)
        #expect(decoded.op == .replace)
        #expect(decoded.value?.intValue == 12345)
    }

    @Test("Encodes move operation")
    func encodeMove() throws {
        let patch = SpecPatch(op: .move, path: "/elements/newKey", from: "/elements/oldKey")
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SpecPatch.self, from: data)
        #expect(decoded.op == .move)
        #expect(decoded.from == "/elements/oldKey")
    }

    @Test("Encodes copy operation")
    func encodeCopy() throws {
        let patch = SpecPatch(op: .copy, path: "/elements/copy", from: "/elements/source")
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SpecPatch.self, from: data)
        #expect(decoded.op == .copy)
        #expect(decoded.from == "/elements/source")
    }

    @Test("Encodes test operation")
    func encodeTest() throws {
        let patch = SpecPatch(op: .test, path: "/state/flag", value: SpecValue(true))
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(SpecPatch.self, from: data)
        #expect(decoded.op == .test)
        #expect(decoded.value?.boolValue == true)
    }

    // MARK: - Path Validation

    @Test("Valid paths accepted")
    func validPaths() {
        #expect(SpecPatch(op: .add, path: "/elements/foo", value: "bar").hasValidPath)
        #expect(SpecPatch(op: .add, path: "/state/x", value: 1).hasValidPath)
        #expect(SpecPatch(op: .replace, path: "/root", value: "main").hasValidPath)
    }

    @Test("Invalid paths rejected")
    func invalidPaths() {
        #expect(!SpecPatch(op: .add, path: "/other/foo", value: "bar").hasValidPath)
        #expect(!SpecPatch(op: .add, path: "/system/config", value: 1).hasValidPath)
    }

    @Test("Validate rejects add without value")
    func validateAddNoValue() {
        let patch = SpecPatch(op: .add, path: "/elements/x")
        #expect(throws: SpecPatchError.self) { try patch.validate() }
    }

    @Test("Validate rejects move without from")
    func validateMoveNoFrom() {
        let patch = SpecPatch(op: .move, path: "/elements/x")
        #expect(throws: SpecPatchError.self) { try patch.validate() }
    }

    @Test("Validate accepts remove without value")
    func validateRemove() throws {
        let patch = SpecPatch(op: .remove, path: "/elements/x")
        try patch.validate()
    }

    @Test("Validate rejects path without leading slash")
    func validatePathNoSlash() {
        let patch = SpecPatch(op: .remove, path: "elements/x")
        #expect(throws: SpecPatchError.self) { try patch.validate() }
    }

    @Test("Validate rejects disallowed path")
    func validateDisallowedPath() {
        let patch = SpecPatch(op: .remove, path: "/forbidden/x")
        #expect(throws: SpecPatchError.self) { try patch.validate() }
    }
}

// MARK: - SpecPatchBatch Tests

@Suite("SpecPatchBatch")
struct SpecPatchBatchTests {
    @Test("Encodes and decodes batch")
    func roundTrip() throws {
        let batch = SpecPatchBatch(
            patches: [
                SpecPatch(op: .add, path: "/elements/a", value: "hello"),
                SpecPatch(op: .replace, path: "/state/x", value: 42)
            ],
            version: "1.0.0"
        )
        let data = try JSONEncoder().encode(batch)
        let decoded = try JSONDecoder().decode(SpecPatchBatch.self, from: data)
        #expect(decoded.patches.count == 2)
        #expect(decoded.version == "1.0.0")
    }

    @Test("Batch validate checks all patches")
    func batchValidate() {
        let batch = SpecPatchBatch(patches: [
            SpecPatch(op: .add, path: "/elements/a", value: "ok"),
            SpecPatch(op: .add, path: "/elements/b") // Missing value
        ])
        #expect(throws: SpecPatchError.self) { try batch.validate() }
    }

    @Test("Decodes from JSON string")
    func decodeFromJSON() throws {
        let json = """
        {"patches":[{"op":"add","path":"/elements/metric","value":{"type":"Metric"}}]}
        """
        let data = Data(json.utf8)
        let batch = try JSONDecoder().decode(SpecPatchBatch.self, from: data)
        #expect(batch.patches.count == 1)
        #expect(batch.patches[0].op == .add)
        #expect(batch.patches[0].path == "/elements/metric")
    }
}
