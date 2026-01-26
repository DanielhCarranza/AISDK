//
//  AIParameter.swift
//  AISDK
//
//  Sendable-compliant property wrapper for AITool parameter definitions.
//  Supports automatic JSON schema generation with validation rules.
//

import Foundation

// MARK: - AIParameterValidation

/// Validation rules for an AIParameter
///
/// Supports enum constraints, numeric ranges, string patterns, and array constraints.
/// All properties are optional - only include validation rules that apply.
public struct AIParameterValidation: Sendable, Equatable {
    /// Valid enum values for string parameters
    public let enumValues: [String]?

    /// Minimum numeric value (inclusive)
    public let minimum: Double?

    /// Maximum numeric value (inclusive)
    public let maximum: Double?

    /// Minimum string length
    public let minLength: Int?

    /// Maximum string length
    public let maxLength: Int?

    /// Regex pattern for string validation
    public let pattern: String?

    /// Minimum array items
    public let minItems: Int?

    /// Maximum array items
    public let maxItems: Int?

    /// Creates validation rules for a parameter.
    ///
    /// - Parameters:
    ///   - enumValues: Valid enum values (for string parameters)
    ///   - minimum: Minimum numeric value (inclusive)
    ///   - maximum: Maximum numeric value (inclusive)
    ///   - minLength: Minimum string length
    ///   - maxLength: Maximum string length
    ///   - pattern: Regex pattern for string validation
    ///   - minItems: Minimum array items
    ///   - maxItems: Maximum array items
    public init(
        enumValues: [String]? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        pattern: String? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil
    ) {
        self.enumValues = enumValues
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.maxLength = maxLength
        self.pattern = pattern
        self.minItems = minItems
        self.maxItems = maxItems
    }

    // MARK: - Factory Methods

    /// Creates enum validation for a set of allowed values.
    ///
    /// - Parameter values: The allowed string values
    /// - Returns: Validation with enum constraint
    public static func enumOf(_ values: String...) -> AIParameterValidation {
        AIParameterValidation(enumValues: values)
    }

    /// Creates numeric range validation.
    ///
    /// - Parameters:
    ///   - min: Minimum value (inclusive)
    ///   - max: Maximum value (inclusive)
    /// - Returns: Validation with range constraint
    public static func range(min: Double? = nil, max: Double? = nil) -> AIParameterValidation {
        AIParameterValidation(minimum: min, maximum: max)
    }

    /// Creates string length validation.
    ///
    /// - Parameters:
    ///   - min: Minimum length
    ///   - max: Maximum length
    /// - Returns: Validation with length constraint
    public static func length(min: Int? = nil, max: Int? = nil) -> AIParameterValidation {
        AIParameterValidation(minLength: min, maxLength: max)
    }

    /// Creates regex pattern validation.
    ///
    /// - Parameter regex: The regex pattern
    /// - Returns: Validation with pattern constraint
    public static func matching(_ regex: String) -> AIParameterValidation {
        AIParameterValidation(pattern: regex)
    }

    /// Creates array size validation.
    ///
    /// - Parameters:
    ///   - min: Minimum items
    ///   - max: Maximum items
    /// - Returns: Validation with array size constraint
    public static func arraySize(min: Int? = nil, max: Int? = nil) -> AIParameterValidation {
        AIParameterValidation(minItems: min, maxItems: max)
    }
}

// MARK: - AIParameterInfo Protocol

/// Protocol for extracting parameter information from property wrappers
public protocol AIParameterInfo: Sendable {
    /// The parameter description for the LLM
    var parameterDescription: String { get }

    /// Optional validation rules
    var parameterValidation: AIParameterValidation? { get }

    /// Whether this parameter is required
    var parameterRequired: Bool { get }

    /// The JSON type name for this parameter
    var jsonTypeName: String { get }
}

// MARK: - AIParameter Property Wrapper

