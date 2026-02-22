//
//  Parameter.swift
//  AISDK
//
//  Core tool types, parameter wrapper, and metadata support.
//

import SwiftUI
import Foundation

// MARK: - JSON Type Enum
public enum JSONType: String, Sendable {
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
public final class Parameter<Value: Codable>: @unchecked Sendable {
    public let description: String
    public var wrappedValue: Value
    public let validation: AIParameterValidation?
    internal let explicitRequired: Bool?

    private init(
        wrappedValue: Value,
        description: String,
        validation: AIParameterValidation?,
        required: Bool?
    ) {
        self.description = description
        self.wrappedValue = wrappedValue
        self.validation = validation
        self.explicitRequired = required
    }

    public convenience init(wrappedValue: Value, description: String) {
        self.init(wrappedValue: wrappedValue, description: description, validation: nil, required: nil)
    }

    public convenience init(wrappedValue: Value, description: String, validation: AIParameterValidation) {
        self.init(wrappedValue: wrappedValue, description: description, validation: validation, required: nil)
    }

    public convenience init(wrappedValue: Value, description: String, _ validation: AIParameterValidation) {
        self.init(wrappedValue: wrappedValue, description: description, validation: validation, required: nil)
    }

    public convenience init(wrappedValue: Value, description: String, validation: [String: Any]? = nil) {
        self.init(
            wrappedValue: wrappedValue,
            description: description,
            validation: validation.flatMap(AIParameterValidation.fromDictionary),
            required: nil
        )
    }

    public convenience init(wrappedValue: Value, description: String, required: Bool) {
        self.init(wrappedValue: wrappedValue, description: description, validation: nil, required: required)
    }

    public convenience init(wrappedValue: Value, description: String, validation: AIParameterValidation, required: Bool) {
        self.init(wrappedValue: wrappedValue, description: description, validation: Optional(validation), required: Optional(required))
    }

    public convenience init(wrappedValue: Value, description: String, validation: [String: Any]?, required: Bool) {
        self.init(
            wrappedValue: wrappedValue,
            description: description,
            validation: validation.flatMap(AIParameterValidation.fromDictionary),
            required: required
        )
    }

    public var projectedValue: Parameter<Value> { self }

    /// Helper to dynamically figure out a JSONType from Swift's type
    internal static func inferType(from valueType: Any.Type) -> JSONType {
        if valueType is any RawRepresentable.Type {
            return .string
        }

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

    internal static func inferEnumValues(for valueType: Any.Type) -> [String]? {
        guard let caseIterableType = valueType as? any CaseIterable.Type else {
            return nil
        }

        let cases = caseIterableType.allCases
        var values: [String] = []
        for enumCase in cases {
            let mirror = Mirror(reflecting: enumCase)
            if let rawValue = mirror.children.first(where: { $0.label == "rawValue" })?.value {
                if let stringValue = rawValue as? String {
                    values.append(stringValue)
                    continue
                }
                if let intValue = rawValue as? Int {
                    values.append(String(intValue))
                    continue
                }
                if let doubleValue = rawValue as? Double {
                    values.append(String(doubleValue))
                    continue
                }
            }
            values.append(String(describing: enumCase))
        }

        return values.isEmpty ? nil : values
    }
}

// MARK: - Codable Conformance

extension Parameter: Codable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Value.self)
        self.init(wrappedValue: value, description: "")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

// MARK: - Equatable Conformance

extension Parameter: Equatable where Value: Equatable {
    public static func == (lhs: Parameter<Value>, rhs: Parameter<Value>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue &&
        lhs.description == rhs.description &&
        lhs.validation == rhs.validation
    }
}

// MARK: - Hashable Conformance

extension Parameter: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
        hasher.combine(description)
    }
}

// MARK: - Metadata Types

/// Base protocol for all tool metadata types
public protocol ToolMetadata: Codable, Sendable {}

/// Empty metadata type for tools that don't return metadata
public struct EmptyMetadata: ToolMetadata, Equatable {
    public init() {}
}

/// A universal metadata that signals "this message can render a tool UI"
public struct RenderMetadata: ToolMetadata {
    public let toolName: String
    public let jsonData: Data

    public init(toolName: String, jsonData: Data) {
        self.toolName = toolName
        self.jsonData = jsonData
    }
}

/// Fallback metadata used when the concrete `ToolMetadata` type cannot be resolved at decode time.
public struct RawToolMetadata: ToolMetadata {
    public let originalType: String
    public let payload: AIProxyJSONValue

