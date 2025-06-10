//
//  Person.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 30/12/24.
//


import Foundation

/**
 Swift JSON Schema Generator
 
 A lightweight and powerful library for automatically generating JSON Schema definitions
 from Swift structs. This library provides a declarative way to define schema metadata
 using property wrappers, similar to Python's Pydantic.
 
 Basic usage example:
 ```swift
 struct Person: JSONSchemaModel, ExpressibleByEmptyInit {
     @Field(description: "Full name of the person")
     let name: String
     
     @Field(
         description: "Age in years",
         validation: ["minimum": 0, "maximum": 120]
     )
     let age: Int
 }
 
 // Generate schema
 let schema = Person.generateJSONSchema()
 ```
 */

/**
 Property wrapper for field definitions with metadata.
 
 This wrapper allows you to add descriptions, validation rules, and format specifications
 to your struct properties.
 
 Example usage:
 ```swift
 struct User: JSONSchemaModel, ExpressibleByEmptyInit {
     @Field(
         description: "User's email address",
         validation: ["pattern": "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"],
         format: "email"
     )
     let email: String
 }
 ```
 */
import Foundation

// MARK: - 1) Field Property Wrapper

/// A property wrapper that stores metadata for JSON Schema generation.
/// Also made Codable, so that 'struct' containing Field<Value: Codable> can be synthesized as Codable.
@propertyWrapper
public struct Field<Value: Codable>: Codable {
    public let description: String?
    public let validation: [String: ValidationValue]?
    public var wrappedValue: Value

    public init(
        wrappedValue: Value,
        description: String? = nil,
        validation: [String: ValidationValue]? = nil
    ) {
        self.wrappedValue = wrappedValue
        self.description = description
        self.validation = validation
    }

    // MARK: - Codable conformance for the property wrapper
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.wrappedValue = try container.decode(Value.self)
        // Since metadata doesn't appear in actual JSON data, we store no metadata here.
        self.description = nil
        self.validation = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

// MARK: - 2) FieldProtocol

public protocol FieldProtocol {
    var fieldDescription: String? { get }
    var validationDict: [String: ValidationValue]? { get }
    var valueType: Any.Type { get }
}

extension Field: FieldProtocol {
    public var fieldDescription: String? { description }
    public var validationDict: [String: ValidationValue]? { validation }
    public var valueType: Any.Type { Value.self }
}

// MARK: - 3) JSONSchema Builders

public struct JSONSchema: Encodable {
    public let rawValue: [String: AnyEncodable]

    public init(rawValue: [String: AnyEncodable]) {
        self.rawValue = rawValue
    }
    
    public func encode(to encoder: Encoder) throws {
        try rawValue.encode(to: encoder)
    }

    public static func object(
        title: String? = nil,
        description: String? = nil,
        properties: [String: JSONSchema],
        required: [String] = [],
        additionalProperties: Bool = false
    ) -> JSONSchema {
        var schema: [String: AnyEncodable] = [
            "type": AnyEncodable("object"),
            "properties": AnyEncodable(properties.mapValues { $0.rawValue }),
            "additionalProperties": AnyEncodable(additionalProperties)
        ]

        if !required.isEmpty {
            schema["required"] = AnyEncodable(required)
        }

        title.map { schema["title"] = AnyEncodable($0) }
        description.map { schema["description"] = AnyEncodable($0) }

        return JSONSchema(rawValue: schema)
    }

    public static func string(
        description: String? = nil,
        validation: [String: ValidationValue]? = nil
    ) -> JSONSchema {
        var schema: [String: AnyEncodable] = ["type": AnyEncodable("string")]
        if let description = description {
            schema["description"] = AnyEncodable(description)
        }
        if let validation = validation {
            for (key, value) in validation {
                schema[key] = AnyEncodable(value)
            }
        }
        return JSONSchema(rawValue: schema)
    }

    public static func integer(
        description: String? = nil,
        validation: [String: ValidationValue]? = nil
    ) -> JSONSchema {
        var schema: [String: AnyEncodable] = ["type": AnyEncodable("integer")]
        if let description = description {
            schema["description"] = AnyEncodable(description)
        }
        if let validation = validation {
            for (key, value) in validation {
                schema[key] = AnyEncodable(value)
            }
        }
        return JSONSchema(rawValue: schema)
    }

    public static func number(
        description: String? = nil,
        validation: [String: ValidationValue]? = nil
    ) -> JSONSchema {
        var schema: [String: AnyEncodable] = ["type": AnyEncodable("number")]
        if let description = description {
            schema["description"] = AnyEncodable(description)
        }
        if let validation = validation {
            for (key, value) in validation {
                schema[key] = AnyEncodable(value)
            }
        }
        return JSONSchema(rawValue: schema)
    }