/// A property wrapper for defining AITool parameters with descriptions and validation.
///
/// `@AIParameter` enables automatic JSON schema generation for AITool Arguments structs.
/// It captures description and validation metadata at compile time while maintaining
/// Sendable compliance for concurrent safety.
///
/// ## Basic Usage
/// ```swift
/// struct WeatherArguments: Codable, Sendable {
///     @AIParameter(description: "The city and state, e.g. San Francisco, CA")
///     var location: String
///
///     @AIParameter(
///         description: "Temperature unit",
///         validation: .enumOf("celsius", "fahrenheit")
///     )
///     var unit: String = "celsius"
/// }
/// ```
///
/// ## Numeric Validation
/// ```swift
/// @AIParameter(
///     description: "Number of results to return",
///     validation: .range(min: 1, max: 100)
/// )
/// var count: Int = 10
/// ```
///
/// ## Optional Parameters
/// Optional parameters are automatically marked as non-required in the schema:
/// ```swift
/// @AIParameter(description: "Optional filter")
/// var filter: String?
/// ```
@propertyWrapper
public struct AIParameter<Value: Codable & Sendable>: Sendable {
    /// The wrapped value
    public var wrappedValue: Value

    /// The parameter description for the LLM
    public let description: String

    /// Optional validation rules
    public let validation: AIParameterValidation?

    /// Whether this parameter is explicitly required (nil = infer from type)
    private let explicitRequired: Bool?

    /// Creates an AIParameter with a description.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value
    ///   - description: Description shown to the LLM
    public init(wrappedValue: Value, description: String) {
        self.wrappedValue = wrappedValue
        self.description = description
        self.validation = nil
        self.explicitRequired = nil
    }

    /// Creates an AIParameter with description and validation.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value
    ///   - description: Description shown to the LLM
    ///   - validation: Validation rules for the parameter
    public init(
        wrappedValue: Value,
        description: String,
        validation: AIParameterValidation
    ) {
        self.wrappedValue = wrappedValue
        self.description = description
        self.validation = validation
        self.explicitRequired = nil
    }

    /// Creates an AIParameter with explicit required flag.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value
    ///   - description: Description shown to the LLM
    ///   - required: Whether this parameter is required
    public init(
        wrappedValue: Value,
        description: String,
        required: Bool
    ) {
        self.wrappedValue = wrappedValue
        self.description = description
        self.validation = nil
        self.explicitRequired = required
    }

    /// Creates an AIParameter with all options.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value
    ///   - description: Description shown to the LLM
    ///   - validation: Validation rules for the parameter
    ///   - required: Whether this parameter is required
    public init(
        wrappedValue: Value,
        description: String,
        validation: AIParameterValidation,
        required: Bool
    ) {
        self.wrappedValue = wrappedValue
        self.description = description
        self.validation = validation
        self.explicitRequired = required
    }

    /// Access the parameter wrapper itself via `$paramName`
    public var projectedValue: AIParameter<Value> {
        get { self }
        set { self = newValue }
    }
}

// MARK: - AIParameterInfo Conformance

extension AIParameter: AIParameterInfo {
    public var parameterDescription: String { description }
    public var parameterValidation: AIParameterValidation? { validation }

    public var parameterRequired: Bool {
        if let explicit = explicitRequired {
            return explicit
        }
        // Infer from type - Optional types are not required
        return !isOptionalType(Value.self)
    }

    public var jsonTypeName: String {
        inferJSONType(Value.self)
    }
}

// MARK: - Codable Conformance

extension AIParameter: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.wrappedValue = try container.decode(Value.self)
        self.description = ""
        self.validation = nil
        self.explicitRequired = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

// MARK: - Equatable Conformance

extension AIParameter: Equatable where Value: Equatable {
    public static func == (lhs: AIParameter<Value>, rhs: AIParameter<Value>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue &&
        lhs.description == rhs.description &&
        lhs.validation == rhs.validation
    }
}

// MARK: - Hashable Conformance

extension AIParameter: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
        hasher.combine(description)
    }
}

// MARK: - Type Inference Helpers

/// Check if a type is Optional
private func isOptionalType<T>(_ type: T.Type) -> Bool {
    // Check if the type name contains "Optional"
    let typeName = String(describing: type)
    return typeName.hasPrefix("Optional<") || typeName == "Optional"
}

