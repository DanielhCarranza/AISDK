//
//  SkillParserTests.swift
//  AISDKTests
//
//  Tests for SKILL.md parsing including frontmatter extraction and body loading.
//

import XCTest
@testable import AISDK

final class SkillParserTests: XCTestCase {

    // MARK: - Test Fixtures

    private var fixturesURL: URL {
        // Navigate from test file location to Fixtures directory
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Skills/
            .deletingLastPathComponent()  // AISDKTests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Skills")
    }

    // MARK: - Frontmatter Extraction Tests

    func testExtractFrontmatter_ValidContent() throws {
        let content = """
        ---
        name: test-skill
        description: A test skill
        ---
        # Body content
        """

        let (frontmatter, body) = try SkillParser.extractFrontmatter(content)

        XCTAssertEqual(frontmatter["name"] as? String, "test-skill")
        XCTAssertEqual(frontmatter["description"] as? String, "A test skill")
        XCTAssertTrue(body.contains("# Body content"))
    }

    func testExtractFrontmatter_WithAllFields() throws {
        let content = """
        ---
        name: full-skill
        description: A complete skill with all fields
        license: MIT
        compatibility: Claude 3.5+
        allowed-tools: bash read_file write_file
        metadata:
          author: test
          version: "1.0"
        ---
        # Instructions
        """

        let (frontmatter, _) = try SkillParser.extractFrontmatter(content)

        XCTAssertEqual(frontmatter["name"] as? String, "full-skill")
        XCTAssertEqual(frontmatter["license"] as? String, "MIT")
        XCTAssertEqual(frontmatter["compatibility"] as? String, "Claude 3.5+")
        XCTAssertEqual(frontmatter["allowed-tools"] as? String, "bash read_file write_file")

        let metadata = frontmatter["metadata"] as? [String: String]
        XCTAssertNotNil(metadata)
        XCTAssertEqual(metadata?["author"], "test")
    }

    func testExtractFrontmatter_NoFrontmatter() {
        let content = """
        # Just markdown
        No YAML frontmatter here.
        """

        XCTAssertThrowsError(try SkillParser.extractFrontmatter(content)) { error in
            guard case SkillError.invalidFrontmatter = error else {
                XCTFail("Expected invalidFrontmatter error, got \(error)")
                return
            }
        }
    }

    func testExtractFrontmatter_UnclosedFrontmatter() {
        let content = """
        ---
        name: broken-skill
        description: Missing closing delimiter
        # Body starts without ---
        """

        XCTAssertThrowsError(try SkillParser.extractFrontmatter(content)) { error in
            guard case SkillError.invalidFrontmatter = error else {
                XCTFail("Expected invalidFrontmatter error, got \(error)")
                return
            }
        }
    }

    // MARK: - Parse Metadata Tests

    func testParseMetadata_ValidSkill() throws {
        let skillDir = fixturesURL.appendingPathComponent("project-indexer")
        let skillMDPath = skillDir.appendingPathComponent("SKILL.md")

        let descriptor = try SkillParser.parseMetadata(from: skillMDPath, scope: .project)

        XCTAssertEqual(descriptor.name, "project-indexer")
        XCTAssertFalse(descriptor.description.isEmpty)
        XCTAssertEqual(descriptor.scope, .project)
        XCTAssertEqual(descriptor.rootPath.lastPathComponent, "project-indexer")
        XCTAssertNotNil(descriptor.allowedTools)
        XCTAssertTrue(descriptor.hasScripts)
    }

    func testParseMetadata_MissingName() {
        let skillDir = fixturesURL.appendingPathComponent("malformed-skill")
        let skillMDPath = skillDir.appendingPathComponent("SKILL.md")

        XCTAssertThrowsError(try SkillParser.parseMetadata(from: skillMDPath, scope: .project)) { error in
            guard case SkillError.missingRequiredField(let field) = error else {
                XCTFail("Expected missingRequiredField error, got \(error)")
                return
            }
            XCTAssertEqual(field, "name")
        }
    }

    func testParseMetadata_AllowedToolsParsing() throws {
        let content = """
        ---
        name: tools-test
        description: Test allowed tools parsing
        allowed-tools: bash read_file write_file
        ---
        # Body
        """

        // Create a temporary file for testing
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tools-test")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillMDPath = tempDir.appendingPathComponent("SKILL.md")
        try content.write(to: skillMDPath, atomically: true, encoding: .utf8)

        let descriptor = try SkillParser.parseMetadata(from: skillMDPath, scope: .user)

        XCTAssertEqual(descriptor.allowedTools, ["bash", "read_file", "write_file"])
    }

    // MARK: - Load Body Tests

    func testLoadBody_ValidSkill() throws {
        let skillDir = fixturesURL.appendingPathComponent("project-indexer")
        let skillMDPath = skillDir.appendingPathComponent("SKILL.md")

        let descriptor = try SkillParser.parseMetadata(from: skillMDPath, scope: .project)
        let loaded = try SkillParser.loadBody(for: descriptor)

        XCTAssertFalse(loaded.body.isEmpty)
        XCTAssertTrue(loaded.body.contains("Project Indexer"))
        XCTAssertTrue(loaded.scriptPaths.contains { $0.contains("list_files.sh") })
        XCTAssertTrue(loaded.referencePaths.contains { $0.contains("guide.md") })
    }

    func testLoadBody_ScriptDiscovery() throws {
        let skillDir = fixturesURL.appendingPathComponent("test-runner")
        let skillMDPath = skillDir.appendingPathComponent("SKILL.md")

        let descriptor = try SkillParser.parseMetadata(from: skillMDPath, scope: .project)
        let loaded = try SkillParser.loadBody(for: descriptor)

        XCTAssertFalse(loaded.scriptPaths.isEmpty)
        XCTAssertTrue(loaded.scriptPaths.contains { $0.contains("run_tests.sh") })
    }

    // MARK: - Find SKILL.md Tests

    func testFindSkillMD_Exists() {
        let skillDir = fixturesURL.appendingPathComponent("project-indexer")
        let result = SkillParser.findSkillMD(in: skillDir)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lastPathComponent, "SKILL.md")
    }

    func testFindSkillMD_NotExists() {
        let emptyDir = fixturesURL  // Skills dir itself has no SKILL.md
        let result = SkillParser.findSkillMD(in: emptyDir)

        XCTAssertNil(result)
    }

    // MARK: - Unknown Keys Tests

    func testUnknownKeys_NoUnknownKeys() {
        let frontmatter: [String: Any] = [
            "name": "test",
            "description": "desc",
            "license": "MIT"
        ]

        let unknown = SkillParser.unknownKeys(in: frontmatter)
        XCTAssertTrue(unknown.isEmpty)
    }

    func testUnknownKeys_WithUnknownKeys() {
        let frontmatter: [String: Any] = [
            "name": "test",
            "description": "desc",
            "unknown_key": "value",
            "another_unknown": 123
        ]

        let unknown = SkillParser.unknownKeys(in: frontmatter)
        XCTAssertEqual(Set(unknown), Set(["unknown_key", "another_unknown"]))
    }
}
