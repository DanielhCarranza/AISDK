//
//  SkillDescriptor.swift
//  AISDK
//
//  Data models for Agent Skills Protocol skill metadata and loaded skills.
//  Based on the Agent Skills Specification from agentskills.io.
//

import Foundation

// MARK: - SkillScope

/// Scope of a discovered skill.
///
/// Skills can be discovered from two locations:
/// - **Project**: `.aidoctor/skills/` in the current workspace (takes precedence)
/// - **User**: `~/.aidoctor/skills/` for user-wide skills
public enum SkillScope: String, Sendable, Codable, Hashable {
    /// Project-level skill from `.aidoctor/skills/`
    case project

    /// User-level skill from `~/.aidoctor/skills/`
    case user
}

// MARK: - SkillDescriptor

/// Metadata and path information for a discovered skill.
///
/// A `SkillDescriptor` contains all information parsed from a skill's SKILL.md
/// frontmatter, plus path and scope information. This is used for:
/// - Injecting skill metadata into the system prompt
/// - Determining when to activate a skill
/// - Validating tool access permissions
///
/// ## Fields
/// Required fields from SKILL.md frontmatter:
/// - `name`: Skill identifier (1-64 chars, lowercase alphanumeric + hyphens)
/// - `description`: What the skill does and when to use it (1-1024 chars)
///
/// Optional fields:
/// - `license`: License information
/// - `compatibility`: Environment requirements
/// - `metadata`: Custom key-value pairs
/// - `allowedTools`: Tools the skill is permitted to use
///
/// ## Usage
/// ```swift
/// let descriptor = try SkillParser.parseMetadata(
///     from: skillMDPath,
///     scope: .project
/// )
/// print("Found skill: \(descriptor.namespacedName)")
/// ```
public struct SkillDescriptor: Sendable, Codable, Hashable, Identifiable {

    // MARK: - Required Fields

    /// Skill name from frontmatter.
    ///
    /// Must be 1-64 characters, lowercase alphanumeric with hyphens.
    /// Cannot start/end with hyphen or contain consecutive hyphens.
    public let name: String

    /// Description of what the skill does and when to use it.
    ///
    /// Must be 1-1024 characters. Should include keywords that help
    /// agents identify when this skill is relevant.
    public let description: String

    // MARK: - Optional Fields

    /// License information for the skill.
    ///
    /// Can be a license name (e.g., "MIT", "Apache-2.0") or reference
    /// to a bundled license file.
    public let license: String?

    /// Compatibility notes for the skill.
    ///
    /// Indicates environment requirements such as intended product,
    /// required system packages, or network access needs.
    /// Maximum 500 characters.
    public let compatibility: String?

    /// Custom metadata key-value pairs.
    ///
    /// Arbitrary metadata for client-specific properties not defined
    /// by the Agent Skills specification.
    public let metadata: [String: String]?

    /// Tools that the skill is pre-approved to use.
    ///
    /// A list of tool patterns (e.g., ["bash", "read_file"]).
    /// If present, the skill can only use tools in this list.
    /// If nil, no tool restrictions apply.
    public let allowedTools: [String]?

    // MARK: - Path Information

    /// Root directory of the skill.
    ///
    /// This is the parent directory containing SKILL.md.
    /// All relative paths in the skill are resolved from here.
    public let rootPath: URL

    /// Path to the SKILL.md file.
    public let skillMDPath: URL

    /// File modification time of SKILL.md.
    ///
    /// Used for cache invalidation - if mtime changes, the skill
    /// should be re-parsed.
    public let modificationDate: Date

    /// Scope of the skill (project or user).
    ///
    /// Project skills take precedence over user skills with the same name.
    public let scope: SkillScope

    // MARK: - Computed Properties

    /// The namespaced skill identifier.
    ///
    /// Format: `skill::<name>`
    /// Used when the model references a skill for activation.
    public var namespacedName: String {
        "skill::\(name)"
    }

    /// Unique identifier combining scope and name.
    ///
    /// Format: `<scope>:<name>` (e.g., "project:my-skill")
    public var id: String {
        "\(scope.rawValue):\(name)"
    }

