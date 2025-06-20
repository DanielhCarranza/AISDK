//
//  Parameter.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import SwiftUI
import Foundation

// MARK: - JSON Type Enum
public enum JSONType: String {
    case string
    case number
    case integer
    case boolean
    case array
    case object
    case null
}

// MARK: - Parameter Property Wrapper
@propertyWrapper
public class Parameter<Value> {
    public let description: String
    public var wrappedValue: Value
    public var validation: [String: Any]?

    public init(wrappedValue: Value,
                description: String,
                validation: [String: Any]? = nil) {
        self.description = description
        self.wrappedValue = wrappedValue
        self.validation = validation
    }
    
    public var projectedValue: Parameter<Value> { self }
    
    /// Helper to dynamically figure out a JSONType from Swift's type
    internal static func inferType(from valueType: Any.Type) -> JSONType {
        switch valueType {
        case is String.Type: return .string
        case is Int.Type, is Int32.Type, is Int64.Type: return .integer
        case is Double.Type, is Float.Type: return .number
        case is Bool.Type: return .boolean
        case is Array<Any>.Type: return .array
        case is [String: Any].Type: return .object
        default: return .string
        }
    }
}


// MARK: - Metadata Types

/// Base protocol for all tool metadata types
public protocol ToolMetadata: Codable {
    // Base protocol that all metadata types must conform to
}

// RenderMetadata.swift

/// A universal metadata that signals "this message can render a tool UI"
public struct RenderMetadata: ToolMetadata {
    public let toolName: String
    
    /// JSON data or dictionary for tool-specific parameters
    public let jsonData: Data
    
    public init(toolName: String, jsonData: Data) {
        self.toolName = toolName
        self.jsonData = jsonData
    }
}




// MARK: - Type Erasing Wrapper

/// Type-erasing wrapper for ToolMetadata to handle encoding/decoding of different metadata types
public struct AnyToolMetadata: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, metadata
    }
    
    public let metadata: ToolMetadata
    private let type: String
    
    public init(_ metadata: ToolMetadata) {
        self.metadata = metadata
        self.type = String(describing: Swift.type(of: metadata))
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        
        switch self.type {
        case String(describing: RenderMetadata.self):
            self.metadata = try container.decode(RenderMetadata.self, forKey: .metadata)
        default:
            // For now, skip unknown metadata types and create a default RenderMetadata
            self.metadata = RenderMetadata(toolName: "unknown", jsonData: Data())
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        
        switch metadata {
        case let renderMeta as RenderMetadata:
            try container.encode(renderMeta, forKey: .metadata)
        default:
            // Skip unknown metadata types for now
            break
        }
    }
}

// MARK: - Tool Protocol

/// A protocol that defines a tool that can be used by the agent
public protocol Tool {
    var name: String { get }
    var description: String { get }
    var returnToolResponse: Bool { get }
    
    init()
    static func jsonSchema() -> ToolSchema
    func execute() async throws -> (content: String, metadata: ToolMetadata?)
    
    // Add mutating keyword here
    mutating func setParameters(from arguments: [String: Any]) throws
    
    // Add mutating keyword here
    mutating func validateAndSetParameters(_ argumentsData: Data) throws -> Self
}

public protocol RenderableTool: Tool {
    /// Renders a SwiftUI view given the stored metadata
    /// - Parameter data: raw JSON arguments or any typed object
    /// - Returns: SwiftUI view to embed
    func render(from data: Data) -> AnyView
}

// Default extension (no-op if tool is not renderable)
extension Tool {
    public func render(from data: Data) -> AnyView {
        AnyView(EmptyView())
    }
}

// Default implementation
extension Tool {
    public var returnToolResponse: Bool { false }
    // Backward compatibility for tools that don't use metadata
    public func execute() async throws -> String {
        let result = try await execute()
        return result.content
    }
    
    // Add mutating keyword here
    public mutating func setParameters(from arguments: [String: Any]) throws {
        let mirror = Mirror(reflecting: self)
        print("📝 Setting parameters from arguments: \(arguments)")
        
        // Convert arguments to camelCase
        let camelCaseArguments = arguments.reduce(into: [String: Any]()) { result, pair in
            let camelCaseKey = pair.key.split(separator: "_")
                .enumerated()
                .map { index, part in
                    index == 0 ? part.lowercased() : part.prefix(1).uppercased() + part.dropFirst().lowercased()
                }
                .joined()
            result[camelCaseKey] = pair.value
            print("📝 Converted \(pair.key) to \(camelCaseKey)")
        }
        
        for child in mirror.children {
            guard let label = child.label?.replacingOccurrences(of: "_", with: ""),
                  var parameterObj = child.value as? ParameterSettable else {
                continue
            }
            
            // Try to get value using the camelCase key
            if let argumentValue = camelCaseArguments[label] {
                print("📝 Setting parameter \(label) to \(argumentValue)")
                do {
                    try parameterObj.setValue(argumentValue)
                } catch {
                    print("⚠️ Error setting parameter \(label): \(error)")
                    throw error
                }
            } else {
                print("📝 No value found for parameter \(label)")
            }
        }
    }
    