    public init(originalType: String, payload: AIProxyJSONValue) {
        self.originalType = originalType
        self.payload = payload
    }
}

/// Optional artifacts returned from tool execution.
public struct ToolArtifact: Sendable, Codable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case file
        case image
        case json
        case text
        case other
    }

    public let name: String
    public let kind: Kind
    public let mimeType: String?
    public let data: Data?
    public let url: URL?

    public init(
        name: String,
        kind: Kind,
        mimeType: String? = nil,
        data: Data? = nil,
        url: URL? = nil
    ) {
        self.name = name
        self.kind = kind
        self.mimeType = mimeType
        self.data = data
        self.url = url
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
        self.type = String(reflecting: Swift.type(of: metadata))
        ToolMetadataRegistry.register(instance: metadata)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)

        if let decoderClosure = ToolMetadataRegistry.decoder(for: self.type) {
            let nested = try container.superDecoder(forKey: .metadata)
            self.metadata = try decoderClosure(nested)
            return
        }

        if let anyType = _typeByName(self.type),
           let decodableMetaType = anyType as? Decodable.Type,
           let _ = anyType as? ToolMetadata.Type {
            let nested = try container.superDecoder(forKey: .metadata)
            let anyObject = try decodableMetaType.init(from: nested)
            if let toolMeta = anyObject as? ToolMetadata {
                self.metadata = toolMeta
                return
            }
        }

        if self.type == String(describing: RenderMetadata.self) {
            self.metadata = try container.decode(RenderMetadata.self, forKey: .metadata)
            return
        }

        do {
            let nested = try container.superDecoder(forKey: .metadata)
            let rawValue = try AIProxyJSONValue(from: nested)
            self.metadata = RawToolMetadata(originalType: self.type, payload: rawValue)
            return
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown ToolMetadata type: \(self.type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)

        let nestedEncoder = container.superEncoder(forKey: .metadata)
        try metadata.encode(to: nestedEncoder)
    }
}

// MARK: - Renderable Tool Protocol

public protocol RenderableTool: Tool {
    /// Renders a SwiftUI view given the stored metadata
    /// - Parameter data: raw JSON arguments or any typed object
    /// - Returns: SwiftUI view to embed
    func render(from data: Data) -> AnyView
}

// Default extension (no-op if tool is not renderable)
extension RenderableTool {
    public func render(from data: Data) -> AnyView {
        AnyView(EmptyView())
    }
}

// MARK: - Default Implementations

extension Tool {
    public var returnToolResponse: Bool { false }

    public static func jsonSchema() -> ToolSchema {
        let instance = Self()
        return generateSchemaFromInstance(
            instance,
            toolName: instance.name,
            toolDescription: instance.description
        )
    }

    public static func validate(arguments: [String: Any]) throws {
        let schema = jsonSchema()
        if let required = schema.function?.parameters.required {
            for param in required {
                guard arguments[param] != nil else {
                    throw ToolError.invalidParameters("Missing required parameter: \(param)")
                }
            }
        }
    }

    public mutating func setParameters(from arguments: [String: Any]) throws {
        let mirror = Mirror(reflecting: self)

        let camelCaseArguments = arguments.reduce(into: [String: Any]()) { result, pair in
            let camelCaseKey = pair.key.split(separator: "_")
                .enumerated()
                .map { index, part in
                    index == 0 ? part.lowercased() : part.prefix(1).uppercased() + part.dropFirst().lowercased()
                }
                .joined()
            result[camelCaseKey] = pair.value
        }

        for child in mirror.children {
            guard let label = child.label?.replacingOccurrences(of: "_", with: ""),
                  var parameterObj = child.value as? ParameterSettable else {
                continue
            }

            if let argumentValue = camelCaseArguments[label] {
                try parameterObj.setValue(argumentValue)
            }
        }
    }