    /// Whether the skill has a scripts/ directory.
    public var hasScripts: Bool {
        let scriptsPath = rootPath.appendingPathComponent("scripts")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: scriptsPath.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Whether the skill has a references/ directory.
    public var hasReferences: Bool {
        let referencesPath = rootPath.appendingPathComponent("references")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: referencesPath.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Whether the skill has an assets/ directory.
    public var hasAssets: Bool {
        let assetsPath = rootPath.appendingPathComponent("assets")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: assetsPath.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    // MARK: - Initialization

    /// Creates a new skill descriptor.
    ///
    /// - Parameters:
    ///   - name: Skill name (validated separately)
    ///   - description: Skill description
    ///   - license: Optional license
    ///   - compatibility: Optional compatibility notes
    ///   - metadata: Optional custom metadata
    ///   - allowedTools: Optional tool restrictions
    ///   - rootPath: Skill root directory
    ///   - skillMDPath: Path to SKILL.md
    ///   - modificationDate: File modification time
    ///   - scope: Project or user scope
    public init(
        name: String,
        description: String,
        license: String? = nil,
        compatibility: String? = nil,
        metadata: [String: String]? = nil,
        allowedTools: [String]? = nil,
        rootPath: URL,
        skillMDPath: URL,
        modificationDate: Date,
        scope: SkillScope
    ) {
        self.name = name
        self.description = description
        self.license = license
        self.compatibility = compatibility
        self.metadata = metadata
        self.allowedTools = allowedTools
        self.rootPath = rootPath
        self.skillMDPath = skillMDPath
        self.modificationDate = modificationDate
        self.scope = scope
    }
}

// MARK: - LoadedSkill

/// A skill with its full body content loaded.
///
/// Created when a skill is activated. Contains the full Markdown body
/// from SKILL.md plus cached lists of available scripts and references.
///
/// ## Usage
/// ```swift
/// let loaded = try await registry.activateSkill(named: "my-skill")
/// print("Instructions: \(loaded.body)")
/// print("Available scripts: \(loaded.scriptPaths)")
/// ```
public struct LoadedSkill: Sendable {

    /// The skill's metadata descriptor.
    public let descriptor: SkillDescriptor

    /// Full Markdown body content (after frontmatter).
    ///
    /// This contains the skill's instructions, usage guidelines,
    /// and any other content the agent needs to execute the skill.
    public let body: String

    /// Relative paths to scripts in the scripts/ directory.
    ///
    /// Only includes files directly in scripts/, not subdirectories.
    /// Paths are relative to the skill root (e.g., "scripts/run.sh").
    public let scriptPaths: [String]

    /// Relative paths to reference files in the references/ directory.
    ///
    /// Only includes files directly in references/, not subdirectories.
    /// Paths are relative to the skill root.
    public let referencePaths: [String]

    /// Relative paths to asset files in the assets/ directory.
    ///
    /// Only includes files directly in assets/, not subdirectories.
    /// Paths are relative to the skill root.
    public let assetPaths: [String]

    // MARK: - Initialization

    /// Creates a loaded skill.
    ///
    /// - Parameters:
    ///   - descriptor: Skill metadata
    ///   - body: Markdown body content
    ///   - scriptPaths: Available script paths
    ///   - referencePaths: Available reference paths
    ///   - assetPaths: Available asset paths
    public init(
        descriptor: SkillDescriptor,
        body: String,
        scriptPaths: [String] = [],
        referencePaths: [String] = [],
        assetPaths: [String] = []
    ) {
        self.descriptor = descriptor
        self.body = body
        self.scriptPaths = scriptPaths
        self.referencePaths = referencePaths
        self.assetPaths = assetPaths
    }
}

// MARK: - SkillValidationResult

/// Result of validating a skill descriptor.
///
/// Contains both errors (which prevent the skill from loading) and
/// warnings (which are logged but don't prevent loading).
public struct SkillValidationResult: Sendable {

    /// Whether the skill passed validation.
    ///
    /// A skill is valid if it has no errors. Warnings don't affect validity.
    public let isValid: Bool

    /// Validation errors that prevent the skill from loading.
    public let errors: [SkillError]

    /// Warnings that don't prevent loading but should be noted.
    public let warnings: [String]

    /// Creates a validation result.
    public init(isValid: Bool, errors: [SkillError] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }

    /// A successful validation with no errors or warnings.
    public static var success: SkillValidationResult {
        SkillValidationResult(isValid: true)
    }

    /// Creates a failed validation with errors.
    public static func failure(_ errors: [SkillError]) -> SkillValidationResult {
        SkillValidationResult(isValid: false, errors: errors)
    }

    /// Creates a successful validation with warnings.
    public static func successWithWarnings(_ warnings: [String]) -> SkillValidationResult {
        SkillValidationResult(isValid: true, warnings: warnings)
    }
}
