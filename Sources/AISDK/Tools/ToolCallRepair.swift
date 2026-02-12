//
//  ToolCallRepair.swift
//  AISDK
//
//  Tool call repair mechanism for handling failed tool calls
//  Uses hybrid strategy: local validation + LegacyLLM-assisted repair
//
//  Based on Vercel AI SDK 6.x patterns for robust tool execution
//

import Foundation

// MARK: - ToolCallRepair

/// Tool call repair mechanism for handling and recovering from failed tool calls
///
/// Provides multiple repair strategies from strict (no repair) to LegacyLLM-assisted repair
/// where the model is asked to correct malformed arguments.
///
/// ## Strategies
/// - `.strict`: No repair attempted, errors propagate immediately
/// - `.autoRepairOnce`: Single repair attempt using LLM
/// - `.autoRepairMax(n)`: Up to n repair attempts (n must be > 0)
/// - `.custom(closure)`: Custom repair logic
///
/// ## Usage Example
/// ```swift
/// // Basic usage with ToolCallRepair.attemptRepair
/// let result = try await ToolCallRepair.attemptRepair(
///     toolCall: failedCall,
///     error: ToolError.invalidParameters("Missing required field"),
///     model: myModel,
///     strategy: .autoRepairOnce,
///     requestContext: originalContext  // Preserves safety settings
/// )
///
/// switch result {
/// case .repaired(let fixedCall):
///     // Retry execution with fixedCall
/// case .failed(let reason):
///     // Handle repair failure
/// case .notAttempted:
///     // Strict mode - error propagates
/// }
/// ```
///
/// ## Request Context
/// When repairing tool calls, provide a `RequestContext` to preserve the original
/// request's security settings (`allowedProviders`, `sensitivity`). This ensures
/// repair requests respect PHI/HIPAA constraints.
public struct ToolCallRepair: Sendable {
    // MARK: - Request Context

    /// Context from the original request for preserving safety settings during repair
    public struct RequestContext: Sendable {
        /// Allowed providers (for PHI protection)
        public let allowedProviders: Set<String>?

        /// Data sensitivity level
        public let sensitivity: DataSensitivity

        /// Request metadata for tracing
        public let metadata: [String: String]?

        public init(
            allowedProviders: Set<String>? = nil,
            sensitivity: DataSensitivity = .standard,
            metadata: [String: String]? = nil
        ) {
            self.allowedProviders = allowedProviders
            self.sensitivity = sensitivity
            self.metadata = metadata
        }

        /// Create context from an existing AITextRequest
        public static func from(_ request: AITextRequest) -> RequestContext {
            RequestContext(
                allowedProviders: request.allowedProviders,
                sensitivity: request.sensitivity,
                metadata: request.metadata
            )
        }
    }

    // MARK: - Strategy

    /// Repair strategy for handling failed tool calls
    ///
    /// Note: Strategy does not conform to Equatable to avoid violating equality
    /// semantics for the `.custom` case (closures cannot be meaningfully compared).
    /// Use pattern matching to check strategy type if needed.
    public enum Strategy: Sendable {
        /// No repair - errors propagate immediately
        case strict

        /// Single automatic repair attempt using LLM
        case autoRepairOnce

        /// Multiple repair attempts (up to max count, must be > 0)
        case autoRepairMax(Int)

        /// Custom repair logic
        case custom(@Sendable (AIToolCallResult, Error, any AILanguageModel) async throws -> AIToolCallResult?)

        /// Default strategy (single repair attempt)
        public static var `default`: Strategy { .autoRepairOnce }

        /// Check if this strategy allows repair attempts
        public var allowsRepair: Bool {
            switch self {
            case .strict:
                return false
            case .autoRepairOnce:
                return true
            case .autoRepairMax(let max):
                return max > 0
            case .custom:
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
                return Swift.max(0, max)
            case .custom:
                return 1  // Custom strategies get one attempt by default
            }
        }