    // Add mutating keyword here
    public mutating func validateAndSetParameters(_ argumentsData: Data) throws -> Self {
        // Debug logging
        let rawString = String(data: argumentsData, encoding: .utf8) ?? "Unable to decode data"
        print("📝 Tool arguments raw string: \(rawString)")
        
        // Try to parse as a single JSON object first
        do {
            guard !argumentsData.isEmpty else {
                throw ToolError.invalidParameters("Empty arguments data")
            }
            
            if let parsed = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any] {
                // Successfully parsed as a single JSON object
                print("📝 Parsed arguments: \(parsed)")
                
                // Create mutable copy
                var tool = self
                
                // Validate required parameters
                let schema = Self.jsonSchema()
                if let required = schema.function?.parameters.required {
                    print("📝 Required parameters: \(required)")
                    for param in required {
                        guard parsed[param] != nil else {
                            throw ToolError.invalidParameters("Missing required parameter: \(param)")
                        }
                    }
                }
                
                // Set parameters
                try tool.setParameters(from: parsed)
                return tool
            }
            
            // If we get here, the JSON parsing failed - try to handle concatenated JSON objects
            print("📝 Attempting to handle concatenated JSON objects")
            
            // Get the tool's required parameters
            let schema = Self.jsonSchema()
            let requiredParams = schema.function?.parameters.required ?? []
            print("📝 Tool requires parameters: \(requiredParams)")
            
            // Try to find valid JSON objects in the string
            let extractedParams = try extractParametersFromConcatenatedJSON(rawString, requiredParams: requiredParams)
            if !extractedParams.isEmpty {
                print("📝 Extracted parameters from concatenated JSON: \(extractedParams)")
                
                // Create mutable copy
                var tool = self
                
                // Validate required parameters
                for param in requiredParams {
                    guard extractedParams[param] != nil else {
                        throw ToolError.invalidParameters("Missing required parameter after extraction: \(param)")
                    }
                }
                
                // Set parameters
                try tool.setParameters(from: extractedParams)
                return tool
            }
            
            // If we get here, we couldn't extract the required parameters
            throw ToolError.invalidParameters("Could not find required parameters in the JSON")
            
        } catch {
            if let toolError = error as? ToolError {
                throw toolError
            }
            print("⚠️ JSON parsing error: \(error)")
            throw ToolError.invalidParameters("Failed to parse JSON: \(error.localizedDescription)")
        }
    }
    
    // Helper function to extract parameters from concatenated JSON objects
    private func extractParametersFromConcatenatedJSON(_ jsonString: String, requiredParams: [String]) throws -> [String: Any] {
        var result: [String: Any] = [:]
        
        // Try to find JSON objects using regex
        let pattern = "\\{[^\\{\\}]*\\}"
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let nsString = jsonString as NSString
        let matches = regex.matches(in: jsonString, options: [], range: NSRange(location: 0, length: nsString.length))
        
        print("📝 Found \(matches.count) potential JSON objects in string")
        
        // Extract and parse each potential JSON object
        for match in matches {
            let matchRange = match.range
            let jsonSubstring = nsString.substring(with: matchRange)
            
            if let jsonData = jsonSubstring.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                
                print("📝 Successfully parsed JSON object: \(jsonObject)")
                
                // Check if this object contains any of our required parameters
                for param in requiredParams {
                    if let value = jsonObject[param] {
                        result[param] = value
                        print("📝 Found required parameter '\(param)' with value: \(value)")
                    }
                }
                
                // If we've found all required parameters, we can stop
                if requiredParams.allSatisfy({ result[$0] != nil }) {
                    break
                }
            }
        }
        
        return result
    }
}

// Protocol for parameters that can be set from JSON values
public protocol ParameterSettable {
    mutating func setValue(_ value: Any) throws
}

// Make Parameter conform to ParameterSettable
extension Parameter: ParameterSettable {
    public func setValue(_ value: Any) throws {
        // Check enum validation first if it exists
        if let validation = validation,
           let enumValues = validation["enum"] as? [String],
           let stringValue = value as? String {
            if !enumValues.contains(stringValue) {
                throw ToolError.invalidParameters(
                    "Invalid enum value '\(stringValue)'. Expected one of: \(enumValues.joined(separator: ", "))"
                )
            }
        }
        
        // Attempt to cast `value` to the property's actual type
        guard let typedValue = value as? Value else {
            throw ToolError.invalidParameters(
                "Expected type \(Value.self), got \(type(of: value))"
            )
        }
        // Mutate the same reference
        self.wrappedValue = typedValue
    }
}