    public static func boolean(
        description: String? = nil
    ) -> JSONSchema {
        var schema: [String: AnyEncodable] = ["type": AnyEncodable("boolean")]
        if let description = description {
            schema["description"] = AnyEncodable(description)
        }
        return JSONSchema(rawValue: schema)
    }

    public static func array(
        description: String? = nil,
        items: JSONSchema,
        validation: [String: ValidationValue]? = nil
    ) -> JSONSchema {
        var schema: [String: AnyEncodable] = [
            "type": AnyEncodable("array"),
            "items": AnyEncodable(items.rawValue)
        ]
        if let description = description {
            schema["description"] = AnyEncodable(description)
        }
        if let validation = validation {
            for (key, value) in validation {
                schema[key] = AnyEncodable(value)
            }
        }
        return JSONSchema(rawValue: schema)
    }

    private static func applyCommonValidations(
        _ validation: [String: Any]?,
        to schema: inout [String: Any]
    ) {
        guard let validation = validation else { return }

        for (key, value) in validation {
            switch key {
            case "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
                 "multipleOf", "minLength", "maxLength", "pattern",
                 "format", "enum":
                schema[key] = value
            default:
                break
            }
        }
    }

    private static func applyArrayValidations(
        _ validation: [String: Any]?,
        to schema: inout [String: Any]
    ) {
        guard let validation = validation else { return }

        for (key, value) in validation {
            switch key {
            case "minItems", "maxItems", "uniqueItems":
                schema[key] = value
            default:
                break
            }
        }
    }
}

// MARK: - 4) ArrayConforming

public protocol ArrayConforming {
    static var elementType: Any.Type { get }
}

extension Array: ArrayConforming {
    public static var elementType: Any.Type { Element.self }
}

// MARK: - 5) JSONSchemaModel Protocol

public protocol JSONSchemaModel: Codable {
    init()
    
    // Instance method for creating schema with metadata
    func generateJSONSchema() -> JSONSchema
    
    // Static method remains for backward compatibility
    static func generateJSONSchema(
        title: String?,
        description: String?
    ) -> JSONSchema
    
    // Add this back
    static func generatePropertiesSchema() -> (properties: [String: JSONSchema], required: [String])
}

// Default implementations
public extension JSONSchemaModel {
    // New instance method
    func generateJSONSchema() -> JSONSchema {
        let (props, reqs) = Self.generatePropertiesSchema()
        return JSONSchema.object(
            title: nil,  // These could be properties of your type if desired
            description: nil,
            properties: props,
            required: reqs
        )
    }
    
    // Existing static method
    static func generateJSONSchema(
        title: String? = nil,
        description: String? = nil
    ) -> JSONSchema {
        let (props, reqs) = generatePropertiesSchema()
        return JSONSchema.object(
            title: title,
            description: description,
            properties: props,
            required: reqs
        )
    }
    