/// Infer JSON type from Swift type
private func inferJSONType<T>(_ type: T.Type) -> String {
    let typeName = String(describing: type)

    // Handle Optional wrapper
    if typeName.hasPrefix("Optional<") {
        let innerType = String(typeName.dropFirst(9).dropLast())
        return inferJSONTypeFromName(innerType)
    }

    return inferJSONTypeFromName(typeName)
}

/// Infer JSON type from type name string
private func inferJSONTypeFromName(_ typeName: String) -> String {
    switch typeName {
    case "String":
        return "string"
    case "Int", "Int8", "Int16", "Int32", "Int64",
         "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
        return "integer"
    case "Double", "Float", "CGFloat":
        return "number"
    case "Bool":
        return "boolean"
    default:
        if typeName.hasPrefix("Array<") || typeName.hasPrefix("[") {
            return "array"
        }
        if typeName.hasPrefix("Dictionary<") || typeName.hasPrefix("[String:") {
            return "object"
        }
        return "string"
    }
}

// MARK: - AIParameterSchema Protocol

/// Protocol for types that can provide their parameter schema.
///
/// Implement this protocol on your Arguments type to enable automatic
/// schema generation from @AIParameter properties.
///
/// ## Usage
/// ```swift
/// struct WeatherArgs: Codable, Sendable, AIParameterSchema {
///     @AIParameter(description: "The city name")
///     var location: String = ""
///
///     @AIParameter(description: "Temperature unit", validation: .enumOf("celsius", "fahrenheit"))
///     var unit: String = "celsius"
///
///     static var parameterSchemaInfo: [AIParameterSchemaEntry] {
///         [
///             AIParameterSchemaEntry(
///                 name: "location",
///                 jsonType: "string",
///                 description: "The city name",
///                 required: true
///             ),
///             AIParameterSchemaEntry(
///                 name: "unit",
///                 jsonType: "string",
///                 description: "Temperature unit",
///                 required: true,
///                 enumValues: ["celsius", "fahrenheit"]
///             )
///         ]
///     }
/// }
/// ```
public protocol AIParameterSchema {
    /// The parameter schema entries for this type.
    static var parameterSchemaInfo: [AIParameterSchemaEntry] { get }
}

/// An entry in a parameter schema.
public struct AIParameterSchemaEntry: Sendable {
    /// The parameter name (will be converted to snake_case)
    public let name: String

    /// The JSON type name (string, integer, number, boolean, array, object)
    public let jsonType: String

    /// The parameter description for the LLM
    public let description: String

    /// Whether this parameter is required
    public let required: Bool

    /// Optional enum values
    public let enumValues: [String]?

    /// Optional minimum value
    public let minimum: Double?

    /// Optional maximum value
    public let maximum: Double?

    /// Optional minimum length
    public let minLength: Int?

    /// Optional maximum length
    public let maxLength: Int?

    /// Optional regex pattern
    public let pattern: String?

    /// Creates a parameter schema entry.
    public init(
        name: String,
        jsonType: String,
        description: String,
        required: Bool = true,
        enumValues: [String]? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        pattern: String? = nil
    ) {
        self.name = name
        self.jsonType = jsonType
        self.description = description
        self.required = required
        self.enumValues = enumValues
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.maxLength = maxLength
        self.pattern = pattern
    }

    /// Creates an entry from an AIParameterInfo.
    public init(name: String, from info: AIParameterInfo) {
        self.name = name
        self.jsonType = info.jsonTypeName
        self.description = info.parameterDescription
        self.required = info.parameterRequired
        self.enumValues = info.parameterValidation?.enumValues
        self.minimum = info.parameterValidation?.minimum
        self.maximum = info.parameterValidation?.maximum
        self.minLength = info.parameterValidation?.minLength
        self.maxLength = info.parameterValidation?.maxLength
        self.pattern = info.parameterValidation?.pattern
    }
}

// MARK: - Schema Generation

