//
//  SkillParser.swift
//  AISDK
//
//  Parser for SKILL.md files with YAML frontmatter and Markdown body.
//  Implements the Agent Skills Protocol specification.
//

import Foundation

// MARK: - SkillParser

/// Parser for SKILL.md files.
///
/// Handles parsing of skill files according to the Agent Skills Protocol:
/// - YAML frontmatter between `---` delimiters
/// - Markdown body after frontmatter
///
/// ## Frontmatter Fields
/// Required:
/// - `name`: Skill identifier
/// - `description`: What the skill does
///
/// Optional:
/// - `license`: License information
/// - `compatibility`: Environment requirements
/// - `metadata`: Custom key-value pairs
/// - `allowed-tools`: Space-delimited tool list
///
/// ## Usage
/// ```swift
/// // Parse metadata only (for discovery)
/// let descriptor = try SkillParser.parseMetadata(from: skillMDPath, scope: .project)
///
/// // Load full content (for activation)
/// let loaded = try SkillParser.loadBody(for: descriptor)
/// ```
public struct SkillParser: Sendable {

    // MARK: - Constants

    /// Allowed frontmatter field keys per Agent Skills Protocol
    public static let allowedFrontmatterKeys: Set<String> = [
        "name",
        "description",
        "license",
        "compatibility",
        "metadata",
        "allowed-tools"
    ]

    /// Frontmatter delimiter
    private static let frontmatterDelimiter = "---"

    // MARK: - Metadata Parsing

    /// Parse a SKILL.md file into a skill descriptor (metadata only).
    ///
    /// This method is optimized for discovery - it reads the file once and
    /// extracts only the frontmatter metadata. The body is not included.
    ///
    /// - Parameters:
    ///   - url: Path to the SKILL.md file
    ///   - scope: Whether this is a project or user skill
    /// - Returns: Parsed skill descriptor
    /// - Throws: `SkillError` for parsing failures
    public static func parseMetadata(from url: URL, scope: SkillScope) throws -> SkillDescriptor {
        // Read file content
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SkillError.fileReadError(path: url, underlying: error)
        }

