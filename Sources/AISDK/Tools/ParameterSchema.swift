//
//  ParameterSchema.swift
//  AISDK
//
//  Validation helpers and schema generation for @Parameter.
//

import Foundation

// MARK: - AIParameterValidation

/// Validation rules for a parameter.
///
/// Supports enum constraints, numeric ranges, string patterns, and array constraints.
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
    public static func enumOf(_ values: String...) -> AIParameterValidation {
        AIParameterValidation(enumValues: values)
    }

    /// Creates enum validation from a CaseIterable String-backed enum.
    public static func enumOf<T: CaseIterable & RawRepresentable>(_ type: T.Type) -> AIParameterValidation where T.RawValue == String {
        AIParameterValidation(enumValues: type.allCases.map { $0.rawValue })
    }

    /// Creates numeric range validation.
    public static func range(min: Double? = nil, max: Double? = nil) -> AIParameterValidation {
        AIParameterValidation(minimum: min, maximum: max)
    }

    /// Creates numeric range validation from an Int range.
    public static func range(_ range: ClosedRange<Int>) -> AIParameterValidation {
        AIParameterValidation(minimum: Double(range.lowerBound), maximum: Double(range.upperBound))
    }

    /// Creates numeric range validation from a Double range.
    public static func range(_ range: ClosedRange<Double>) -> AIParameterValidation {
        AIParameterValidation(minimum: range.lowerBound, maximum: range.upperBound)
    }

    /// Creates string length validation.
    public static func length(min: Int? = nil, max: Int? = nil) -> AIParameterValidation {
        AIParameterValidation(minLength: min, maxLength: max)
    }

    /// Creates regex pattern validation.
    public static func matching(_ regex: String) -> AIParameterValidation {
        AIParameterValidation(pattern: regex)
    }

    /// Creates array size validation.
    public static func arraySize(min: Int? = nil, max: Int? = nil) -> AIParameterValidation {
        AIParameterValidation(minItems: min, maxItems: max)
    }

    // MARK: - Internal helpers

    internal static func fromDictionary(_ dictionary: [String: Any]) -> AIParameterValidation? {
        let enumValues = dictionary["enum"] as? [String]
        let minimum = dictionary["minimum"] as? Double
        let maximum = dictionary["maximum"] as? Double
        let minLength = dictionary["minLength"] as? Int
        let maxLength = dictionary["maxLength"] as? Int
        let pattern = dictionary["pattern"] as? String
        let minItems = dictionary["minItems"] as? Int
        let maxItems = dictionary["maxItems"] as? Int

        if enumValues == nil,
           minimum == nil,
           maximum == nil,
           minLength == nil,
           maxLength == nil,
           pattern == nil,
           minItems == nil,
           maxItems == nil {
            return nil
        }

        return AIParameterValidation(
            enumValues: enumValues,
            minimum: minimum,
            maximum: maximum,
            minLength: minLength,
            maxLength: maxLength,
            pattern: pattern,
            minItems: minItems,
            maxItems: maxItems
        )
    }

    internal func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let enumValues = enumValues { dict["enum"] = enumValues }
        if let minimum = minimum { dict["minimum"] = minimum }
        if let maximum = maximum { dict["maximum"] = maximum }
        if let minLength = minLength { dict["minLength"] = minLength }
        if let maxLength = maxLength { dict["maxLength"] = maxLength }
        if let pattern = pattern { dict["pattern"] = pattern }
        if let minItems = minItems { dict["minItems"] = minItems }
        if let maxItems = maxItems { dict["maxItems"] = maxItems }
        return dict
    }

    internal func mergingEnumValues(_ values: [String]) -> AIParameterValidation {
        if let enumValues = enumValues, !enumValues.isEmpty {
            return self
        }

        return AIParameterValidation(
            enumValues: values,
            minimum: minimum,
            maximum: maximum,
            minLength: minLength,
            maxLength: maxLength,
            pattern: pattern,
            minItems: minItems,
            maxItems: maxItems
        )
    }
}

// MARK: - AIParameterInfo Protocol

/// Protocol for extracting parameter information from property wrappers.
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

// MARK: - Parameter Conformance

extension Parameter: AIParameterInfo {
    public var parameterDescription: String { description }

    public var parameterValidation: AIParameterValidation? {
        let inferred = Self.inferEnumValues(for: Value.self)
        guard let validation = validation else {
            return inferred.map { AIParameterValidation(enumValues: $0) }
        }
        if let inferred {
            return validation.mergingEnumValues(inferred)
        }
        return validation
    }

    public var parameterRequired: Bool {
        if let explicitRequired {
            return explicitRequired
        }
        return !isOptionalType(Value.self)
    }

    public var jsonTypeName: String {
        inferJSONType(Value.self)
    }
}

// MARK: - Type Inference Helpers

/// Check if a type is Optional
private func isOptionalType<T>(_ type: T.Type) -> Bool {
    let typeName = String(describing: type)
    return typeName.hasPrefix("Optional<") || typeName == "Optional"
}

/// Infer JSON type from Swift type
private func inferJSONType<T>(_ type: T.Type) -> String {
    // Treat enums as strings by default
    if type is any RawRepresentable.Type {
        return "string"
    }

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
/// schema generation from @Parameter properties.
public protocol AIParameterSchema {
    /// The parameter schema entries for this type.
    static var parameterSchemaInfo: [AIParameterSchemaEntry] { get }
}

/// An entry in a parameter schema.
public struct AIParameterSchemaEntry: Sendable {
    public let name: String
    public let jsonType: String
    public let description: String
    public let required: Bool
    public let enumValues: [String]?
    public let minimum: Double?
    public let maximum: Double?
    public let minLength: Int?
    public let maxLength: Int?
    public let pattern: String?

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

        let paramName = label.hasPrefix("_") ? String(label.dropFirst()) : label
        let snakeCaseName = camelCaseToSnakeCase(paramName)

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
