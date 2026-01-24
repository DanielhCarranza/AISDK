//
//  ToolCallRepair.swift
//  AISDK
//
//  Tool call repair mechanism for handling failed tool calls
//  Uses hybrid strategy: local validation + LLM-assisted repair
//
//  Based on Vercel AI SDK 6.x patterns for robust tool execution
//

import Foundation

// MARK: - ToolCallRepair

/// Tool call repair mechanism for handling and recovering from failed tool calls
///
/// Provides multiple repair strategies from strict (no repair) to LLM-assisted repair
/// where the model is asked to correct malformed arguments.
///
/// ## Strategies
/// - `.strict`: No repair attempted, errors propagate immediately
/// - `.autoRepairOnce`: Single repair attempt using LLM
/// - `.autoRepairMax(n)`: Up to n repair attempts
/// - `.custom(closure)`: Custom repair logic
///
/// ## Usage Example
/// ```swift
/// let agent = AIAgentActor(
///     model: myModel,
///     tools: [SearchTool.self],
///     repairStrategy: .autoRepairOnce
/// )
///
/// // During execution, if a tool call fails due to invalid arguments,
/// // the repair mechanism will ask the model to fix them
/// ```
public struct ToolCallRepair: Sendable {
    // MARK: - Strategy

    /// Repair strategy for handling failed tool calls
    public enum Strategy: Sendable {
        /// No repair - errors propagate immediately
        case strict

        /// Single automatic repair attempt using LLM
        case autoRepairOnce

        /// Multiple repair attempts (up to max count)
        case autoRepairMax(Int)

        /// Custom repair logic
        case custom(@Sendable (AIToolCallResult, ToolError, any AILanguageModel) async throws -> AIToolCallResult?)

        /// Default strategy (single repair attempt)
        public static var `default`: Strategy { .autoRepairOnce }

        /// Check if this strategy allows repair attempts
        public var allowsRepair: Bool {
            switch self {
            case .strict:
                return false
            case .autoRepairOnce, .autoRepairMax, .custom:
                return true
            }
        }

        /// Maximum repair attempts for this strategy
        public var maxAttempts: Int {
            switch self {
            case .strict:
                return 0
            case .autoRepairOnce:
                return 1
            case .autoRepairMax(let max):
                return max
            case .custom:
                return 1  // Custom strategies get one attempt by default
            }
        }
    }

    // MARK: - Repair Result

    /// Result of a repair attempt
    public enum RepairResult: Sendable {
        /// Repair succeeded with corrected tool call
        case repaired(AIToolCallResult)

        /// Repair failed and cannot be retried
        case failed(reason: String)

        /// Repair was not attempted (e.g., strict mode)
        case notAttempted
    }

    // MARK: - Static Repair Methods

    /// Attempt to repair a failed tool call using the provided model
    ///
    /// This method constructs a repair prompt with the error context and asks
    /// the model to provide corrected arguments.
    ///
    /// - Parameters:
    ///   - toolCall: The failed tool call
    ///   - error: The error that occurred
    ///   - model: The language model to use for repair
    ///   - toolSchema: Optional JSON schema for the tool (helps model understand expected format)
    /// - Returns: A repaired tool call if successful, nil if repair fails
    /// - Throws: If the repair request itself fails
    public static func repair(
        toolCall: AIToolCallResult,
        error: ToolError,
        model: any AILanguageModel,
        toolSchema: ToolSchema? = nil
    ) async throws -> AIToolCallResult? {
        // Build repair prompt with context
        let repairPrompt = buildRepairPrompt(
            toolCall: toolCall,
            error: error,
            toolSchema: toolSchema
        )

        // Ask model to fix the arguments
        let request = AITextRequest(
            messages: [.user(repairPrompt)],
            responseFormat: .jsonObject
        )

        let result = try await model.generateText(request: request)

        // Parse corrected arguments from response
        guard let correctedArgs = parseArguments(from: result.text) else {
            return nil
        }

        // Validate that the corrected arguments are different and valid JSON
        guard correctedArgs != toolCall.arguments else {
            // Model returned the same arguments, repair didn't help
            return nil
        }

        return AIToolCallResult(
            id: toolCall.id,
            name: toolCall.name,
            arguments: correctedArgs
        )
    }