        // Get file modification date
        let modificationDate: Date
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            modificationDate = attributes[.modificationDate] as? Date ?? Date()
        } catch {
            modificationDate = Date()
        }

        // Extract frontmatter
        let (frontmatter, _) = try extractFrontmatter(content)

        // Parse required fields
        guard let name = frontmatter["name"] else {
            throw SkillError.missingRequiredField(field: "name")
        }
        let nameString = try parseStringField(name, fieldName: "name")

        guard let description = frontmatter["description"] else {
            throw SkillError.missingRequiredField(field: "description")
        }
        let descriptionString = try parseStringField(description, fieldName: "description")

        // Parse optional fields
        let license = try parseOptionalStringField(frontmatter["license"], fieldName: "license")
        let compatibility = try parseOptionalStringField(frontmatter["compatibility"], fieldName: "compatibility")
        let metadata = try parseMetadataField(frontmatter["metadata"])
        let allowedTools = try parseAllowedTools(frontmatter["allowed-tools"])

        // Determine root path (parent of SKILL.md)
        let rootPath = url.deletingLastPathComponent()

        return SkillDescriptor(
            name: nameString,
            description: descriptionString,
            license: license,
            compatibility: compatibility,
            metadata: metadata,
            allowedTools: allowedTools,
            rootPath: rootPath,
            skillMDPath: url,
            modificationDate: modificationDate,
            scope: scope
        )
    }

    /// Find SKILL.md in a skill directory.
    ///
    /// Prefers `SKILL.md` (uppercase) but accepts `skill.md` (lowercase).
    ///
    /// - Parameter skillDir: Path to the skill directory
    /// - Returns: Path to SKILL.md, or nil if not found
    public static func findSkillMD(in skillDir: URL) -> URL? {
        for filename in ["SKILL.md", "skill.md"] {
            let path = skillDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }

    // MARK: - Full Content Loading

    /// Load a skill with its full body content.
    ///
    /// This method reads the SKILL.md body and scans for available
    /// scripts, references, and assets.
    ///
    /// - Parameter descriptor: Previously parsed skill descriptor
    /// - Returns: Loaded skill with body content
    /// - Throws: `SkillError` for file access failures
    public static func loadBody(for descriptor: SkillDescriptor) throws -> LoadedSkill {
        // Read file content
        let content: String
        do {
            content = try String(contentsOf: descriptor.skillMDPath, encoding: .utf8)
        } catch {
            throw SkillError.fileReadError(path: descriptor.skillMDPath, underlying: error)
        }

        // Extract body
        let (_, body) = try extractFrontmatter(content)

        // Scan for scripts
        let scriptPaths = listFiles(
            in: descriptor.rootPath.appendingPathComponent("scripts")
        )

        // Scan for references
        let referencePaths = listFiles(
            in: descriptor.rootPath.appendingPathComponent("references")
        )

        // Scan for assets
        let assetPaths = listFiles(
            in: descriptor.rootPath.appendingPathComponent("assets")
        )

        return LoadedSkill(
            descriptor: descriptor,
            body: body,
            scriptPaths: scriptPaths,
            referencePaths: referencePaths,
            assetPaths: assetPaths
        )
    }

    // MARK: - Frontmatter Extraction

    /// Extract YAML frontmatter from SKILL.md content.
    ///
    /// The frontmatter must be at the start of the file, delimited by `---`.
    ///
    /// - Parameter content: Full file content
    /// - Returns: Tuple of (frontmatter dictionary, body string)
    /// - Throws: `SkillError` for parsing failures
    public static func extractFrontmatter(_ content: String) throws -> ([String: Any], String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must start with ---
        guard trimmed.hasPrefix(frontmatterDelimiter) else {
            throw SkillError.invalidFrontmatter(reason: "SKILL.md must start with '---'")
        }

        // Find closing ---
        let afterOpening = trimmed.dropFirst(frontmatterDelimiter.count)
        guard let closingRange = afterOpening.range(of: "\n\(frontmatterDelimiter)") else {
            throw SkillError.invalidFrontmatter(reason: "Frontmatter not properly closed with '---'")
        }

        // Extract frontmatter string
        let frontmatterString = String(afterOpening[..<closingRange.lowerBound])

        // Extract body (everything after closing ---)
        let afterClosing = afterOpening[closingRange.upperBound...]
        let body = String(afterClosing).trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse YAML
        let frontmatter = try parseYAML(frontmatterString)

        return (frontmatter, body)
    }

    // MARK: - YAML Parsing

    /// Parse YAML frontmatter string into a dictionary.
    ///
    /// Uses a simple parser for the subset of YAML needed by SKILL.md.
    /// Supports string values, maps, and the metadata field.
    ///
    /// - Parameter yaml: YAML string to parse
    /// - Returns: Parsed dictionary
    /// - Throws: `SkillError` for invalid YAML
    private static func parseYAML(_ yaml: String) throws -> [String: Any] {
        var result: [String: Any] = [:]
        let lines = yaml.components(separatedBy: .newlines)

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                i += 1
                continue
            }

            // Check for key-value pair
            guard let colonIndex = trimmedLine.firstIndex(of: ":") else {
                i += 1
                continue
            }

            let key = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let valueAfterColon = String(trimmedLine[trimmedLine.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)

            // Check if this is a nested map (metadata field)
            if valueAfterColon.isEmpty && key == "metadata" {
                // Parse nested map
                var nestedMap: [String: String] = [:]
                i += 1
                while i < lines.count {
                    let nestedLine = lines[i]
                    let nestedTrimmed = nestedLine.trimmingCharacters(in: .whitespaces)

                    // Check indentation (must be indented for nested)
                    let leadingSpaces = nestedLine.prefix(while: { $0 == " " || $0 == "\t" })
                    if leadingSpaces.isEmpty && !nestedTrimmed.isEmpty {
                        // Not indented, end of nested map
                        break
                    }

                    if nestedTrimmed.isEmpty || nestedTrimmed.hasPrefix("#") {
                        i += 1
                        continue
                    }

                    if let nestedColon = nestedTrimmed.firstIndex(of: ":") {
                        let nestedKey = String(nestedTrimmed[..<nestedColon])
                            .trimmingCharacters(in: .whitespaces)
                        let nestedValue = String(nestedTrimmed[nestedTrimmed.index(after: nestedColon)...])
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        nestedMap[nestedKey] = nestedValue
                    }
                    i += 1
                }
                result[key] = nestedMap
            } else {
                // Simple key-value
                // Remove quotes if present
                let cleanValue = valueAfterColon
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                result[key] = cleanValue
                i += 1
            }
        }

        return result
    }

    // MARK: - Field Parsing Helpers

    /// Parse a required string field.
    private static func parseStringField(_ value: Any, fieldName: String) throws -> String {
        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw SkillError.invalidFieldType(field: fieldName, expected: "non-empty string", actual: "empty string")
            }
            return trimmed
        }
        throw SkillError.invalidFieldType(field: fieldName, expected: "string", actual: String(describing: type(of: value)))
    }

    /// Parse an optional string field.
    private static func parseOptionalStringField(_ value: Any?, fieldName: String) throws -> String? {
        guard let value = value else { return nil }
        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        throw SkillError.invalidFieldType(field: fieldName, expected: "string", actual: String(describing: type(of: value)))
    }

    /// Parse the metadata field (map of string to string).
    private static func parseMetadataField(_ value: Any?) throws -> [String: String]? {
        guard let value = value else { return nil }
        if let dict = value as? [String: String] {
            return dict.isEmpty ? nil : dict
        }
        if let dict = value as? [String: Any] {
            var result: [String: String] = [:]
            for (k, v) in dict {
                result[k] = String(describing: v)
            }
            return result.isEmpty ? nil : result
        }
        throw SkillError.invalidFieldType(field: "metadata", expected: "map", actual: String(describing: type(of: value)))
    }

    /// Parse the allowed-tools field (space-delimited string to array).
    private static func parseAllowedTools(_ value: Any?) throws -> [String]? {
        guard let value = value else { return nil }
        if let stringValue = value as? String {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            let tools = trimmed.components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return tools.isEmpty ? nil : tools
        }
        throw SkillError.invalidFieldType(field: "allowed-tools", expected: "string", actual: String(describing: type(of: value)))
    }

    // MARK: - Directory Scanning

    /// List files in a directory (non-recursive).
    ///
    /// - Parameter directory: Directory to scan
    /// - Returns: Array of relative paths (e.g., "scripts/run.sh")
    private static func listFiles(in directory: URL) -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }

        do {
            let contents = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            return contents.compactMap { url -> String? in
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else {
                    return nil
                }
                // Return path relative to skill root (e.g., "scripts/run.sh")
                let relativePath = directory.lastPathComponent + "/" + url.lastPathComponent
                return relativePath
            }.sorted()
        } catch {
            return []
        }
    }

    /// Get unknown frontmatter keys (for validation warnings).
    ///
    /// - Parameter frontmatter: Parsed frontmatter dictionary
    /// - Returns: Set of keys not in the allowed list
    public static func unknownKeys(in frontmatter: [String: Any]) -> Set<String> {
        let keys = Set(frontmatter.keys)
        return keys.subtracting(allowedFrontmatterKeys)
    }
}
