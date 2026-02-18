//
//  SkillPromptBuilder.swift
//  AISDK
//
//  Generates available skills metadata for system prompt injection.
//  Follows the Agent Skills Protocol recommendation for Claude models.
//

import Foundation

// MARK: - SkillPromptBuilder

/// Builder for generating skill metadata in system prompt format.
///
/// Generates XML or JSON representations of available skills for
/// injection into the agent's system prompt. The recommended format
/// for Claude models is XML with `<available_skills>` wrapper.
///
/// ## Progressive Disclosure
/// Only metadata is included in the prompt - skill bodies are loaded
/// on demand when the model activates a skill.
///
/// ## Usage
/// ```swift
/// let skills = try await registry.getSkillsMetadata()
/// let xmlBlock = SkillPromptBuilder.buildAvailableSkillsBlock(skills)
/// // Inject into system prompt
/// let prompt = baseInstructions + "\n\n" + xmlBlock
/// ```
public struct SkillPromptBuilder: Sendable {

    // MARK: - XML Format

    /// Build XML metadata block for available skills.
    ///
    /// Generates the `<available_skills>` XML block recommended by the
    /// Agent Skills Protocol for Claude models.
    ///
    /// Example output:
    /// ```xml
    /// <available_skills>
    /// <skill name="pdf-reader" scope="project">
    /// <description>Read and extract text from PDF files</description>
    /// <location>/path/to/pdf-reader/SKILL.md</location>
    /// <allowed_tools>bash read_file</allowed_tools>
    /// <has_scripts>true</has_scripts>
    /// </skill>
    /// </available_skills>
    /// ```
    ///
    /// - Parameter skills: Array of skill descriptors
    /// - Returns: XML string ready for system prompt injection
    public static func buildAvailableSkillsBlock(_ skills: [SkillDescriptor]) -> String {
        guard !skills.isEmpty else {
            return "<available_skills>\n</available_skills>"
        }

        var lines: [String] = ["<available_skills>"]

        for skill in skills.sorted(by: { $0.name < $1.name }) {
            lines.append("<skill name=\"\(escapeXML(skill.name))\" scope=\"\(skill.scope.rawValue)\">")
            lines.append("<description>\(escapeXML(skill.description))</description>")
            lines.append("<location>\(escapeXML(skill.skillMDPath.path))</location>")

            if let tools = skill.allowedTools, !tools.isEmpty {
                lines.append("<allowed_tools>\(escapeXML(tools.joined(separator: " ")))</allowed_tools>")
            }

            lines.append("<has_scripts>\(skill.hasScripts)</has_scripts>")
            lines.append("<has_references>\(skill.hasReferences)</has_references>")
            lines.append("</skill>")
        }

        lines.append("</available_skills>")

        return lines.joined(separator: "\n")
    }