        /// Check if this strategy matches another (for testing)
        public func matches(_ other: Strategy) -> Bool {
            switch (self, other) {
            case (.strict, .strict):
                return true
            case (.autoRepairOnce, .autoRepairOnce):
                return true
            case (.autoRepairMax(let lhs), .autoRepairMax(let rhs)):
                return lhs == rhs
            case (.custom, .custom):
                // Custom strategies are considered matching by type only
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Repair Result

    /// Result of a repair attempt
    public enum RepairResult: Sendable, Equatable {
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
    ///   - error: The error that occurred (accepts any Error type)
    ///   - model: The language model to use for repair
    ///   - toolSchema: Optional JSON schema for the tool (helps model understand expected format)
    ///   - requestContext: Optional context to preserve safety settings from original request
    /// - Returns: A repaired tool call if successful, nil if repair fails
    /// - Throws: If the repair request itself fails
    public static func repair(
        toolCall: AIToolCallResult,
        error: Error,
        model: any AILanguageModel,
        toolSchema: ToolSchema? = nil,
        requestContext: RequestContext? = nil
    ) async throws -> AIToolCallResult? {
        // Build repair prompt with context
        let repairPrompt = buildRepairPrompt(
            toolCall: toolCall,
            error: error,
            toolSchema: toolSchema
        )

        // Build request preserving safety settings from context
        let context = requestContext ?? RequestContext()
        let request = AITextRequest(
            messages: [.user(repairPrompt)],
            responseFormat: .jsonObject,
            allowedProviders: context.allowedProviders,
            sensitivity: context.sensitivity,
            metadata: context.metadata
        )

        let result = try await model.generateText(request: request)

        // Parse corrected arguments from response (must be JSON object, not array)
        guard let correctedArgs = parseArgumentsAsObject(from: result.text) else {
            return nil
        }

        // Validate that the corrected arguments are different
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
    ///   - error: The error that occurred (accepts any Error type)
    ///   - model: The language model for repair
    ///   - strategy: The repair strategy to use
    ///   - toolSchema: Optional JSON schema for the tool
    ///   - requestContext: Optional context to preserve safety settings
    /// - Returns: RepairResult indicating the outcome
    public static func attemptRepair(
        toolCall: AIToolCallResult,
        error: Error,
        model: any AILanguageModel,
        strategy: Strategy,
        toolSchema: ToolSchema? = nil,
        requestContext: RequestContext? = nil
    ) async throws -> RepairResult {
        switch strategy {
        case .strict:
            return .notAttempted

        case .autoRepairOnce:
            if let repaired = try await repair(
                toolCall: toolCall,
                error: error,
                model: model,
                toolSchema: toolSchema,
                requestContext: requestContext
            ) {
                return .repaired(repaired)
            }
            return .failed(reason: "Single repair attempt failed")

        case .autoRepairMax(let maxAttempts):
            // Guard against non-positive values
            guard maxAttempts > 0 else {
                return .failed(reason: "Invalid maxAttempts: \(maxAttempts) (must be > 0)")
            }

            var currentCall = toolCall
            var lastErrorDescription = errorDescription(error)

            for attempt in 1...maxAttempts {
                // Create a synthetic error for retry attempts
                let currentError = attempt == 1 ? error : ToolError.invalidParameters(lastErrorDescription)

                if let repaired = try await repair(
                    toolCall: currentCall,
                    error: currentError,
                    model: model,
                    toolSchema: toolSchema,
                    requestContext: requestContext
                ) {
                    return .repaired(repaired)
                }

                if attempt == maxAttempts {
                    return .failed(reason: "Exhausted all \(maxAttempts) repair attempts")
                }

                // Update for next iteration
                lastErrorDescription = "Previous repair attempt produced invalid arguments"
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

    /// Extract error description from any Error type
    private static func errorDescription(_ error: Error) -> String {
        if let toolError = error as? ToolError {
            return toolError.detailedDescription
        } else if let aiError = error as? AISDKError {
            return aiError.localizedDescription
        } else {
            return error.localizedDescription
        }
    }

    /// Build a repair prompt with context about the failure
    private static func buildRepairPrompt(
        toolCall: AIToolCallResult,
        error: Error,
        toolSchema: ToolSchema?
    ) -> String {
        var prompt = """
        A tool call failed with the following error. Please provide corrected JSON arguments.

        Tool Name: \(toolCall.name)
        Original Arguments: \(toolCall.arguments)
        Error: \(errorDescription(error))

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
        The response must be a valid JSON object (not an array) that can be parsed directly.
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

    /// Parse and validate JSON arguments from model response, ensuring it's a JSON object (not array)
    private static func parseArgumentsAsObject(from text: String) -> String? {
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

        // Validate it's valid JSON and specifically a dictionary (not array)
        guard let data = cleanedText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              json is [String: Any] else {
            return nil
        }

        return cleanedText
    }
}
