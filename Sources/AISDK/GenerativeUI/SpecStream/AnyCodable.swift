//
//  SpecValue.swift
//  AISDK
//
//  Type-erased Codable wrapper for JSON-compatible values in UI specs.
//  Used by SpecPatch to represent arbitrary patch values with null support.
//

import Foundation

/// A type-erased wrapper for JSON-compatible values in UI specs.
///
/// Supports: String, Int, Double, Bool, [SpecValue], [String: SpecValue], and nil.
/// Used as the `value` type in `SpecPatch` operations.
///
/// Unlike the existing `AnyCodable` (in ResponseObject.swift), `SpecValue`:
/// - Supports explicit null values (important for JSON Patch "replace with null")
/// - Preserves nested structure (doesn't unwrap to raw `Any`)
/// - Conforms to ExpressibleBy literals for ergonomic test writing
public struct SpecValue: Sendable, Equatable, Codable {
    /// The underlying value
    public let value: Any?

    // MARK: - Convenience Initializers

    public init(_ value: Any?) {
        self.value = value
    }

    public init(_ string: String) { self.value = string }
    public init(_ int: Int) { self.value = int }
    public init(_ double: Double) { self.value = double }
    public init(_ bool: Bool) { self.value = bool }
    public init(_ array: [SpecValue]) { self.value = array }
    public init(_ dictionary: [String: SpecValue]) { self.value = dictionary }

    /// Nil value
    public static let null = SpecValue(nil)

    // MARK: - Value Accessors

    public var stringValue: String? { value as? String }
    public var intValue: Int? { value as? Int }
    public var doubleValue: Double? { value as? Double }
    public var boolValue: Bool? { value as? Bool }
    public var arrayValue: [SpecValue]? { value as? [SpecValue] }
    public var dictionaryValue: [String: SpecValue]? { value as? [String: SpecValue] }
    public var isNull: Bool { value == nil }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = nil
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([SpecValue].self) {
            self.value = array
        } else if let dict = try? container.decode([String: SpecValue].self) {
            self.value = dict
        } else {
            throw DecodingError.typeMismatch(
                SpecValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported JSON value type"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case nil:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [SpecValue]:
            try container.encode(array)
        case let dict as [String: SpecValue]:
            try container.encode(dict)
        default:
            throw EncodingError.invalidValue(
                value as Any,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Unsupported value type: \(type(of: value))"
                )
            )
        }
    }

    // MARK: - Equatable

    public static func == (lhs: SpecValue, rhs: SpecValue) -> Bool {
        switch (lhs.value, rhs.value) {
        case (nil, nil):
            return true
        case (let l as Bool, let r as Bool):
            return l == r
        case (let l as Int, let r as Int):
            return l == r
        case (let l as Double, let r as Double):
            return l == r
        case (let l as String, let r as String):
            return l == r
        case (let l as [SpecValue], let r as [SpecValue]):
            return l == r
        case (let l as [String: SpecValue], let r as [String: SpecValue]):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - ExpressibleBy Literals

extension SpecValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.value = value }
}

extension SpecValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self.value = value }
}

extension SpecValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self.value = value }
}

extension SpecValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self.value = value }
}

extension SpecValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self.value = nil }
}

extension SpecValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: SpecValue...) {
        self.value = elements
    }
}

extension SpecValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, SpecValue)...) {
        self.value = Dictionary(uniqueKeysWithValues: elements)
    }
}
