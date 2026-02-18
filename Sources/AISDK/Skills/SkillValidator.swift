//
//  SkillValidator.swift
//  AISDK
//
//  Validator for skill descriptors against the Agent Skills Protocol.
//  Checks name format, size limits, and directory naming.
//

import Foundation

// MARK: - SkillValidator

/// Validator for skill descriptors.
///
/// Validates skills against the Agent Skills Protocol specification:
/// - Name: 1-64 chars, lowercase alphanumeric + hyphens
/// - Description: 1-1024 chars
/// - Compatibility: 1-500 chars (if present)
/// - File size: Within configured limits
/// - Directory name: Must match skill name
///
/// ## Usage
/// ```swift
/// let result = SkillValidator.validate(descriptor, configuration: config)
/// if !result.isValid {
///     for error in result.errors {
///         print("Error: \(error)")
///     }
/// }
/// ```
public struct SkillValidator: Sendable {

    // MARK: - Constants

    /// Maximum skill name length
    public static let maxNameLength = 64

    /// Maximum description length
    public static let maxDescriptionLength = 1024

    /// Maximum compatibility field length
    public static let maxCompatibilityLength = 500

    /// Pattern for valid skill names (lowercase alphanumeric + hyphens)
    private static let namePattern = "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"

    // MARK: - Full Validation

