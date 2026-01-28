//
//  RealSkillsIntegrationTests.swift
//  AISDKTests
//
//  Integration tests against the actual skills in .agents/skills/
//

import Testing
import Foundation
@testable import AISDK

/// Tests that verify the Skills implementation works with real skill files
struct RealSkillsIntegrationTests {

    /// Helper to get the project root directory
    /// Uses SRCROOT environment variable when available, falls back to working directory
    private static var projectRoot: URL {
        // Try SRCROOT first (set by Xcode)
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            return URL(fileURLWithPath: srcRoot)
        }

        // For swift test, try to find it from the current working directory
        // The test is run from the project root by default
        let cwd = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: cwd)
    }

    /// Test that we can discover skills from the .agents/skills directory
    @Test("Discover real skills from .agents/skills")
    func testDiscoverRealSkills() async throws {
        let skillsDir = Self.projectRoot.appendingPathComponent(".agents/skills")

        // Skip if the directory doesn't exist (e.g. CI environment)
        guard FileManager.default.fileExists(atPath: skillsDir.path) else {
            print("Skipping: .agents/skills not found at \(skillsDir.path)")
            return
        }

        // Create registry with real skills directory
        let config = SkillConfiguration(searchRoots: [skillsDir])
        let registry = SkillRegistry(configuration: config)

        // Discover skills
        let skills = try await registry.discoverSkills()

        // Should find at least the known skills
        #expect(skills.count >= 2, "Expected at least 2 skills, found \(String(describing: skills.count))")

        // Check for specific skills we know exist
        let skillNames = skills.map { $0.name }
        #expect(skillNames.contains("swift-concurrency-expert"), "Expected swift-concurrency-expert skill")
        #expect(skillNames.contains("gepetto"), "Expected gepetto skill")

        print("Found \(skills.count) skills: \(skillNames.sorted().joined(separator: ", "))")
    }

    /// Test that we can activate and load a real skill's body
    @Test("Activate real skill and load body")
    func testActivateRealSkill() async throws {
        let skillsDir = Self.projectRoot.appendingPathComponent(".agents/skills")

        guard FileManager.default.fileExists(atPath: skillsDir.path) else {
            print("Skipping: .agents/skills not found at \(skillsDir.path)")
            return
        }

        let config = SkillConfiguration(searchRoots: [skillsDir])
        let registry = SkillRegistry(configuration: config)

        // Discover first
        _ = try await registry.discoverSkills()

        // Activate swift-concurrency-expert
        let loaded = try await registry.activateSkill(named: "swift-concurrency-expert")

        // Verify descriptor
        #expect(loaded.descriptor.name == "swift-concurrency-expert")
        #expect(loaded.descriptor.description.contains("Swift Concurrency"))

        // Verify body content was loaded
        #expect(!loaded.body.isEmpty, "Body should not be empty")
        #expect(loaded.body.contains("Workflow"), "Body should contain workflow section")
        #expect(loaded.body.contains("Reference material"), "Body should contain reference section")

        // Check for references directory
        if loaded.descriptor.hasReferences {
            #expect(!loaded.referencePaths.isEmpty, "Should have reference files")
            print("Reference files: \(loaded.referencePaths)")
        }
    }

    /// Test that gepetto skill parses correctly with its complex structure
    @Test("Parse complex gepetto skill")
    func testGepettoSkillParsing() async throws {
        let skillsDir = Self.projectRoot.appendingPathComponent(".agents/skills")

        guard FileManager.default.fileExists(atPath: skillsDir.path) else {
            print("Skipping: .agents/skills not found at \(skillsDir.path)")
            return
        }

        let config = SkillConfiguration(searchRoots: [skillsDir])
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        let loaded = try await registry.activateSkill(named: "gepetto")

        // Verify gepetto specific content
        #expect(loaded.descriptor.name == "gepetto")
        #expect(loaded.descriptor.description.contains("implementation plans"))

        // Body should contain its workflow steps
        #expect(loaded.body.contains("CRITICAL: First Actions"))
        #expect(loaded.body.contains("Workflow"))
        #expect(loaded.body.contains("Step"))

        print("Gepetto body length: \(loaded.body.count) characters")
    }

    /// Test prompt builder with real skills
    @Test("Build prompt from real skills")
    func testPromptBuilderWithRealSkills() async throws {
        let skillsDir = Self.projectRoot.appendingPathComponent(".agents/skills")

        guard FileManager.default.fileExists(atPath: skillsDir.path) else {
            print("Skipping: .agents/skills not found at \(skillsDir.path)")
            return
        }

        let config = SkillConfiguration(searchRoots: [skillsDir])
        let registry = SkillRegistry(configuration: config)

        let skills = try await registry.discoverSkills()

        // Build available skills block
        let availableBlock = SkillPromptBuilder.buildAvailableSkillsBlock(skills)

        #expect(availableBlock.contains("<available_skills>"))
        #expect(availableBlock.contains("swift-concurrency-expert"))
        #expect(availableBlock.contains("gepetto"))

        print("Available skills prompt block:\n\(availableBlock.prefix(500))...")
    }

    /// Test reading reference files from a real skill
    @Test("Read reference files from swift-concurrency-expert")
    func testReadReferenceFiles() async throws {
        let skillsDir = Self.projectRoot.appendingPathComponent(".agents/skills")

        guard FileManager.default.fileExists(atPath: skillsDir.path) else {
            print("Skipping: .agents/skills not found at \(skillsDir.path)")
            return
        }

        let config = SkillConfiguration(searchRoots: [skillsDir])
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        // List references
        let refs = try await registry.listReferences(forSkill: "swift-concurrency-expert")

        if !refs.isEmpty {
            // Try to read the first reference
            let firstRef = refs[0]
            let content = try await registry.readResource(path: firstRef, forSkill: "swift-concurrency-expert")
            #expect(!content.isEmpty, "Reference file content should not be empty")
            print("Read reference '\(firstRef)': \(content.count) characters")
        }
    }
}