    /// Build a minimal XML block with just names and descriptions.
    ///
    /// Use this for reduced token usage when full metadata isn't needed.
    ///
    /// - Parameter skills: Array of skill descriptors
    /// - Returns: Minimal XML string
    public static func buildMinimalSkillsBlock(_ skills: [SkillDescriptor]) -> String {
        guard !skills.isEmpty else {
            return "<available_skills />"
        }

        var lines: [String] = ["<available_skills>"]

        for skill in skills.sorted(by: { $0.name < $1.name }) {
            lines.append("<skill name=\"\(escapeXML(skill.name))\">")
            lines.append("\(escapeXML(skill.description))")
            lines.append("</skill>")
        }

        lines.append("</available_skills>")

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Format

    /// Build JSON metadata for skills (alternative format).
    ///
    /// Some models may prefer JSON over XML. This generates a JSON array
    /// with skill metadata.
    ///
    /// - Parameter skills: Array of skill descriptors
    /// - Returns: JSON string
    public static func buildSkillsJSON(_ skills: [SkillDescriptor]) -> String {
        guard !skills.isEmpty else {
            return "[]"
        }

        var skillObjects: [[String: Any]] = []

        for skill in skills.sorted(by: { $0.name < $1.name }) {
            var obj: [String: Any] = [
                "name": skill.name,
                "description": skill.description,
                "scope": skill.scope.rawValue,
                "location": skill.skillMDPath.path,
                "has_scripts": skill.hasScripts,
                "has_references": skill.hasReferences
            ]

            if let tools = skill.allowedTools, !tools.isEmpty {
                obj["allowed_tools"] = tools
            }

            if let license = skill.license {
                obj["license"] = license
            }

            if let compatibility = skill.compatibility {
                obj["compatibility"] = compatibility
            }

            skillObjects.append(obj)
        }

        // Convert to JSON
        do {
            let data = try JSONSerialization.data(
                withJSONObject: skillObjects,
                options: [.prettyPrinted, .sortedKeys]
            )
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }

    // MARK: - Activated Skill Format

    /// Build XML block for an activated skill's body.
    ///
    /// Used when injecting a skill's full instructions into context.
    ///
    /// - Parameter loadedSkill: The activated skill with body content
    /// - Returns: XML string with skill body
    public static func buildActivatedSkillBlock(_ loadedSkill: LoadedSkill) -> String {
        var lines: [String] = []

        lines.append("<skill name=\"\(escapeXML(loadedSkill.descriptor.name))\" activated=\"true\">")

        // Include available scripts
        if !loadedSkill.scriptPaths.isEmpty {
            lines.append("<available_scripts>")
            for script in loadedSkill.scriptPaths {
                lines.append("  <script>\(escapeXML(script))</script>")
            }
            lines.append("</available_scripts>")
        }

        // Include available references
        if !loadedSkill.referencePaths.isEmpty {
            lines.append("<available_references>")
            for ref in loadedSkill.referencePaths {
                lines.append("  <reference>\(escapeXML(ref))</reference>")
            }
            lines.append("</available_references>")
        }

        // Include body
        lines.append("<instructions>")
        lines.append(loadedSkill.body)
        lines.append("</instructions>")

        lines.append("</skill>")

        return lines.joined(separator: "\n")
    }

    /// Build instruction text for using skills.
    ///
    /// Provides the model with guidance on how to interact with skills.
    ///
    /// - Returns: Instruction text
    public static func buildSkillUsageInstructions() -> String {
        """
        ## Using Skills

        Skills are specialized capabilities you can activate when needed. To use a skill:

        1. Review the available skills in <available_skills> above
        2. When a skill is relevant to the task, mention its name (e.g., "I'll use the project-indexer skill")
        3. Once activated, follow the skill's instructions
        4. You can execute scripts by using the bash tool with the skill's scripts/ directory
        5. You can read reference files from the skill's references/ directory

        Skills help you perform specific tasks more effectively. Use them when the task matches the skill's description.
        """
    }

    // MARK: - Combined Prompt

    /// Build complete skills section for system prompt.
    ///
    /// Combines usage instructions, available skills, and any activated skills.
    ///
    /// - Parameters:
    ///   - available: Available skill descriptors
    ///   - activated: Currently activated skills
    ///   - includeInstructions: Whether to include usage instructions
    /// - Returns: Complete skills section
    public static func buildSkillsSection(
        available: [SkillDescriptor],
        activated: [LoadedSkill] = [],
        includeInstructions: Bool = true
    ) -> String {
        var parts: [String] = []

        // Usage instructions
        if includeInstructions && !available.isEmpty {
            parts.append(buildSkillUsageInstructions())
        }

        // Available skills
        if !available.isEmpty {
            parts.append(buildAvailableSkillsBlock(available))
        }

        // Activated skill bodies
        for loadedSkill in activated {
            parts.append(buildActivatedSkillBlock(loadedSkill))
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - XML Escaping

    /// Escape special characters for XML.
    ///
    /// - Parameter string: String to escape
    /// - Returns: XML-safe string
    private static func escapeXML(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&apos;")
        return result
    }
}

// MARK: - Token Estimation

extension SkillPromptBuilder {

    /// Estimate token count for a skills section.
    ///
    /// Rough estimation based on character count. Useful for
    /// deciding whether to use minimal or full format.
    ///
    /// - Parameters:
    ///   - available: Available skills
    ///   - activated: Activated skills
    /// - Returns: Estimated token count
    public static func estimateTokens(
        available: [SkillDescriptor],
        activated: [LoadedSkill]
    ) -> Int {
        let section = buildSkillsSection(
            available: available,
            activated: activated,
            includeInstructions: true
        )

        // Rough estimate: ~4 characters per token
        return section.count / 4
    }

    /// Check if skills section exceeds token budget.
    ///
    /// - Parameters:
    ///   - available: Available skills
    ///   - activated: Activated skills
    ///   - maxTokens: Token budget
    /// - Returns: True if estimated tokens exceed budget
    public static func exceedsTokenBudget(
        available: [SkillDescriptor],
        activated: [LoadedSkill],
        maxTokens: Int
    ) -> Bool {
        return estimateTokens(available: available, activated: activated) > maxTokens
    }
}