    /// Attempt repair with full strategy support
    ///
    /// - Parameters:
    ///   - toolCall: The failed tool call
    ///   - error: The error that occurred
    ///   - model: The language model for repair
    ///   - strategy: The repair strategy to use
    ///   - toolSchema: Optional JSON schema for the tool
    /// - Returns: RepairResult indicating the outcome
    public static func attemptRepair(
        toolCall: AIToolCallResult,
        error: ToolError,
        model: any AILanguageModel,
        strategy: Strategy,
        toolSchema: ToolSchema? = nil
    ) async throws -> RepairResult {
        switch strategy {
        case .strict:
            return .notAttempted

        case .autoRepairOnce:
            if let repaired = try await repair(
                toolCall: toolCall,
                error: error,
                model: model,
                toolSchema: toolSchema
            ) {
                return .repaired(repaired)
            }
            return .failed(reason: "Single repair attempt failed")

        case .autoRepairMax(let maxAttempts):
            var lastError: ToolError = error
            var currentCall = toolCall

            for attempt in 1...maxAttempts {
                if let repaired = try await repair(
                    toolCall: currentCall,
                    error: lastError,
                    model: model,
                    toolSchema: toolSchema
                ) {
                    // Validate the repaired arguments
                    if let validationError = validateArguments(repaired.arguments) {
                        lastError = validationError
                        currentCall = repaired
                        continue
                    }
                    return .repaired(repaired)
                }

                if attempt == maxAttempts {
                    return .failed(reason: "Exhausted all \(maxAttempts) repair attempts")
                }
            }
            return .failed(reason: "Repair loop completed without success")

        case .custom(let handler):
            if let repaired = try await handler(toolCall, error, model) {
                return .repaired(repaired)
            }
            return .failed(reason: "Custom repair handler returned nil")
        }
    }

    // MARK: - Private Helpers

    /// Build a repair prompt with context about the failure
    private static func buildRepairPrompt(
        toolCall: AIToolCallResult,
        error: ToolError,
        toolSchema: ToolSchema?
    ) -> String {
        var prompt = """
        A tool call failed with the following error. Please provide corrected JSON arguments.

        Tool Name: \(toolCall.name)
        Original Arguments: \(toolCall.arguments)
        Error: \(error.detailedDescription)

        """

        // Add schema information if available
        if let schema = toolSchema,
           let function = schema.function {
            prompt += """

            Expected Format:
            - Tool: \(function.name)
            - Description: \(function.description ?? "No description")
            - Parameters: \(formatParameters(function.parameters))

            """
        }

        prompt += """

        Respond with ONLY the corrected JSON arguments object, no explanation or markdown.
        The response must be valid JSON that can be parsed directly.
        """

        return prompt
    }

    /// Format parameters for the prompt
    private static func formatParameters(_ params: Parameters) -> String {
        guard !params.properties.isEmpty else {
            return "{}"
        }

        var lines: [String] = ["{"]
        for (name, prop) in params.properties.sorted(by: { $0.key < $1.key }) {
            let required = params.required?.contains(name) ?? false
            let requiredMark = required ? " (required)" : ""
            lines.append("  \"\(name)\": \(prop.type)\(requiredMark) - \(prop.description ?? "")")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// Parse and validate JSON arguments from model response
    private static func parseArguments(from text: String) -> String? {
        // Clean up the response - remove markdown code blocks if present
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks
        if cleanedText.hasPrefix("```json") {
            cleanedText = String(cleanedText.dropFirst(7))
        } else if cleanedText.hasPrefix("```") {
            cleanedText = String(cleanedText.dropFirst(3))
        }
        if cleanedText.hasSuffix("```") {
            cleanedText = String(cleanedText.dropLast(3))
        }
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate it's valid JSON
        guard let data = cleanedText.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }

        return cleanedText
    }

    /// Validate that arguments are valid JSON
    private static func validateArguments(_ arguments: String) -> ToolError? {
        guard let data = arguments.data(using: .utf8) else {
            return .invalidParameters("Arguments are not valid UTF-8")
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            return nil
        } catch {
            return .invalidParameters("Invalid JSON: \(error.localizedDescription)")
        }
    }
}

// MARK: - Convenience Extensions

extension ToolCallRepair.Strategy: Equatable {
    public static func == (lhs: ToolCallRepair.Strategy, rhs: ToolCallRepair.Strategy) -> Bool {
        switch (lhs, rhs) {
        case (.strict, .strict):
            return true
        case (.autoRepairOnce, .autoRepairOnce):
            return true
        case (.autoRepairMax(let lhsMax), .autoRepairMax(let rhsMax)):
            return lhsMax == rhsMax
        case (.custom, .custom):
            // Custom closures cannot be compared for equality
            return false
        default:
            return false
        }
    }
}

extension ToolCallRepair.RepairResult: Equatable {
    public static func == (lhs: ToolCallRepair.RepairResult, rhs: ToolCallRepair.RepairResult) -> Bool {
        switch (lhs, rhs) {
        case (.repaired(let lhsCall), .repaired(let rhsCall)):
            return lhsCall == rhsCall
        case (.failed(let lhsReason), .failed(let rhsReason)):
            return lhsReason == rhsReason
        case (.notAttempted, .notAttempted):
            return true
        default:
            return false
        }
    }
}
