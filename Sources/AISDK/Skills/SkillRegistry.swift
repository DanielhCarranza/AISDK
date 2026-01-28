//
//  SkillRegistry.swift
//  AISDK
//
//  Actor-based registry for skill discovery, caching, and activation.
//  Manages the lifecycle of skills from discovery to execution.
//

import Foundation

// MARK: - SkillRegistry

/// Actor-based registry for skill management.
///
/// The `SkillRegistry` handles:
/// - **Discovery**: Scanning directories for skills
/// - **Validation**: Checking skills against the protocol
/// - **Caching**: Storing parsed skill metadata
/// - **Activation**: Loading skill bodies on demand
/// - **Resource Access**: Sandboxed file reading
///
/// ## Thread Safety
/// As an actor, all operations are serialized. Concurrent access from
/// multiple agent tasks is safe.
///
/// ## Usage
/// ```swift
/// let registry = SkillRegistry(configuration: .default)
///
/// // Discover all skills
/// let skills = try await registry.discoverSkills()
///
/// // Activate a skill
/// let loaded = try await registry.activateSkill(named: "my-skill")
///
/// // Read a resource
/// let content = try await registry.readResource(
///     path: "references/guide.md",
///     forSkill: "my-skill"
/// )
/// ```
public actor SkillRegistry {

    // MARK: - State

    /// Configuration for skill operations
    private let configuration: SkillConfiguration

    /// Cached skill descriptors by name
    private var cache: [String: SkillDescriptor] = [:]

    /// Loaded skill bodies by name
    private var loadedSkills: [String: LoadedSkill] = [:]

    /// Whether discovery has been performed
    private var hasDiscovered: Bool = false

    // MARK: - Initialization

    /// Creates a new skill registry.
    ///
    /// - Parameter configuration: Configuration for skill operations
    public init(configuration: SkillConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Discovery

    /// Discover all skills from configured search roots.
    ///
    /// Scans each search root for skill directories (containing SKILL.md),
    /// parses metadata, validates, and caches valid skills.
    ///
    /// Project skills take precedence over user skills with the same name.
    ///
    /// - Returns: Array of valid skill descriptors
    /// - Note: Results are cached; subsequent calls return cached data
    public func discoverSkills() async throws -> [SkillDescriptor] {
        guard configuration.enabled else {
            return []
        }

        // Return cached results if already discovered
        if hasDiscovered {
            return Array(cache.values)
        }

        var discovered: [String: SkillDescriptor] = [:]

        for (index, searchRoot) in configuration.searchRoots.enumerated() {
            let scope: SkillScope = index == 0 ? .project : .user

            // Skip non-existent roots
            let fm = FileManager.default
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: searchRoot.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            // Scan for skill directories
            do {
                let contents = try fm.contentsOfDirectory(
                    at: searchRoot,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )

                for itemURL in contents {
                    // Check if it's a directory
                    var isDirCheck: ObjCBool = false
                    guard fm.fileExists(atPath: itemURL.path, isDirectory: &isDirCheck),
                          isDirCheck.boolValue else {
                        continue
                    }

                    // Look for SKILL.md
                    guard let skillMDPath = SkillParser.findSkillMD(in: itemURL) else {
                        continue
                    }

                    do {
                        // Parse metadata
                        let descriptor = try SkillParser.parseMetadata(
                            from: skillMDPath,
                            scope: scope
                        )

                        // Validate if enabled
                        if configuration.enableValidation {
                            let validationResult = SkillValidator.validate(
                                descriptor,
                                configuration: configuration
                            )

                            // Log warnings
                            for warning in validationResult.warnings {
                                print("[AISDK] Skill '\(descriptor.name)' warning: \(warning)")
                            }

                            // Skip invalid skills
                            if !validationResult.isValid {
                                for error in validationResult.errors {
                                    print("[AISDK] Skill '\(descriptor.name)' validation error: \(error.localizedDescription ?? String(describing: error))")
                                }
                                continue
                            }
                        }

                        // Only add if not already discovered (project takes precedence)
                        if discovered[descriptor.name] == nil {
                            discovered[descriptor.name] = descriptor
                        }
                    } catch {
                        // Log and skip invalid skills
                        print("[AISDK] Failed to parse skill at '\(itemURL.path)': \(error.localizedDescription)")
                    }
                }
            } catch {
                // Log and continue with other roots
                print("[AISDK] Failed to scan search root '\(searchRoot.path)': \(error.localizedDescription)")
            }
        }

        cache = discovered
        hasDiscovered = true

        return Array(cache.values)
    }

    /// Force re-discovery of skills.
    ///
    /// Clears caches and re-scans all search roots.
    ///
    /// - Returns: Array of freshly discovered skill descriptors
    public func refresh() async throws -> [SkillDescriptor] {
        cache.removeAll()
        loadedSkills.removeAll()
        hasDiscovered = false
        return try await discoverSkills()
    }

    // MARK: - Skill Access

    /// Get metadata for all discovered skills.
    ///
    /// Use this for injecting skill metadata into the system prompt.
    ///
    /// - Returns: Array of skill descriptors
    public func getSkillsMetadata() async throws -> [SkillDescriptor] {
        if !hasDiscovered {
            _ = try await discoverSkills()
        }
        return Array(cache.values).sorted { $0.name < $1.name }
    }

    /// Get a skill descriptor by name.
    ///
    /// - Parameter name: Skill name (without `skill::` prefix)
    /// - Returns: Skill descriptor, or nil if not found
    public func getSkill(named name: String) async -> SkillDescriptor? {
        return cache[name]
    }

    /// Check if a skill exists.
    ///
    /// - Parameter name: Skill name
    /// - Returns: True if the skill is discovered
    public func hasSkill(named name: String) async -> Bool {
        return cache[name] != nil
    }

    // MARK: - Activation

    /// Activate a skill by loading its full body content.
    ///
    /// Loads the SKILL.md body and scans for available scripts,
    /// references, and assets.
    ///
    /// - Parameter name: Skill name (without `skill::` prefix)
    /// - Returns: Loaded skill with body content
    /// - Throws: `SkillError.skillNotFound` if skill doesn't exist
    public func activateSkill(named name: String) async throws -> LoadedSkill {
        // Return cached loaded skill if available
        if let loaded = loadedSkills[name] {
            return loaded
        }

        // Find descriptor
        guard let descriptor = cache[name] else {
            throw SkillError.skillNotFound(name: name)
        }

        // Load full content
        let loaded = try SkillParser.loadBody(for: descriptor)

        // Cache the loaded skill
        loadedSkills[name] = loaded

        return loaded
    }

    /// Deactivate a skill (remove from loaded cache).
    ///
    /// - Parameter name: Skill name
    public func deactivateSkill(named name: String) async {
        loadedSkills.removeValue(forKey: name)
    }

    /// Check if a skill is currently activated.
    ///
    /// - Parameter name: Skill name
    /// - Returns: True if the skill body is loaded
    public func isActivated(named name: String) async -> Bool {
        return loadedSkills[name] != nil
    }

    /// Get all currently activated skills.
    ///
    /// - Returns: Array of loaded skills
    public func getActivatedSkills() async -> [LoadedSkill] {
        return Array(loadedSkills.values)
    }

    // MARK: - Resource Access

    /// Read a file from a skill's directory (sandboxed).
    ///
    /// Validates that the path doesn't escape the skill root.
    ///
    /// - Parameters:
    ///   - path: Relative path within the skill (e.g., "scripts/run.sh")
    ///   - skillName: Name of the skill
    /// - Returns: File contents as string
    /// - Throws: `SkillError.pathTraversal` or `SkillError.fileReadError`
    public func readResource(
        path: String,
        forSkill skillName: String
    ) async throws -> String {
        guard let descriptor = cache[skillName] else {
            throw SkillError.skillNotFound(name: skillName)
        }

        // Validate path (throws on traversal attempt)
        let resolvedPath = try SkillValidator.validatePath(
            path,
            skillRoot: descriptor.rootPath
        )

        // Read file
        do {
            return try String(contentsOf: resolvedPath, encoding: .utf8)
        } catch {
            throw SkillError.fileReadError(path: resolvedPath, underlying: error)
        }
    }

    /// List scripts available in a skill.
    ///
    /// - Parameter skillName: Name of the skill
    /// - Returns: Array of script paths relative to skill root
    public func listScripts(forSkill skillName: String) async throws -> [String] {
        // If skill is already loaded, use cached data
        if let loaded = loadedSkills[skillName] {
            return loaded.scriptPaths
        }

        guard let descriptor = cache[skillName] else {
            throw SkillError.skillNotFound(name: skillName)
        }

        let scriptsDir = descriptor.rootPath.appendingPathComponent("scripts")
        return listFilesInDirectory(scriptsDir, prefix: "scripts")
    }

    /// List references available in a skill.
    ///
    /// - Parameter skillName: Name of the skill
    /// - Returns: Array of reference paths relative to skill root
    public func listReferences(forSkill skillName: String) async throws -> [String] {
        if let loaded = loadedSkills[skillName] {
            return loaded.referencePaths
        }

        guard let descriptor = cache[skillName] else {
            throw SkillError.skillNotFound(name: skillName)
        }

        let refsDir = descriptor.rootPath.appendingPathComponent("references")
        return listFilesInDirectory(refsDir, prefix: "references")
    }

    // MARK: - Cache Management

    /// Check if a skill's cache is stale (mtime changed).
    ///
    /// - Parameter descriptor: Skill descriptor to check
    /// - Returns: True if the SKILL.md file has been modified
    public func isStale(_ descriptor: SkillDescriptor) async -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: descriptor.skillMDPath.path
            )
            guard let currentMTime = attributes[.modificationDate] as? Date else {
                return false
            }
            return currentMTime > descriptor.modificationDate
        } catch {
            // If we can't read attributes, assume stale
            return true
        }
    }

    /// Clear all caches.
    ///
    /// Forces re-discovery on next access.
    public func clearCaches() async {
        cache.removeAll()
        loadedSkills.removeAll()
        hasDiscovered = false
    }

    // MARK: - Private Helpers

    /// List files in a directory with a prefix.
    private func listFilesInDirectory(_ directory: URL, prefix: String) -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else {
            return []
        }

        do {
            let contents = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            return contents.compactMap { url -> String? in
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir),
                      !isDir.boolValue else {
                    return nil
                }
                return "\(prefix)/\(url.lastPathComponent)"
            }.sorted()
        } catch {
            return []
        }
    }
}

// MARK: - Convenience Extensions

extension SkillRegistry {

    /// Create a registry with a single search root (for testing).
    ///
    /// - Parameter searchRoot: Single directory to search
    /// - Returns: Configured registry
    public static func forTesting(searchRoot: URL) -> SkillRegistry {
        SkillRegistry(configuration: .forTesting(searchRoot: searchRoot))
    }

    /// Discover and return skill names.
    ///
    /// - Returns: Sorted array of skill names
    public func discoverSkillNames() async throws -> [String] {
        let skills = try await discoverSkills()
        return skills.map(\.name).sorted()
    }
}
