//
//  SkillIntegrationTests.swift
//  AISDKTests
//
//  Integration tests for skills with AIAgentActor.
//

import XCTest
@testable import AISDK

final class SkillIntegrationTests: XCTestCase {

    // MARK: - Test Fixtures

    private var fixturesURL: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Skills/
            .deletingLastPathComponent()  // AISDKTests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Skills")
    }

    // MARK: - Full Discovery Flow Tests

    func testFullDiscoveryFlow() async throws {
        // Test the complete flow from discovery to prompt building
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        // 1. Discover skills
        let skills = try await registry.discoverSkills()
        XCTAssertGreaterThanOrEqual(skills.count, 2)

        // 2. Get metadata for prompt
        let metadata = try await registry.getSkillsMetadata()
        XCTAssertEqual(metadata.count, skills.count)

        // 3. Build available skills block
        let xmlBlock = SkillPromptBuilder.buildAvailableSkillsBlock(metadata)
        XCTAssertTrue(xmlBlock.contains("<available_skills>"))
        XCTAssertTrue(xmlBlock.contains("project-indexer"))
        XCTAssertTrue(xmlBlock.contains("test-runner"))

        // 4. Activate a skill
        let loaded = try await registry.activateSkill(named: "project-indexer")
        XCTAssertFalse(loaded.body.isEmpty)

        // 5. Build complete section with activated skill
        let activated = await registry.getActivatedSkills()
        let section = SkillPromptBuilder.buildSkillsSection(
            available: metadata,
            activated: activated,
            includeInstructions: true
        )

        XCTAssertTrue(section.contains("## Using Skills"))
        XCTAssertTrue(section.contains("<available_skills>"))
        XCTAssertTrue(section.contains("activated=\"true\""))
    }

    func testProjectSkillsPrecedence() async throws {
        // Create a temporary project directory with a skill that shadows a user skill
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let projectSkillsDir = tempDir.appendingPathComponent("project-skills")
        let userSkillsDir = tempDir.appendingPathComponent("user-skills")

        try FileManager.default.createDirectory(
            at: projectSkillsDir.appendingPathComponent("shared-skill"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: userSkillsDir.appendingPathComponent("shared-skill"),
            withIntermediateDirectories: true
        )

        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create project skill
        let projectContent = """
        ---
        name: shared-skill
        description: Project version
        ---
        # Project Instructions
        """
        try projectContent.write(
            to: projectSkillsDir.appendingPathComponent("shared-skill/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Create user skill with same name
        let userContent = """
        ---
        name: shared-skill
        description: User version
        ---
        # User Instructions
        """
        try userContent.write(
            to: userSkillsDir.appendingPathComponent("shared-skill/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )

        // Configure with project first (higher precedence)
        let config = SkillConfiguration(
            searchRoots: [projectSkillsDir, userSkillsDir],
            enableValidation: true,
            maxSkillSizeBytes: 32 * 1024,
            maxSkillLines: 500,
            enabled: true,
            strictFrontmatter: false
        )

        let registry = SkillRegistry(configuration: config)
        let skills = try await registry.discoverSkills()

        // Should find only one shared-skill (project version)
        let sharedSkills = skills.filter { $0.name == "shared-skill" }
        XCTAssertEqual(sharedSkills.count, 1)

        // Should be project scope
        let skill = sharedSkills.first!
        XCTAssertEqual(skill.scope, .project)
        XCTAssertEqual(skill.description, "Project version")
    }

    // MARK: - Skill Activation Tests

    func testSkillActivationAndDeactivation() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        // Initially not activated
        var isActive = await registry.isActivated(named: "project-indexer")
        XCTAssertFalse(isActive)

        // Activate
        _ = try await registry.activateSkill(named: "project-indexer")
        isActive = await registry.isActivated(named: "project-indexer")
        XCTAssertTrue(isActive)

        // Check activated list
        var activated = await registry.getActivatedSkills()
        XCTAssertEqual(activated.count, 1)

        // Activate another
        _ = try await registry.activateSkill(named: "test-runner")
        activated = await registry.getActivatedSkills()
        XCTAssertEqual(activated.count, 2)

        // Deactivate one
        await registry.deactivateSkill(named: "project-indexer")
        activated = await registry.getActivatedSkills()
        XCTAssertEqual(activated.count, 1)
        XCTAssertEqual(activated.first?.descriptor.name, "test-runner")
    }

    // MARK: - Resource Access Tests

    func testReadSkillScript() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        let script = try await registry.readResource(
            path: "scripts/list_files.sh",
            forSkill: "project-indexer"
        )

        XCTAssertTrue(script.contains("#!/bin/bash"))
        XCTAssertTrue(script.contains("find"))
    }

    func testReadSkillReference() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        let ref = try await registry.readResource(
            path: "references/guide.md",
            forSkill: "project-indexer"
        )

        XCTAssertTrue(ref.contains("Guide"))
    }

    // MARK: - Sandbox Tests

    func testSandboxPreventsPathTraversal() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        // Try various traversal attacks
        let traversalAttempts = [
            "../test-runner/SKILL.md",
            "../../Fixtures/Skills/test-runner/SKILL.md",
            "scripts/../../SKILL.md",
            "/etc/passwd"
        ]

        for path in traversalAttempts {
            do {
                _ = try await registry.readResource(
                    path: path,
                    forSkill: "project-indexer"
                )
                XCTFail("Expected pathTraversal error for: \(path)")
            } catch {
                guard case SkillError.pathTraversal = error else {
                    XCTFail("Expected pathTraversal error for: \(path), got \(error)")
                    continue
                }
            }
        }
    }

    // MARK: - Validation Flow Tests

    func testInvalidSkillsSkipped() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        let skills = try await registry.discoverSkills()
        let names = skills.map(\.name)

        // Valid skills should be found
        XCTAssertTrue(names.contains("project-indexer"))
        XCTAssertTrue(names.contains("test-runner"))

        // Invalid skills should be skipped
        XCTAssertFalse(names.contains("malformed-skill"))
        XCTAssertFalse(names.contains("Invalid_Name_With_Uppercase"))
    }

    // MARK: - Token Budget Tests

    func testSkillPromptTokenEstimation() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        let skills = try await registry.discoverSkills()

        // Estimate without activation
        let baseTokens = SkillPromptBuilder.estimateTokens(
            available: skills,
            activated: []
        )

        // Activate a skill
        _ = try await registry.activateSkill(named: "project-indexer")
        let activated = await registry.getActivatedSkills()

        let activatedTokens = SkillPromptBuilder.estimateTokens(
            available: skills,
            activated: activated
        )

        // Activated should have more tokens
        XCTAssertGreaterThan(activatedTokens, baseTokens)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentDiscovery() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        // Launch multiple concurrent discoveries
        async let result1 = registry.discoverSkills()
        async let result2 = registry.discoverSkills()
        async let result3 = registry.discoverSkills()

        let skills1 = try await result1
        let skills2 = try await result2
        let skills3 = try await result3

        // All should return same results (actor ensures thread safety)
        XCTAssertEqual(skills1.count, skills2.count)
        XCTAssertEqual(skills2.count, skills3.count)
    }

    func testConcurrentActivation() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        // Activate same skill concurrently
        async let load1 = registry.activateSkill(named: "project-indexer")
        async let load2 = registry.activateSkill(named: "project-indexer")

        let result1 = try await load1
        let result2 = try await load2

        // Both should get same cached result
        XCTAssertEqual(result1.body, result2.body)
    }
}
