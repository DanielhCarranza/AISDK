//
//  SkillValidatorTests.swift
//  AISDKTests
//
//  Tests for skill validation against the LegacyAgent Skills Protocol.
//

import XCTest
@testable import AISDK

final class SkillValidatorTests: XCTestCase {

    // MARK: - Name Validation Tests

    func testValidateName_Valid() {
        let validNames = [
            "a",
            "test",
            "my-skill",
            "skill-123",
            "a1b2c3",
            "pdf-reader-v2"
        ]

        for name in validNames {
            let result = SkillValidator.validateName(name)
            XCTAssertTrue(result.isValid, "Expected '\(name)' to be valid")
        }
    }

    func testValidateName_Empty() {
        let result = SkillValidator.validateName("")
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { error in
            if case .invalidName(_, let reason) = error {
                return reason.contains("empty")
            }
            return false
        })
    }

    func testValidateName_TooLong() {
        let longName = String(repeating: "a", count: 65)
        let result = SkillValidator.validateName(longName)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { error in
            if case .invalidName(_, let reason) = error {
                return reason.contains("64")
            }
            return false
        })
    }

    func testValidateName_MaxLength() {
        let maxName = String(repeating: "a", count: 64)
        let result = SkillValidator.validateName(maxName)
        XCTAssertTrue(result.isValid)
    }

    func testValidateName_Uppercase() {
        let result = SkillValidator.validateName("MySkill")
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { error in
            if case .invalidName(_, let reason) = error {
                return reason.contains("lowercase")
            }
            return false
        })
    }

    func testValidateName_StartsWithHyphen() {
        let result = SkillValidator.validateName("-skill")
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { error in
            if case .invalidName(_, let reason) = error {
                return reason.contains("start with hyphen")
            }
            return false
        })
    }

    func testValidateName_EndsWithHyphen() {
        let result = SkillValidator.validateName("skill-")
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { error in
            if case .invalidName(_, let reason) = error {
                return reason.contains("end with hyphen")
            }
            return false
        })
    }

    func testValidateName_ConsecutiveHyphens() {
        let result = SkillValidator.validateName("my--skill")
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { error in
            if case .invalidName(_, let reason) = error {
                return reason.contains("consecutive")
            }
            return false
        })
    }

    func testValidateName_InvalidCharacters() {
        let invalidNames = [
            "my_skill",      // underscore
            "my skill",      // space
            "skill.name",    // dot
            "skill@test",    // special char
        ]

        for name in invalidNames {
            let result = SkillValidator.validateName(name)
            XCTAssertFalse(result.isValid, "Expected '\(name)' to be invalid")
        }
    }

    // MARK: - Directory Match Validation Tests

    func testValidateDirectoryMatch_Matching() {
        let result = SkillValidator.validateDirectoryMatch(
            directoryName: "my-skill",
            skillName: "my-skill"
        )
        XCTAssertTrue(result.isValid)
    }

    func testValidateDirectoryMatch_Mismatch() {
        let result = SkillValidator.validateDirectoryMatch(
            directoryName: "different-name",
            skillName: "my-skill"
        )
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { error in
            if case .directoryNameMismatch = error {
                return true
            }
            return false
        })
    }

    // MARK: - Description Validation Tests

    func testValidateDescription_Valid() {
        let result = SkillValidator.validateDescription("A valid description")
        XCTAssertTrue(result.isValid)
    }

    func testValidateDescription_Empty() {
        let result = SkillValidator.validateDescription("")
        XCTAssertFalse(result.isValid)
    }

    func testValidateDescription_TooLong() {
        let longDesc = String(repeating: "a", count: 1025)
        let result = SkillValidator.validateDescription(longDesc)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { error in
            if case .descriptionTooLong = error {
                return true
            }
            return false
        })
    }

    func testValidateDescription_MaxLength() {
        let maxDesc = String(repeating: "a", count: 1024)
        let result = SkillValidator.validateDescription(maxDesc)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Compatibility Validation Tests

    func testValidateCompatibility_Valid() {
        let result = SkillValidator.validateCompatibility("Claude 3.5+")
        XCTAssertTrue(result.isValid)
    }

    func testValidateCompatibility_TooLong() {
        let longComp = String(repeating: "a", count: 501)
        let result = SkillValidator.validateCompatibility(longComp)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { error in
            if case .compatibilityTooLong = error {
                return true
            }
            return false
        })
    }

    // MARK: - Path Validation Tests

    func testValidatePath_Valid() throws {
        let skillRoot = URL(fileURLWithPath: "/skills/my-skill")

        let validPaths = [
            "scripts/run.sh",
            "references/guide.md",
            "assets/template.txt"
        ]

        for path in validPaths {
            let resolved = try SkillValidator.validatePath(path, skillRoot: skillRoot)
            XCTAssertTrue(resolved.path.hasPrefix(skillRoot.path))
        }
    }

    func testValidatePath_TraversalAttempt() {
        let skillRoot = URL(fileURLWithPath: "/skills/my-skill")

        let traversalPaths = [
            "../other-skill/SKILL.md",
            "../../etc/passwd",
            "scripts/../../../etc/passwd"
        ]

        for path in traversalPaths {
            XCTAssertThrowsError(
                try SkillValidator.validatePath(path, skillRoot: skillRoot)
            ) { error in
                guard case SkillError.pathTraversal = error else {
                    XCTFail("Expected pathTraversal error for '\(path)'")
                    return
                }
            }
        }
    }

    func testValidatePath_AbsolutePath() {
        let skillRoot = URL(fileURLWithPath: "/skills/my-skill")

        XCTAssertThrowsError(
            try SkillValidator.validatePath("/etc/passwd", skillRoot: skillRoot)
        ) { error in
            guard case SkillError.pathTraversal = error else {
                XCTFail("Expected pathTraversal error")
                return
            }
        }
    }

    // MARK: - Tool Validation Tests

    func testValidateTool_Allowed() throws {
        let allowedTools = ["bash", "read_file", "write_file"]

        try SkillValidator.validateTool("bash", allowedTools: allowedTools)
        try SkillValidator.validateTool("read_file", allowedTools: allowedTools)
    }

    func testValidateTool_NotAllowed() {
        let allowedTools = ["bash", "read_file"]

        XCTAssertThrowsError(
            try SkillValidator.validateTool("delete_file", allowedTools: allowedTools)
        ) { error in
            guard case SkillError.toolNotAllowed = error else {
                XCTFail("Expected toolNotAllowed error")
                return
            }
        }
    }

    func testValidateTool_NoRestrictions() throws {
        // nil means all tools allowed
        try SkillValidator.validateTool("any_tool", allowedTools: nil)
    }

    func testValidateTool_CaseInsensitive() throws {
        let allowedTools = ["Bash", "Read_File"]

        try SkillValidator.validateTool("bash", allowedTools: allowedTools)
        try SkillValidator.validateTool("BASH", allowedTools: allowedTools)
    }

    func testValidateTool_WildcardPattern() throws {
        let allowedTools = ["Bash(*)"]

        try SkillValidator.validateTool("Bash", allowedTools: allowedTools)
        try SkillValidator.validateTool("BashCommand", allowedTools: allowedTools)
    }

    // MARK: - Full Validation Tests

    func testValidate_ValidDescriptor() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("valid-skill")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = """
        ---
        name: valid-skill
        description: A valid test skill
        ---
        # Body
        """

        let skillMDPath = tempDir.appendingPathComponent("SKILL.md")
        try content.write(to: skillMDPath, atomically: true, encoding: .utf8)

        let descriptor = try SkillParser.parseMetadata(from: skillMDPath, scope: .project)
        let result = SkillValidator.validate(descriptor, configuration: .default)

        XCTAssertTrue(result.isValid)
    }
}
