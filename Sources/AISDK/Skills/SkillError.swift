//
//  SkillError.swift
//  AISDK
//
//  Error types for Agent Skills Protocol operations.
//  Handles parsing, validation, activation, and sandbox errors.
//

import Foundation

// MARK: - SkillError

/// Errors that can occur during skill operations.
///
/// Skills can fail at various stages:
/// - **Parsing**: Invalid SKILL.md format or missing files
/// - **Validation**: Protocol compliance failures (name format, size limits)
/// - **Activation**: Skill not found or already activated
/// - **Sandbox**: Path traversal or tool restriction violations
///
/// ## Usage
/// ```swift
/// do {
///     let skill = try await registry.activateSkill(named: "my-skill")
/// } catch let error as SkillError {
///     switch error {
///     case .skillNotFound(let name):
///         print("Skill '\(name)' not found")
///     case .pathTraversal(let path, let root):
///         print("Security: attempted path traversal")
///     default:
///         print(error.localizedDescription)
///     }
/// }
/// ```
public enum SkillError: Error, Sendable, Equatable {

    // MARK: - Parsing Errors

    /// SKILL.md file not found in the skill directory
    case missingSkillMD(path: URL)

    /// Invalid YAML frontmatter syntax or structure
    case invalidFrontmatter(reason: String)

    /// Required field missing from frontmatter (name or description)
    case missingRequiredField(field: String)

    /// Invalid YAML type for a field (e.g., array instead of string)
    case invalidFieldType(field: String, expected: String, actual: String)

    // MARK: - Validation Errors

    /// Skill name doesn't match protocol requirements
    /// (1-64 chars, lowercase alphanumeric + hyphens, no consecutive hyphens)
    case invalidName(name: String, reason: String)

    /// Description exceeds maximum length (1024 chars)
    case descriptionTooLong(length: Int, max: Int)

    /// Compatibility field exceeds maximum length (500 chars)
    case compatibilityTooLong(length: Int, max: Int)

    /// SKILL.md file exceeds maximum size
    case fileTooLarge(size: Int, max: Int)

    /// SKILL.md file exceeds maximum line count
    case tooManyLines(count: Int, max: Int)

    /// Directory name doesn't match skill name in frontmatter
    case directoryNameMismatch(directoryName: String, skillName: String)

    /// Unknown key found in frontmatter (warning-level, but can be elevated to error)
    case unknownFrontmatterKey(key: String, allowedKeys: [String])

    // MARK: - Activation Errors

    /// Skill with the given name was not found in any search root
    case skillNotFound(name: String)

    /// Attempted to access a resource outside the skill's root directory
    case pathTraversal(attemptedPath: String, skillRoot: URL)

    /// Tool not in the skill's allowed-tools list
    case toolNotAllowed(tool: String, allowedTools: [String])

    /// Skill is already activated
    case alreadyActivated(name: String)

    // MARK: - File System Errors

    /// Failed to read a file
    case fileReadError(path: URL, underlying: Error)

    /// Failed to access or enumerate a directory
    case directoryAccessError(path: URL, underlying: Error)

    /// Search root directory doesn't exist or isn't accessible
    case searchRootNotAccessible(path: URL)
}

// MARK: - LocalizedError

