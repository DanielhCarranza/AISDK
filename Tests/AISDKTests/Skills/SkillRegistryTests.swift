//
//  SkillRegistryTests.swift
//  AISDKTests
//
//  Tests for skill discovery, caching, and activation.
//

import XCTest
@testable import AISDK

final class SkillRegistryTests: XCTestCase {

    // MARK: - Test Fixtures

    private var fixturesURL: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Skills/
            .deletingLastPathComponent()  // AISDKTests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Skills")
    }

    // MARK: - Discovery Tests

    func testDiscoverSkills_FindsValidSkills() async throws {
        let config = SkillConfiguration(
            searchRoots: [fixturesURL],
            enableValidation: true,
            maxSkillSizeBytes: 32 * 1024,
            maxSkillLines: 500,
            enabled: true,
            strictFrontmatter: false
        )

        let registry = SkillRegistry(configuration: config)
        let skills = try await registry.discoverSkills()

        // Should find project-indexer and test-runner, skip malformed and invalid-name
        let names = skills.map(\.name)
        XCTAssertTrue(names.contains("project-indexer"))
        XCTAssertTrue(names.contains("test-runner"))
        XCTAssertFalse(names.contains("malformed-skill"))
        XCTAssertFalse(names.contains("Invalid_Name_With_Uppercase"))
    }

    func testDiscoverSkills_CachesResults() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        // First call
        let skills1 = try await registry.discoverSkills()
        // Second call should return cached
        let skills2 = try await registry.discoverSkills()

        XCTAssertEqual(skills1.count, skills2.count)
        XCTAssertEqual(Set(skills1.map(\.name)), Set(skills2.map(\.name)))
    }

    func testDiscoverSkills_DisabledReturnsEmpty() async throws {
        let config = SkillConfiguration(
            searchRoots: [fixturesURL],
            enableValidation: true,
            maxSkillSizeBytes: 32 * 1024,
            maxSkillLines: 500,
            enabled: false,  // Disabled
            strictFrontmatter: false
        )

        let registry = SkillRegistry(configuration: config)
        let skills = try await registry.discoverSkills()

        XCTAssertTrue(skills.isEmpty)
    }

    func testDiscoverSkills_NonexistentRootSkipped() async throws {
        let config = SkillConfiguration(
            searchRoots: [
                URL(fileURLWithPath: "/nonexistent/path"),
                fixturesURL
            ],
            enableValidation: true,
            maxSkillSizeBytes: 32 * 1024,
            maxSkillLines: 500,
            enabled: true,
            strictFrontmatter: false
        )

        let registry = SkillRegistry(configuration: config)
        let skills = try await registry.discoverSkills()

        // Should still find skills from valid root
        XCTAssertFalse(skills.isEmpty)
    }

    // MARK: - Refresh Tests

    func testRefresh_ClearsCache() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        // Initial discovery
        _ = try await registry.discoverSkills()

        // Refresh should work
        let refreshed = try await registry.refresh()
        XCTAssertFalse(refreshed.isEmpty)
    }

    // MARK: - Skill Access Tests

    func testGetSkill_Exists() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()
        let skill = await registry.getSkill(named: "project-indexer")

        XCTAssertNotNil(skill)
        XCTAssertEqual(skill?.name, "project-indexer")
    }

    func testGetSkill_NotExists() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()
        let skill = await registry.getSkill(named: "nonexistent-skill")

        XCTAssertNil(skill)
    }

    func testHasSkill() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        let hasProjectIndexer = await registry.hasSkill(named: "project-indexer")
        let hasNonexistent = await registry.hasSkill(named: "nonexistent")

        XCTAssertTrue(hasProjectIndexer)
        XCTAssertFalse(hasNonexistent)
    }

    // MARK: - Activation Tests

    func testActivateSkill_LoadsBody() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()
        let loaded = try await registry.activateSkill(named: "project-indexer")

        XCTAssertEqual(loaded.descriptor.name, "project-indexer")
        XCTAssertFalse(loaded.body.isEmpty)
        XCTAssertTrue(loaded.body.contains("Project Indexer"))
    }

    func testActivateSkill_CachesLoadedSkill() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        // First activation
        let loaded1 = try await registry.activateSkill(named: "project-indexer")
        // Second activation should return cached
        let loaded2 = try await registry.activateSkill(named: "project-indexer")

        XCTAssertEqual(loaded1.body, loaded2.body)
    }

    func testActivateSkill_NotFound() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        do {
            _ = try await registry.activateSkill(named: "nonexistent")
            XCTFail("Expected skillNotFound error")
        } catch {
            guard case SkillError.skillNotFound(let name) = error else {
                XCTFail("Expected skillNotFound error, got \(error)")
                return
            }
            XCTAssertEqual(name, "nonexistent")
        }
    }

    func testDeactivateSkill() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()
        _ = try await registry.activateSkill(named: "project-indexer")

        let isActivatedBefore = await registry.isActivated(named: "project-indexer")
        XCTAssertTrue(isActivatedBefore)

        await registry.deactivateSkill(named: "project-indexer")

        let isActivatedAfter = await registry.isActivated(named: "project-indexer")
        XCTAssertFalse(isActivatedAfter)
    }

    func testGetActivatedSkills() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()
        _ = try await registry.activateSkill(named: "project-indexer")
        _ = try await registry.activateSkill(named: "test-runner")

        let activated = await registry.getActivatedSkills()
        let names = activated.map(\.descriptor.name)

        XCTAssertEqual(names.count, 2)
        XCTAssertTrue(names.contains("project-indexer"))
        XCTAssertTrue(names.contains("test-runner"))
    }

    // MARK: - Resource Access Tests

    func testReadResource_ValidPath() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        let content = try await registry.readResource(
            path: "references/guide.md",
            forSkill: "project-indexer"
        )

        XCTAssertFalse(content.isEmpty)
        XCTAssertTrue(content.contains("Guide"))
    }

    func testReadResource_PathTraversal() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        do {
            _ = try await registry.readResource(
                path: "../test-runner/SKILL.md",
                forSkill: "project-indexer"
            )
            XCTFail("Expected pathTraversal error")
        } catch {
            guard case SkillError.pathTraversal = error else {
                XCTFail("Expected pathTraversal error, got \(error)")
                return
            }
        }
    }

    func testReadResource_SkillNotFound() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()

        do {
            _ = try await registry.readResource(
                path: "scripts/run.sh",
                forSkill: "nonexistent"
            )
            XCTFail("Expected skillNotFound error")
        } catch {
            guard case SkillError.skillNotFound = error else {
                XCTFail("Expected skillNotFound error, got \(error)")
                return
            }
        }
    }

    // MARK: - Script/Reference Listing Tests

    func testListScripts() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()
        let scripts = try await registry.listScripts(forSkill: "project-indexer")

        XCTAssertFalse(scripts.isEmpty)
        XCTAssertTrue(scripts.contains { $0.contains("list_files.sh") })
    }

    func testListReferences() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        _ = try await registry.discoverSkills()
        let refs = try await registry.listReferences(forSkill: "project-indexer")

        XCTAssertFalse(refs.isEmpty)
        XCTAssertTrue(refs.contains { $0.contains("guide.md") })
    }

    // MARK: - Cache Management Tests

    func testClearCaches() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        // Discovery and activation
        _ = try await registry.discoverSkills()
        _ = try await registry.activateSkill(named: "project-indexer")

        // Clear caches
        await registry.clearCaches()

        // Should need to rediscover
        let hasSkill = await registry.hasSkill(named: "project-indexer")
        XCTAssertFalse(hasSkill)  // Cache was cleared
    }

    // MARK: - Skill Names Convenience

    func testDiscoverSkillNames() async throws {
        let config = SkillConfiguration.forTesting(searchRoot: fixturesURL)
        let registry = SkillRegistry(configuration: config)

        let names = try await registry.discoverSkillNames()

        XCTAssertTrue(names.contains("project-indexer"))
        XCTAssertTrue(names.contains("test-runner"))
        XCTAssertEqual(names, names.sorted())  // Should be sorted
    }
}