    // Add the implementation back
    static func generatePropertiesSchema() -> (properties: [String: JSONSchema], required: [String]) {
        let instance = Self.init()
        let mirror = Mirror(reflecting: instance)
        var properties: [String: JSONSchema] = [:]
        var requiredProps: [String] = []

        for child in mirror.children {
            // Remove underscore prefix from property wrapper names
            guard let propName = child.label?.replacingOccurrences(of: "_", with: "") else { continue }
            
            // First unwrap the property wrapper
            let fieldMirror = Mirror(reflecting: child.value)
            guard let propertyWrapper = fieldMirror.children.first(where: { $0.label == "wrappedValue" }) else {
                continue
            }
            
            // Then check if the wrapped value is optional
            let (_, isOptional) = unwrapIfOptional(Mirror(reflecting: propertyWrapper.value))
            guard let fieldWrapper = child.value as? FieldProtocol else {
                continue
            }

            // If not optional, add to required list
            if !isOptional {
                requiredProps.append(propName)
            }

            let propSchema = schemaForProperty(
                fieldWrapper: fieldWrapper,
                isOptional: isOptional
            )
            properties[propName] = propSchema
        }

        return (properties, requiredProps)
    }
}

// MARK: - 6) Reflection Helpers

private func unwrapIfOptional(_ mirror: Mirror) -> (Any, Bool) {
    if mirror.displayStyle == .optional, let child = mirror.children.first {
        return (child.value, true)
    }
    return (mirror.subjectType, false)
}

private func createEmptyInstance<T: JSONSchemaModel>(of type: T.Type) throws -> T {
    return T.init()
}

/// Protocol for Swift structs that have an init() with no arguments.
public protocol ExpressibleByEmptyInit {
    init()
}

extension ExpressibleByEmptyInit where Self: Any {
    public init() { self.init() }
}

/// Build the JSON schema for a given field using its Swift type, metadata, etc.
private func schemaForProperty(fieldWrapper: FieldProtocol, isOptional: Bool) -> JSONSchema {
    // If the property is a nested JSONSchemaModel:
    if let nestedModelType = fieldWrapper.valueType as? JSONSchemaModel.Type {
        return nestedModelType.generateJSONSchema()
    }
    // If it's an array:
    if let arrayType = fieldWrapper.valueType as? ArrayConforming.Type {
        return generateArraySchema(
            elementType: arrayType.elementType,
            description: fieldWrapper.fieldDescription,
            validation: fieldWrapper.validationDict
        )
    }

    // Otherwise, figure out the basic type
    switch String(describing: fieldWrapper.valueType) {
    case "String":
        return .string(description: fieldWrapper.fieldDescription,
                       validation: fieldWrapper.validationDict)
    case "Int":
        return .integer(description: fieldWrapper.fieldDescription,
                        validation: fieldWrapper.validationDict)
    case "Double", "Float":
        return .number(description: fieldWrapper.fieldDescription,
                       validation: fieldWrapper.validationDict)
    case "Bool":
        return .boolean(description: fieldWrapper.fieldDescription)
    default:
        // fallback
        return .string(description: fieldWrapper.fieldDescription)
    }
}

private func generateArraySchema(
    elementType: Any.Type,
    description: String?,
    validation: [String: ValidationValue]?
) -> JSONSchema {
    if let nestedModelType = elementType as? JSONSchemaModel.Type {
        let itemsSchema = nestedModelType.generateJSONSchema()
        return .array(description: description, items: itemsSchema, validation: validation)
    }
    // If it's a basic type
    switch String(describing: elementType) {
    case "String":
        return .array(description: description, items: .string(), validation: validation)
    case "Int":
        return .array(description: description, items: .integer(), validation: validation)
    case "Double", "Float":
        return .array(description: description, items: .number(), validation: validation)
    case "Bool":
        return .array(description: description, items: .boolean(), validation: validation)
    default:
        // fallback
        return .array(description: description, items: .string(), validation: validation)
    }
}

// MARK: - 7) Example Models
/*
/// Make our structs adopt `ExpressibleByEmptyInit` so that `createEmptyInstance(...)` can call `init()`.
public struct Address: JSONSchemaModel {
    // Provide default values to fix "Missing argument for parameter 'wrappedValue'"
    @Field(description: "Street address") public var street = ""
    @Field(description: "City name")      public var city   = ""
    @Field(description: "Country name")   public var country = ""

    @Field(description: "Postal code", validation: [
        "pattern": "^[0-9]{5}(-[0-9]{4})?$"
    ]) public var postalCode = ""

    // The no-arguments init needed by reflection:
    public init() { }
}

public struct User: JSONSchemaModel {
    @Field(description: "The unique identifier for a user", validation: [
        "minimum": 1
    ]) public var id = 0

    @Field(description: "The user's full name", validation: [
        "minLength": 1,
        "maxLength": 100
    ]) public var name = ""

    @Field(description: "The user's email address", validation: [
        "format": "email",
        "pattern": "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
    ]) public var email = ""

    // Optional
    @Field(description: "The user's age", validation: [
        "minimum": 0,
        "maximum": 150
    ]) public var age: Int? = nil

    // An array of nested JSONSchemaModels
    @Field(description: "User's addresses") public var addresses: [Address] = []

    public init() { }
}

// MARK: - 8) Testing in a Playground

let userSchema = User.generateJSONSchema(
    title: "User",
    description: "A user in the system"
)

if let jsonData = try? JSONSerialization.data(
    withJSONObject: userSchema.rawValue,
    options: .prettyPrinted
),
   let jsonString = String(data: jsonData, encoding: .utf8) {
    print(jsonString)
}
*/

public protocol SchemaBuilding {
    func build() -> JSONSchema
}

public struct SchemaBuilder<T: JSONSchemaModel>: SchemaBuilding {
    private let model: T
    private var title: String?
    private var description: String?
    
    public init(_ model: T) {
        self.model = model
    }
    
    public func title(_ title: String) -> SchemaBuilder<T> {
        var copy = self
        copy.title = title
        return copy
    }
    
    public func description(_ description: String) -> SchemaBuilder<T> {
        var copy = self
        copy.description = description
        return copy
    }
    
    public func build() -> JSONSchema {
        let (props, reqs) = T.generatePropertiesSchema()
        return JSONSchema.object(
            title: title,
            description: description,
            properties: props,
            required: reqs
        )
    }
}

// Add convenience method to JSONSchemaModel
public extension JSONSchemaModel {
    static func schema() -> SchemaBuilder<Self> {
        SchemaBuilder(Self.init())
    }
}

// First, let's define what validation values can be
public enum ValidationValue: Encodable {
    case string(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case array([ValidationValue])
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        }
    }
}
