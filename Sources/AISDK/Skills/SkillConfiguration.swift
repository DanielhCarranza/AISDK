//
//  SkillConfiguration.swift
//  AISDK
//
//  Configuration for Agent Skills Protocol discovery and loading.
//  Specifies search paths, size limits, and validation settings.
//

import Foundation

// MARK: - SkillConfiguration

/// Configuration for skill discovery and loading.
///
/// Controls how skills are discovered from the filesystem, validated,
/// and loaded into agent context. Use the default configuration for
/// standard behavior, or customize for specific requirements.
///
/// ## Default Behavior
/// - Search paths: `.aidoctor/skills/` (project) and `~/.aidoctor/skills/` (user)
/// - Validation enabled
/// - Max file size: 32KB
/// - Max lines: 500
///
/// ## Usage
/// ```swift
/// // Use defaults
/// let agent = AIAgentActor(
///     model: myModel,
///     skillConfiguration: .default
/// )
///
/// // Custom configuration
/// let config = SkillConfiguration(
///     searchRoots: [customPath],
///     maxSkillSizeBytes: 64 * 1024
/// )
/// let agent = AIAgentActor(
///     model: myModel,
///     skillConfiguration: config
/// )
/// ```
public struct SkillConfiguration: Sendable, Codable, Hashable {

    // MARK: - Properties

    /// Search paths for skill directories (ordered by priority).
    ///
    /// Skills are discovered by scanning these directories for subdirectories
    /// containing SKILL.md files. Earlier paths take precedence over later
    /// paths when skills have the same name.
    ///
    /// Default: `[.aidoctor/skills, ~/.aidoctor/skills]`
    public let searchRoots: [URL]

    /// Whether to validate discovered skills.
    ///
    /// When enabled, skills are validated against the Agent Skills Protocol:
    /// - Name format (lowercase, alphanumeric, hyphens)
    /// - Size limits
    /// - Directory name matching
    ///
    /// Invalid skills are skipped with a warning.
    public let enableValidation: Bool

    /// Maximum SKILL.md file size in bytes.
    ///
    /// Skills exceeding this limit are skipped during discovery.
    /// Default: 32KB (32 * 1024)
    public let maxSkillSizeBytes: Int

    /// Maximum number of lines in SKILL.md.
    ///
    /// Skills exceeding this limit are skipped during discovery.
    /// Default: 500 lines
    public let maxSkillLines: Int

    /// Whether the skills feature is enabled.
    ///
    /// When disabled, no skills are discovered or loaded.
    /// Useful for feature flags or testing.
    public let enabled: Bool

    /// Whether to treat unknown frontmatter keys as errors.
    ///
    /// When false (default), unknown keys generate warnings.
    /// When true, unknown keys cause validation failure.
    public let strictFrontmatter: Bool

    // MARK: - Initialization

    /// Creates a skill configuration.
    ///
    /// - Parameters:
    ///   - searchRoots: Directories to search for skills (default: standard paths)
    ///   - enableValidation: Whether to validate skills (default: true)
    ///   - maxSkillSizeBytes: Maximum SKILL.md size (default: 32KB)
    ///   - maxSkillLines: Maximum line count (default: 500)
    ///   - enabled: Whether skills are enabled (default: true)
    ///   - strictFrontmatter: Treat unknown keys as errors (default: false)
    public init(
        searchRoots: [URL]? = nil,
        enableValidation: Bool = true,
        maxSkillSizeBytes: Int = 32 * 1024,
        maxSkillLines: Int = 500,
        enabled: Bool = true,
        strictFrontmatter: Bool = false
    ) {
        self.searchRoots = searchRoots ?? Self.defaultSearchRoots
        self.enableValidation = enableValidation
        self.maxSkillSizeBytes = maxSkillSizeBytes
        self.maxSkillLines = maxSkillLines
        self.enabled = enabled
        self.strictFrontmatter = strictFrontmatter
    }

    // MARK: - Default Configuration

    /// Default search roots for skill discovery.
    ///
    /// 1. `.aidoctor/skills/` - Project-level skills (current directory)
    /// 2. `~/.aidoctor/skills/` - User-level skills (home directory, macOS only)
    public static var defaultSearchRoots: [URL] {
        var roots: [URL] = [
            URL(fileURLWithPath: ".aidoctor/skills", isDirectory: true)
        ]
        #if os(macOS)
        roots.append(
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".aidoctor/skills", isDirectory: true)
        )
        #endif
        return roots
    }

    /// Default configuration with standard settings.
    ///
    /// - Search paths: `.aidoctor/skills/`, `~/.aidoctor/skills/`
    /// - Validation: enabled
    /// - Max size: 32KB
    /// - Max lines: 500
    /// - Skills: enabled
    public static var `default`: SkillConfiguration {
        SkillConfiguration()
    }

    /// Configuration with skills disabled.
    ///
    /// Use this to create an agent without skills support.
    public static var disabled: SkillConfiguration {
        SkillConfiguration(enabled: false)
    }

    /// Configuration for testing with custom search root.
    ///
    /// - Parameter testRoot: Single directory to search for skills
    /// - Returns: Configuration searching only the test root
    public static func forTesting(searchRoot testRoot: URL) -> SkillConfiguration {
        SkillConfiguration(searchRoots: [testRoot])
    }
}

// MARK: - Codable

extension SkillConfiguration {

    enum CodingKeys: String, CodingKey {
        case searchRoots
        case enableValidation
        case maxSkillSizeBytes
        case maxSkillLines
        case enabled
        case strictFrontmatter
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode searchRoots as strings and convert to URLs
        if let rootStrings = try container.decodeIfPresent([String].self, forKey: .searchRoots) {
            self.searchRoots = rootStrings.map { URL(fileURLWithPath: $0, isDirectory: true) }
        } else {
            self.searchRoots = Self.defaultSearchRoots
        }

        self.enableValidation = try container.decodeIfPresent(Bool.self, forKey: .enableValidation) ?? true
        self.maxSkillSizeBytes = try container.decodeIfPresent(Int.self, forKey: .maxSkillSizeBytes) ?? (32 * 1024)
        self.maxSkillLines = try container.decodeIfPresent(Int.self, forKey: .maxSkillLines) ?? 500
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.strictFrontmatter = try container.decodeIfPresent(Bool.self, forKey: .strictFrontmatter) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode searchRoots as strings
        try container.encode(searchRoots.map { $0.path }, forKey: .searchRoots)
        try container.encode(enableValidation, forKey: .enableValidation)
        try container.encode(maxSkillSizeBytes, forKey: .maxSkillSizeBytes)
        try container.encode(maxSkillLines, forKey: .maxSkillLines)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(strictFrontmatter, forKey: .strictFrontmatter)
    }
}

// MARK: - CustomStringConvertible

extension SkillConfiguration: CustomStringConvertible {

    public var description: String {
        """
        SkillConfiguration(
            searchRoots: \(searchRoots.map { $0.path }),
            enableValidation: \(enableValidation),
            maxSkillSizeBytes: \(maxSkillSizeBytes),
            maxSkillLines: \(maxSkillLines),
            enabled: \(enabled),
            strictFrontmatter: \(strictFrontmatter)
        )
        """
    }
}