    /// Validate a skill descriptor against the protocol and configuration.
    ///
    /// Checks all protocol requirements and configuration limits.
    ///
    /// - Parameters:
    ///   - descriptor: Skill descriptor to validate
    ///   - configuration: Configuration with size limits
    /// - Returns: Validation result with errors and warnings
    public static func validate(
        _ descriptor: SkillDescriptor,
        configuration: SkillConfiguration
    ) -> SkillValidationResult {
        var errors: [SkillError] = []
        var warnings: [String] = []

        // Validate name
        let nameResult = validateName(descriptor.name)
        errors.append(contentsOf: nameResult.errors)
        warnings.append(contentsOf: nameResult.warnings)

        // Validate directory name matches skill name
        let dirResult = validateDirectoryMatch(
            directoryName: descriptor.rootPath.lastPathComponent,
            skillName: descriptor.name
        )
        errors.append(contentsOf: dirResult.errors)
        warnings.append(contentsOf: dirResult.warnings)

        // Validate description length
        let descResult = validateDescription(descriptor.description)
        errors.append(contentsOf: descResult.errors)
        warnings.append(contentsOf: descResult.warnings)

        // Validate compatibility length (if present)
        if let compatibility = descriptor.compatibility {
            let compResult = validateCompatibility(compatibility)
            errors.append(contentsOf: compResult.errors)
            warnings.append(contentsOf: compResult.warnings)
        }

        // Validate file size and line count
        do {
            let sizeResult = try validateFileSize(
                url: descriptor.skillMDPath,
                maxBytes: configuration.maxSkillSizeBytes,
                maxLines: configuration.maxSkillLines
            )
            errors.append(contentsOf: sizeResult.errors)
            warnings.append(contentsOf: sizeResult.warnings)
        } catch let error as SkillError {
            errors.append(error)
        } catch {
            errors.append(.fileReadError(path: descriptor.skillMDPath, underlying: error))
        }

        return SkillValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    /// Validate a raw frontmatter dictionary before creating a descriptor.
    ///
    /// Useful for early validation during parsing.
    ///
    /// - Parameters:
    ///   - frontmatter: Parsed YAML frontmatter
    ///   - skillDir: Path to skill directory (for name-directory match)
    ///   - configuration: Configuration settings
    /// - Returns: Validation result
    public static func validateFrontmatter(
        _ frontmatter: [String: Any],
        skillDir: URL?,
        configuration: SkillConfiguration
    ) -> SkillValidationResult {
        var errors: [SkillError] = []
        var warnings: [String] = []

        // Check for unknown keys
        let unknownKeys = SkillParser.unknownKeys(in: frontmatter)
        if !unknownKeys.isEmpty {
            let sortedKeys = unknownKeys.sorted()
            if configuration.strictFrontmatter {
                for key in sortedKeys {
                    errors.append(.unknownFrontmatterKey(
                        key: key,
                        allowedKeys: Array(SkillParser.allowedFrontmatterKeys).sorted()
                    ))
                }
            } else {
                warnings.append("Unknown frontmatter keys: \(sortedKeys.joined(separator: ", "))")
            }
        }

        // Validate name if present
        if let name = frontmatter["name"] as? String {
            let nameResult = validateName(name)
            errors.append(contentsOf: nameResult.errors)
            warnings.append(contentsOf: nameResult.warnings)

            // Validate directory match if we have a skillDir
            if let dir = skillDir {
                let dirResult = validateDirectoryMatch(
                    directoryName: dir.lastPathComponent,
                    skillName: name
                )
                errors.append(contentsOf: dirResult.errors)
                warnings.append(contentsOf: dirResult.warnings)
            }
        }

        // Validate description if present
        if let description = frontmatter["description"] as? String {
            let descResult = validateDescription(description)
            errors.append(contentsOf: descResult.errors)
            warnings.append(contentsOf: descResult.warnings)
        }

        // Validate compatibility if present
        if let compatibility = frontmatter["compatibility"] as? String {
            let compResult = validateCompatibility(compatibility)
            errors.append(contentsOf: compResult.errors)
            warnings.append(contentsOf: compResult.warnings)
        }

        return SkillValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    // MARK: - Name Validation

    /// Validate skill name format.
    ///
    /// Requirements:
    /// - 1-64 characters
    /// - Lowercase letters, digits, and hyphens only
    /// - Cannot start or end with hyphen
    /// - No consecutive hyphens
    ///
    /// - Parameter name: Skill name to validate
    /// - Returns: Validation result
    public static func validateName(_ name: String) -> SkillValidationResult {
        var errors: [SkillError] = []

        // Check empty
        if name.isEmpty {
            errors.append(.invalidName(name: name, reason: "Name cannot be empty"))
            return .failure(errors)
        }

        // Check length
        if name.count > maxNameLength {
            errors.append(.invalidName(
                name: name,
                reason: "Name exceeds \(maxNameLength) character limit (\(name.count) chars)"
            ))
        }

        // Check lowercase
        if name != name.lowercased() {
            errors.append(.invalidName(name: name, reason: "Name must be lowercase"))
        }

        // Check start/end with hyphen
        if name.hasPrefix("-") {
            errors.append(.invalidName(name: name, reason: "Name cannot start with hyphen"))
        }
        if name.hasSuffix("-") {
            errors.append(.invalidName(name: name, reason: "Name cannot end with hyphen"))
        }

        // Check consecutive hyphens
        if name.contains("--") {
            errors.append(.invalidName(name: name, reason: "Name cannot contain consecutive hyphens"))
        }

        // Check character set (alphanumeric + hyphens only)
        let validChars = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "-"))

        for scalar in name.unicodeScalars {
            if !validChars.contains(scalar) {
                errors.append(.invalidName(
                    name: name,
                    reason: "Name contains invalid character '\(scalar)'. Only lowercase letters, digits, and hyphens allowed."
                ))
                break
            }
        }

        return SkillValidationResult(isValid: errors.isEmpty, errors: errors)
    }

    // MARK: - Directory Match Validation

    /// Validate that directory name matches skill name.
    ///
    /// - Parameters:
    ///   - directoryName: Name of the skill directory
    ///   - skillName: Name from SKILL.md frontmatter
    /// - Returns: Validation result
    public static func validateDirectoryMatch(
        directoryName: String,
        skillName: String
    ) -> SkillValidationResult {
        if directoryName != skillName {
            return .failure([.directoryNameMismatch(
                directoryName: directoryName,
                skillName: skillName
            )])
        }
        return .success
    }

    // MARK: - Description Validation