    public mutating func validateAndSetParameters(_ argumentsData: Data) throws -> Self {
        let rawString = String(data: argumentsData, encoding: .utf8) ?? ""

        do {
            guard !argumentsData.isEmpty else {
                throw ToolError.invalidParameters("Empty arguments data")
            }

            if let parsed = try? JSONSerialization.jsonObject(with: argumentsData, options: []) as? [String: Any] {
                var tool = self
                try Self.validate(arguments: parsed)
                try tool.setParameters(from: parsed)
                return tool
            }

            let schema = Self.jsonSchema()
            let requiredParams = schema.function?.parameters.required ?? []

            let extractedParams = try extractParametersFromConcatenatedJSON(rawString, requiredParams: requiredParams)
            if !extractedParams.isEmpty {
                var tool = self
                try Self.validate(arguments: extractedParams)
                try tool.setParameters(from: extractedParams)
                return tool
            }

            throw ToolError.invalidParameters("Could not find required parameters in the JSON")
        } catch {
            if let toolError = error as? ToolError {
                throw toolError
            }
            throw ToolError.invalidParameters("Failed to parse JSON: \(error.localizedDescription)")
        }
    }

    private func extractParametersFromConcatenatedJSON(
        _ jsonString: String,
        requiredParams: [String]
    ) throws -> [String: Any] {
        var result: [String: Any] = [:]

        let pattern = "\\{[^\\{\\}]*\\}"
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let nsString = jsonString as NSString
        let matches = regex.matches(in: jsonString, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            let matchRange = match.range
            let jsonSubstring = nsString.substring(with: matchRange)

            if let jsonData = jsonSubstring.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {

                for param in requiredParams {
                    if let value = jsonObject[param] {
                        result[param] = value
                    }
                }

                if requiredParams.allSatisfy({ result[$0] != nil }) {
                    break
                }
            }
        }

        return result
    }
}

// MARK: - Parameter Setting

public protocol ParameterSettable {
    mutating func setValue(_ value: Any) throws
}

extension Parameter: ParameterSettable {
    public func setValue(_ value: Any) throws {
        let resolvedValidation = parameterValidation

        if let enumValues = resolvedValidation?.enumValues,
           let stringValue = value as? String {
            if !enumValues.contains(stringValue) {
                throw ToolError.invalidParameters(
                    "Invalid enum value '\(stringValue)'. Expected one of: \(enumValues.joined(separator: ", "))"
                )
            }
        }

        if let typedValue = value as? Value {
            self.wrappedValue = typedValue
            return
        }

        if let decodedValue = decodeValue(from: value) {
            self.wrappedValue = decodedValue
            return
        }

        throw ToolError.invalidParameters(
            "Expected type \(Value.self), got \(type(of: value))"
        )
    }

    private func decodeValue(from value: Any) -> Value? {
        guard let data = jsonData(for: value) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func jsonData(for value: Any) -> Data? {
        if let stringValue = value as? String {
            return try? JSONEncoder().encode(stringValue)
        }

        if let boolValue = value as? Bool {
            return try? JSONEncoder().encode(boolValue)
        }

        if let numberValue = value as? NSNumber {
            if CFGetTypeID(numberValue) == CFBooleanGetTypeID() {
                return try? JSONEncoder().encode(numberValue.boolValue)
            }
            return try? JSONEncoder().encode(numberValue.doubleValue)
        }

        if let arrayValue = value as? [Any] {
            return try? JSONSerialization.data(withJSONObject: arrayValue, options: [])
        }

        if let dictValue = value as? [String: Any] {
            return try? JSONSerialization.data(withJSONObject: dictValue, options: [])
        }

        return nil
    }
}

// MARK: - Utilities

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

// MARK: - ToolMetadata Registry

fileprivate enum ToolMetadataRegistry {
    private static var _decoders: [String: (Decoder) throws -> ToolMetadata] = [:]
    private static let lock = NSLock()

    static func register<T: ToolMetadata & Decodable>(instance: T) {
        let key = String(reflecting: T.self)
        lock.lock(); defer { lock.unlock() }
        guard _decoders[key] == nil else { return }
        _decoders[key] = { decoder in
            try T(from: decoder)
        }
    }

    static func registerType<T: ToolMetadata & Decodable>(_ type: T.Type) {
        let key = String(reflecting: T.self)
        lock.lock(); defer { lock.unlock() }
        guard _decoders[key] == nil else { return }
        _decoders[key] = { decoder in
            try T(from: decoder)
        }
    }

    static func decoder(for key: String) -> ((Decoder) throws -> ToolMetadata)? {
        lock.lock(); defer { lock.unlock() }
        return _decoders[key]
    }
}

/// Public API for applications to register their custom ToolMetadata types for decoding.
public enum ToolMetadataDecoderRegistry {
    /// Register a concrete `ToolMetadata & Decodable` type so it can be resolved during decoding
    public static func register<T: ToolMetadata & Decodable>(_ type: T.Type) {
        ToolMetadataRegistry.registerType(type)
    }
}