extension SkillError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        // Parsing
        case .missingSkillMD(let path):
            return "SKILL.md not found at \(path.path)"

        case .invalidFrontmatter(let reason):
            return "Invalid YAML frontmatter: \(reason)"

        case .missingRequiredField(let field):
            return "Missing required field in frontmatter: '\(field)'"

        case .invalidFieldType(let field, let expected, let actual):
            return "Invalid type for '\(field)': expected \(expected), got \(actual)"

        // Validation
        case .invalidName(let name, let reason):
            return "Invalid skill name '\(name)': \(reason)"

        case .descriptionTooLong(let length, let max):
            return "Description too long: \(length) characters (max \(max))"

        case .compatibilityTooLong(let length, let max):
            return "Compatibility field too long: \(length) characters (max \(max))"

        case .fileTooLarge(let size, let max):
            return "SKILL.md too large: \(size) bytes (max \(max))"

        case .tooManyLines(let count, let max):
            return "SKILL.md has too many lines: \(count) (max \(max))"

        case .directoryNameMismatch(let dirName, let skillName):
            return "Directory name '\(dirName)' doesn't match skill name '\(skillName)'"

        case .unknownFrontmatterKey(let key, let allowed):
            return "Unknown frontmatter key '\(key)'. Allowed: \(allowed.joined(separator: ", "))"

        // Activation
        case .skillNotFound(let name):
            return "Skill '\(name)' not found"

        case .pathTraversal(let path, let root):
            return "Path traversal blocked: '\(path)' escapes skill root '\(root.path)'"

        case .toolNotAllowed(let tool, let allowed):
            let allowedStr = allowed.isEmpty ? "none" : allowed.joined(separator: ", ")
            return "Tool '\(tool)' not allowed. Allowed tools: \(allowedStr)"

        case .alreadyActivated(let name):
            return "Skill '\(name)' is already activated"

        // File System
        case .fileReadError(let path, let underlying):
            return "Failed to read '\(path.path)': \(underlying.localizedDescription)"

        case .directoryAccessError(let path, let underlying):
            return "Failed to access directory '\(path.path)': \(underlying.localizedDescription)"

        case .searchRootNotAccessible(let path):
            return "Search root not accessible: \(path.path)"
        }
    }
}

// MARK: - Equatable Conformance

extension SkillError {

    public static func == (lhs: SkillError, rhs: SkillError) -> Bool {
        switch (lhs, rhs) {
        case (.missingSkillMD(let l), .missingSkillMD(let r)):
            return l == r
        case (.invalidFrontmatter(let l), .invalidFrontmatter(let r)):
            return l == r
        case (.missingRequiredField(let l), .missingRequiredField(let r)):
            return l == r
        case (.invalidFieldType(let lf, let le, let la), .invalidFieldType(let rf, let re, let ra)):
            return lf == rf && le == re && la == ra
        case (.invalidName(let ln, let lr), .invalidName(let rn, let rr)):
            return ln == rn && lr == rr
        case (.descriptionTooLong(let ll, let lm), .descriptionTooLong(let rl, let rm)):
            return ll == rl && lm == rm
        case (.compatibilityTooLong(let ll, let lm), .compatibilityTooLong(let rl, let rm)):
            return ll == rl && lm == rm
        case (.fileTooLarge(let ls, let lm), .fileTooLarge(let rs, let rm)):
            return ls == rs && lm == rm
        case (.tooManyLines(let lc, let lm), .tooManyLines(let rc, let rm)):
            return lc == rc && lm == rm
        case (.directoryNameMismatch(let ld, let ls), .directoryNameMismatch(let rd, let rs)):
            return ld == rd && ls == rs
        case (.unknownFrontmatterKey(let lk, let la), .unknownFrontmatterKey(let rk, let ra)):
            return lk == rk && la == ra
        case (.skillNotFound(let l), .skillNotFound(let r)):
            return l == r
        case (.pathTraversal(let lp, let lr), .pathTraversal(let rp, let rr)):
            return lp == rp && lr == rr
        case (.toolNotAllowed(let lt, let la), .toolNotAllowed(let rt, let ra)):
            return lt == rt && la == ra
        case (.alreadyActivated(let l), .alreadyActivated(let r)):
            return l == r
        case (.searchRootNotAccessible(let l), .searchRootNotAccessible(let r)):
            return l == r
        // File errors can't be easily compared due to underlying Error
        case (.fileReadError(let lp, _), .fileReadError(let rp, _)):
            return lp == rp
        case (.directoryAccessError(let lp, _), .directoryAccessError(let rp, _)):
            return lp == rp
        default:
            return false
        }
    }
}