    /// Validate description length.
    ///
    /// - Parameter description: Description text
    /// - Returns: Validation result
    public static func validateDescription(_ description: String) -> SkillValidationResult {
        if description.isEmpty {
            return .failure([.invalidFieldType(
                field: "description",
                expected: "non-empty string",
                actual: "empty string"
            )])
        }

        if description.count > maxDescriptionLength {
            return .failure([.descriptionTooLong(
                length: description.count,
                max: maxDescriptionLength
            )])
        }

        return .success
    }

    // MARK: - Compatibility Validation

    /// Validate compatibility field length.
    ///
    /// - Parameter compatibility: Compatibility text
    /// - Returns: Validation result
    public static func validateCompatibility(_ compatibility: String) -> SkillValidationResult {
        if compatibility.count > maxCompatibilityLength {
            return .failure([.compatibilityTooLong(
                length: compatibility.count,
                max: maxCompatibilityLength
            )])
        }
        return .success
    }

    // MARK: - File Size Validation

    /// Validate SKILL.md file size and line count.
    ///
    /// - Parameters:
    ///   - url: Path to SKILL.md
    ///   - maxBytes: Maximum file size in bytes
    ///   - maxLines: Maximum line count
    /// - Returns: Validation result
    /// - Throws: File read errors
    public static func validateFileSize(
        url: URL,
        maxBytes: Int,
        maxLines: Int
    ) throws -> SkillValidationResult {
        var errors: [SkillError] = []

        // Check file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? Int {
            if size > maxBytes {
                errors.append(.fileTooLarge(size: size, max: maxBytes))
            }
        }

        // Check line count
        let content = try String(contentsOf: url, encoding: .utf8)
        let lineCount = content.components(separatedBy: .newlines).count
        if lineCount > maxLines {
            errors.append(.tooManyLines(count: lineCount, max: maxLines))
        }

        return SkillValidationResult(isValid: errors.isEmpty, errors: errors)
    }

    // MARK: - Path Validation

    /// Validate that a path doesn't escape the skill root.
    ///
    /// Prevents path traversal attacks (e.g., `../../../etc/passwd`).
    ///
    /// - Parameters:
    ///   - relativePath: Relative path within the skill
    ///   - skillRoot: Root directory of the skill
    /// - Returns: Resolved absolute path if valid
    /// - Throws: `SkillError.pathTraversal` if path escapes root
    public static func validatePath(
        _ relativePath: String,
        skillRoot: URL
    ) throws -> URL {
        // Reject absolute paths
        if relativePath.hasPrefix("/") {
            throw SkillError.pathTraversal(attemptedPath: relativePath, skillRoot: skillRoot)
        }

        // Resolve the path
        let resolvedURL = skillRoot.appendingPathComponent(relativePath).standardized

        // Check that resolved path is within skill root
        let rootPath = skillRoot.standardized.path
        let resolvedPath = resolvedURL.path

        guard resolvedPath.hasPrefix(rootPath) else {
            throw SkillError.pathTraversal(attemptedPath: relativePath, skillRoot: skillRoot)
        }

        return resolvedURL
    }

    // MARK: - Tool Validation

    /// Validate that a tool is in the allowed list.
    ///
    /// - Parameters:
    ///   - tool: Tool name being requested
    ///   - allowedTools: List of allowed tools (nil means all allowed)
    /// - Throws: `SkillError.toolNotAllowed` if tool is restricted
    public static func validateTool(
        _ tool: String,
        allowedTools: [String]?
    ) throws {
        guard let allowed = allowedTools else {
            // No restrictions
            return
        }

        // Check if tool matches any allowed pattern
        let toolLower = tool.lowercased()
        for pattern in allowed {
            let patternLower = pattern.lowercased()
            if toolLower == patternLower {
                return
            }
            // Support simple wildcards like "Bash(*)"
            if patternLower.hasSuffix("(*)") {
                let prefix = String(patternLower.dropLast(3))
                if toolLower.hasPrefix(prefix) {
                    return
                }
            }
        }

        throw SkillError.toolNotAllowed(tool: tool, allowedTools: allowed)
    }
}