/// Generate a ToolSchema from parameter schema entries.
///
/// - Parameters:
///   - entries: The parameter schema entries
///   - toolName: The tool name for the schema
///   - toolDescription: The tool description for the schema
/// - Returns: A complete ToolSchema for LLM function calling
public func generateSchemaFromEntries(
    _ entries: [AIParameterSchemaEntry],
    toolName: String,
    toolDescription: String
) -> ToolSchema {
    var properties: [String: PropertyDefinition] = [:]
    var required: [String] = []

    for entry in entries {
        let snakeCaseName = camelCaseToSnakeCase(entry.name)

        let propertyDef = PropertyDefinition(
            type: entry.jsonType,
            description: entry.description,
            minimum: entry.minimum,
            maximum: entry.maximum,
            minLength: entry.minLength,
            maxLength: entry.maxLength,
            pattern: entry.pattern,
            enumValues: entry.enumValues
        )

        properties[snakeCaseName] = propertyDef

        if entry.required {
            required.append(snakeCaseName)
        }
    }

    return ToolSchema(
        type: "function",
        function: ToolFunction(
            name: toolName,
            description: toolDescription,
            parameters: Parameters(
                type: "object",
                properties: properties,
                required: required.isEmpty ? nil : required,
                additionalProperties: false
            )
        )
    )
}

/// Generate a ToolSchema from an AIParameterSchema conforming type.
///
/// - Parameters:
///   - argumentsType: The Arguments type that conforms to AIParameterSchema
///   - toolName: The tool name for the schema
///   - toolDescription: The tool description for the schema
/// - Returns: A complete ToolSchema for LLM function calling
public func generateSchemaFromAIParameters<T: AIParameterSchema>(
    _ argumentsType: T.Type,
    toolName: String,
    toolDescription: String
) -> ToolSchema {
    generateSchemaFromEntries(
        T.parameterSchemaInfo,
        toolName: toolName,
        toolDescription: toolDescription
    )
}

/// Generate a ToolSchema by reflecting on an instance.
///
/// This function uses Mirror to inspect an Arguments struct instance and extract
/// @AIParameter metadata to build a complete JSON schema. The instance must have
/// all @AIParameter properties properly initialized with their metadata.
///
/// - Parameters:
///   - instance: An instance of the Arguments type to reflect
///   - toolName: The tool name for the schema
///   - toolDescription: The tool description for the schema
/// - Returns: A complete ToolSchema for LLM function calling
public func generateSchemaFromInstance<T>(
    _ instance: T,
    toolName: String,
    toolDescription: String
) -> ToolSchema {
    let mirror = Mirror(reflecting: instance)

    var properties: [String: PropertyDefinition] = [:]
    var required: [String] = []

    for child in mirror.children {
        guard let label = child.label else { continue }

        // Remove underscore prefix from property wrapper backing storage
        let paramName = label.hasPrefix("_") ? String(label.dropFirst()) : label

        // Convert to snake_case for JSON schema
        let snakeCaseName = camelCaseToSnakeCase(paramName)

        // Check if this is an AIParameter wrapper
        if let paramInfo = child.value as? AIParameterInfo {
            let propertyDef = PropertyDefinition(
                type: paramInfo.jsonTypeName,
                description: paramInfo.parameterDescription,
                minimum: paramInfo.parameterValidation?.minimum,
                maximum: paramInfo.parameterValidation?.maximum,
                minLength: paramInfo.parameterValidation?.minLength,
                maxLength: paramInfo.parameterValidation?.maxLength,
                pattern: paramInfo.parameterValidation?.pattern,
                enumValues: paramInfo.parameterValidation?.enumValues
            )

            properties[snakeCaseName] = propertyDef

            if paramInfo.parameterRequired {
                required.append(snakeCaseName)
            }
        }
    }

    return ToolSchema(
        type: "function",
        function: ToolFunction(
            name: toolName,
            description: toolDescription,
            parameters: Parameters(
                type: "object",
                properties: properties,
                required: required.isEmpty ? nil : required,
                additionalProperties: false
            )
        )
    )
}

/// Convert camelCase to snake_case
private func camelCaseToSnakeCase(_ input: String) -> String {
    var result = ""
    for (index, char) in input.enumerated() {
        if char.isUppercase {
            if index > 0 {
                result += "_"
            }
            result += char.lowercased()
        } else {
            result += String(char)
        }
    }
    return result
}
