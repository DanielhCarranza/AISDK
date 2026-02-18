//
//  SkillPromptBuilderTests.swift
//  AISDKTests
//
//  Tests for skill prompt XML/JSON generation.
//

import XCTest
@testable import AISDK

final class SkillPromptBuilderTests: XCTestCase {

    // MARK: - Test Helpers

    private func createTestDescriptor(
        name: String = "test-skill",
        description: String = "A test skill",
        scope: SkillScope = .project,
        allowedTools: [String]? = nil
    ) -> SkillDescriptor {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)

        return SkillDescriptor(
            name: name,
            description: description,
            license: "MIT",
            compatibility: nil,
            metadata: nil,
            allowedTools: allowedTools,
            rootPath: tempDir,
            skillMDPath: tempDir.appendingPathComponent("SKILL.md"),
            modificationDate: Date(),
            scope: scope
        )
    }

    private func createLoadedSkill(
        name: String = "test-skill",
        body: String = "# Instructions\nDo something.",
        scriptPaths: [String] = ["scripts/run.sh"],
        referencePaths: [String] = []
    ) -> LoadedSkill {
        let descriptor = createTestDescriptor(name: name)
        return LoadedSkill(
            descriptor: descriptor,
            body: body,
            scriptPaths: scriptPaths,
            referencePaths: referencePaths
        )
    }

    // MARK: - XML Block Tests

    func testBuildAvailableSkillsBlock_Empty() {
        let result = SkillPromptBuilder.buildAvailableSkillsBlock([])
        XCTAssertEqual(result, "<available_skills>\n</available_skills>")
    }

    func testBuildAvailableSkillsBlock_SingleSkill() {
        let skill = createTestDescriptor()
        let result = SkillPromptBuilder.buildAvailableSkillsBlock([skill])

        XCTAssertTrue(result.contains("<available_skills>"))
        XCTAssertTrue(result.contains("</available_skills>"))
        XCTAssertTrue(result.contains("<skill name=\"test-skill\" scope=\"project\">"))
        XCTAssertTrue(result.contains("<description>A test skill</description>"))
        // hasScripts is computed from filesystem, so we just check the element exists
        XCTAssertTrue(result.contains("<has_scripts>"))
        XCTAssertTrue(result.contains("</skill>"))
    }

    func testBuildAvailableSkillsBlock_WithAllowedTools() {
        let skill = createTestDescriptor(
            allowedTools: ["bash", "read_file"]
        )
        let result = SkillPromptBuilder.buildAvailableSkillsBlock([skill])

        XCTAssertTrue(result.contains("<allowed_tools>bash read_file</allowed_tools>"))
    }

    func testBuildAvailableSkillsBlock_MultipleSkills_Sorted() {
        let skills = [
            createTestDescriptor(name: "zebra-skill", description: "Z skill"),
            createTestDescriptor(name: "alpha-skill", description: "A skill"),
            createTestDescriptor(name: "middle-skill", description: "M skill")
        ]

        let result = SkillPromptBuilder.buildAvailableSkillsBlock(skills)

        // Should be sorted alphabetically
        let alphaIndex = result.range(of: "alpha-skill")!.lowerBound
        let middleIndex = result.range(of: "middle-skill")!.lowerBound
        let zebraIndex = result.range(of: "zebra-skill")!.lowerBound

        XCTAssertTrue(alphaIndex < middleIndex)
        XCTAssertTrue(middleIndex < zebraIndex)
    }

    func testBuildAvailableSkillsBlock_XMLEscaping() {
        let skill = createTestDescriptor(
            name: "test-skill",
            description: "Description with <special> & \"chars\""
        )
        let result = SkillPromptBuilder.buildAvailableSkillsBlock([skill])

        XCTAssertTrue(result.contains("&lt;special&gt;"))
        XCTAssertTrue(result.contains("&amp;"))
        XCTAssertTrue(result.contains("&quot;chars&quot;"))
    }

    // MARK: - Minimal Block Tests

    func testBuildMinimalSkillsBlock_Empty() {
        let result = SkillPromptBuilder.buildMinimalSkillsBlock([])
        XCTAssertEqual(result, "<available_skills />")
    }

    func testBuildMinimalSkillsBlock_SingleSkill() {
        let skill = createTestDescriptor()
        let result = SkillPromptBuilder.buildMinimalSkillsBlock([skill])

        XCTAssertTrue(result.contains("<skill name=\"test-skill\">"))
        XCTAssertTrue(result.contains("A test skill"))
        // Should NOT contain detailed fields
        XCTAssertFalse(result.contains("<location>"))
        XCTAssertFalse(result.contains("<has_scripts>"))
    }

    // MARK: - JSON Format Tests

    func testBuildSkillsJSON_Empty() {
        let result = SkillPromptBuilder.buildSkillsJSON([])
        XCTAssertEqual(result, "[]")
    }

    func testBuildSkillsJSON_SingleSkill() {
        let skill = createTestDescriptor(
            allowedTools: ["bash"]
        )
        let result = SkillPromptBuilder.buildSkillsJSON([skill])

        // Should be valid JSON
        let data = result.data(using: .utf8)!
        let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?.count, 1)
        XCTAssertEqual(json?.first?["name"] as? String, "test-skill")
        XCTAssertEqual(json?.first?["description"] as? String, "A test skill")
        XCTAssertEqual(json?.first?["scope"] as? String, "project")
    }

    // MARK: - Activated Skill Block Tests

    func testBuildActivatedSkillBlock() {
        let loaded = createLoadedSkill(
            scriptPaths: ["scripts/run.sh", "scripts/build.sh"],
            referencePaths: ["references/guide.md"]
        )

        let result = SkillPromptBuilder.buildActivatedSkillBlock(loaded)

        XCTAssertTrue(result.contains("<skill name=\"test-skill\" activated=\"true\">"))
        XCTAssertTrue(result.contains("<available_scripts>"))
        XCTAssertTrue(result.contains("<script>scripts/run.sh</script>"))
        XCTAssertTrue(result.contains("<available_references>"))
        XCTAssertTrue(result.contains("<reference>references/guide.md</reference>"))
        XCTAssertTrue(result.contains("<instructions>"))
        XCTAssertTrue(result.contains("# Instructions"))
        XCTAssertTrue(result.contains("</instructions>"))
        XCTAssertTrue(result.contains("</skill>"))
    }

    func testBuildActivatedSkillBlock_NoScripts() {
        let loaded = createLoadedSkill(
            scriptPaths: [],
            referencePaths: []
        )

        let result = SkillPromptBuilder.buildActivatedSkillBlock(loaded)

        XCTAssertFalse(result.contains("<available_scripts>"))
        XCTAssertFalse(result.contains("<available_references>"))
    }

    // MARK: - Skills Section Tests

    func testBuildSkillsSection_AvailableOnly() {
        let skills = [createTestDescriptor()]
        let result = SkillPromptBuilder.buildSkillsSection(
            available: skills,
            activated: [],
            includeInstructions: true
        )

        XCTAssertTrue(result.contains("## Using Skills"))
        XCTAssertTrue(result.contains("<available_skills>"))
    }

    func testBuildSkillsSection_WithActivated() {
        let skills = [createTestDescriptor()]
        let loaded = [createLoadedSkill()]

        let result = SkillPromptBuilder.buildSkillsSection(
            available: skills,
            activated: loaded,
            includeInstructions: true
        )

        XCTAssertTrue(result.contains("<available_skills>"))
        XCTAssertTrue(result.contains("activated=\"true\""))
    }

    func testBuildSkillsSection_NoInstructions() {
        let skills = [createTestDescriptor()]
        let result = SkillPromptBuilder.buildSkillsSection(
            available: skills,
            activated: [],
            includeInstructions: false
        )

        XCTAssertFalse(result.contains("## Using Skills"))
        XCTAssertTrue(result.contains("<available_skills>"))
    }

    func testBuildSkillsSection_Empty() {
        let result = SkillPromptBuilder.buildSkillsSection(
            available: [],
            activated: [],
            includeInstructions: true
        )

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Usage Instructions Tests

    func testBuildSkillUsageInstructions() {
        let result = SkillPromptBuilder.buildSkillUsageInstructions()

        XCTAssertTrue(result.contains("## Using Skills"))
        XCTAssertTrue(result.contains("<available_skills>"))
        XCTAssertTrue(result.contains("scripts/"))
        XCTAssertTrue(result.contains("references/"))
    }

    // MARK: - Token Estimation Tests

    func testEstimateTokens() {
        let skills = [
            createTestDescriptor(name: "skill-1"),
            createTestDescriptor(name: "skill-2")
        ]

        let tokens = SkillPromptBuilder.estimateTokens(
            available: skills,
            activated: []
        )

        XCTAssertGreaterThan(tokens, 0)
    }

    func testExceedsTokenBudget() {
        let skills = [createTestDescriptor()]

        // Small budget should exceed
        let exceeds = SkillPromptBuilder.exceedsTokenBudget(
            available: skills,
            activated: [],
            maxTokens: 10
        )
        XCTAssertTrue(exceeds)

        // Large budget should not exceed
        let notExceeds = SkillPromptBuilder.exceedsTokenBudget(
            available: skills,
            activated: [],
            maxTokens: 10000
        )
        XCTAssertFalse(notExceeds)
    }
}