extension Tool {
    public static func jsonSchema() -> ToolSchema {
        let instance = Self()
        let mirror = Mirror(reflecting: instance)
        var properties: [String: PropertyDefinition] = [:]
        var required: [String] = []

        for child in mirror.children {
            // Convert property name to snake_case for JSON schema
            guard let originalLabel = child.label?.trimmingCharacters(in: ["_"]),
                  let parameter = unwrapParameter(from: child.value) else {
                continue
            }
            
            // Convert camelCase to snake_case
            let label = originalLabel.replacingOccurrences(of: "(?=[A-Z])", with: "_", options: .regularExpression)
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

            // Create PropertyDefinition from unwrapped parameter
            let propertyDefinition = PropertyDefinition(
                type: parameter.type.rawValue,
                description: parameter.description,
                minimum: parameter.validation?["minimum"] as? Double,
                maximum: parameter.validation?["maximum"] as? Double,
                minLength: parameter.validation?["minLength"] as? Int,
                maxLength: parameter.validation?["maxLength"] as? Int,
                pattern: parameter.validation?["pattern"] as? String,
                enumValues: parameter.validation?["enum"] as? [String]
            )

            properties[label] = propertyDefinition
            
            // Add to required list by default
            // Only exclude if it's an Optional type
            let isOptional = isOptionalType(child.value)
            if !isOptional {
                required.append(label)
            }
        }

        return ToolSchema(
            type: "function",
            function: ToolFunction(
                name: instance.name,
                description: instance.description,
                parameters: Parameters(
                    type: "object",
                    properties: properties,
                    required: required
                )
            )
        )
    }
}

/// Check if a value is an Optional type
private func isOptionalType(_ value: Any) -> Bool {
    let mirror = Mirror(reflecting: value)
    
    // Check if it's a Parameter wrapper first
    if value is any ParameterProtocol {
        // For Parameter wrapper, check the wrapped value type
        let parameterMirror = Mirror(reflecting: value)
        if let wrappedValue = parameterMirror.children.first(where: { $0.label == "wrappedValue" })?.value {
            // Check if the wrapped value's type is Optional
            let wrappedMirror = Mirror(reflecting: wrappedValue)
            return wrappedMirror.displayStyle == .optional
        }
    }
    
    // Direct check for Optional type
    return mirror.displayStyle == .optional || String(describing: type(of: value)).contains("Optional")
}

private func unwrapParameter(from value: Any) -> (description: String, validation: [String: Any]?, type: JSONType)? {
    // Remove struct check since Parameter is a class
    guard let parameter = value as? any ParameterProtocol else {
        return nil
    }
    return (parameter.parameterDescription, parameter.validationDict, parameter.parameterType)
}

// MARK: - Parameter Protocol
public protocol ParameterProtocol {
    var parameterDescription: String { get }
    var validationDict: [String: Any]? { get }
    var parameterType: JSONType { get }
}

extension Parameter: ParameterProtocol {
    public var parameterDescription: String { description }
    public var validationDict: [String: Any]? { validation }
    public var parameterType: JSONType { Self.inferType(from: Value.self) }
}

// MARK: - Example Tools
/*
struct WeatherTool: Tool {
    let name = "get_current_weather"
    let description = "Get the current weather in a given location"
    
    init() {}

    @Parameter(description: "The city and state, e.g. San Francisco, CA")
    var location: String = ""

    @Parameter(description: "Temperature unit", validation: ["enum": ["celsius", "fahrenheit"]])
    var unit: String = "celsius"

    func execute() async throws -> String {
        return "Weather \(self.location) \(self.unit)"
    }
}

struct ImageGenerationTool: Tool {
    let name = "generate_image"
    let description = "Generate an image based on text prompt"
    
    init() {}

    @Parameter(description: "Text description of the image to generate")
    var prompt: String = ""

    @Parameter(description: "Image size", validation: ["enum": ["256x256", "512x512", "1024x1024"]])
    var size: String = "512x512"
}

// Testing different tools
let weatherSchema = WeatherTool.jsonSchema()
let imageGenSchema = ImageGenerationTool.jsonSchema()

*/

extension Encodable {
    func prettyPrintJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        guard let data = try? encoder.encode(self),
              let output = String(data: data, encoding: .utf8) else {
            return "Error converting to JSON"
        }
        return output
    }
}
