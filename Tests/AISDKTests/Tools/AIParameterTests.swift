//
//  AIParameterTests.swift
//  AISDKTests
//
//  Tests for the @AIParameter property wrapper and schema generation.
//

import XCTest
@testable import AISDK

final class AIParameterTests: XCTestCase {

    // MARK: - Basic Property Wrapper Tests

    func testBasicParameter() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(description: "A test string")
            var testString: String = ""
        }

        let args = TestArgs()
        XCTAssertEqual(args.testString, "")
        XCTAssertEqual(args.$testString.description, "A test string")
        XCTAssertNil(args.$testString.validation)
        XCTAssertTrue(args.$testString.parameterRequired)
    }

    func testParameterWithDefaultValue() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(description: "Temperature unit")
            var unit: String = "celsius"
        }

        let args = TestArgs()
        XCTAssertEqual(args.unit, "celsius")
    }

    func testParameterWithEnumValidation() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(
                description: "Temperature unit",
                validation: .enumOf("celsius", "fahrenheit", "kelvin")
            )
            var unit: String = "celsius"
        }

        let args = TestArgs()
        XCTAssertEqual(args.$unit.validation?.enumValues, ["celsius", "fahrenheit", "kelvin"])
    }

    func testParameterWithRangeValidation() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(
                description: "Number of results",
                validation: .range(min: 1, max: 100)
            )
            var count: Int = 10
        }

        let args = TestArgs()
        XCTAssertEqual(args.$count.validation?.minimum, 1)
        XCTAssertEqual(args.$count.validation?.maximum, 100)
    }

    func testParameterWithLengthValidation() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(
                description: "Username",
                validation: .length(min: 3, max: 20)
            )
            var username: String = ""
        }

        let args = TestArgs()
        XCTAssertEqual(args.$username.validation?.minLength, 3)
        XCTAssertEqual(args.$username.validation?.maxLength, 20)
    }

    func testParameterWithPatternValidation() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(
                description: "Email address",
                validation: .matching("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$")
            )
            var email: String = ""
        }

        let args = TestArgs()
        XCTAssertNotNil(args.$email.validation?.pattern)
    }

    // MARK: - Type Inference Tests

    func testStringTypeInference() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(description: "Test")
            var value: String = ""
        }

        let args = TestArgs()
        XCTAssertEqual(args.$value.jsonTypeName, "string")
    }

    func testIntegerTypeInference() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(description: "Test")
            var value: Int = 0
        }

        let args = TestArgs()
        XCTAssertEqual(args.$value.jsonTypeName, "integer")
    }

    func testNumberTypeInference() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(description: "Test")
            var value: Double = 0.0
        }

        let args = TestArgs()
        XCTAssertEqual(args.$value.jsonTypeName, "number")
    }

    func testBooleanTypeInference() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(description: "Test")
            var value: Bool = false
        }

        let args = TestArgs()
        XCTAssertEqual(args.$value.jsonTypeName, "boolean")
    }

    // MARK: - Codable Tests

    func testCodableRoundtrip() throws {
        struct TestArgs: Codable, Sendable, Equatable {
            @AIParameter(description: "Location")
            var location: String = ""

            @AIParameter(description: "Unit")
            var unit: String = "celsius"

            static func == (lhs: TestArgs, rhs: TestArgs) -> Bool {
                lhs.location == rhs.location && lhs.unit == rhs.unit
            }
        }

        var original = TestArgs()
        original.location = "San Francisco"
        original.unit = "fahrenheit"

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TestArgs.self, from: encoded)

        XCTAssertEqual(original, decoded)
    }

    func testDecodingFromJSON() throws {
        struct TestArgs: Codable, Sendable {
            @AIParameter(description: "Location")
            var location: String = ""

            @AIParameter(description: "Unit")
            var unit: String = "celsius"
        }

        let json = """
        {"location": "Tokyo", "unit": "celsius"}
        """

        let args = try JSONDecoder().decode(TestArgs.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(args.location, "Tokyo")
        XCTAssertEqual(args.unit, "celsius")
    }

    // MARK: - Schema Generation Tests

    func testSchemaGenerationBasicWithInstance() {
        struct WeatherArgs: Codable, Sendable {
            @AIParameter(description: "The city name")
            var location: String = ""
        }

        // Create an instance to reflect
        let args = WeatherArgs()

        let schema = generateSchemaFromInstance(
            args,
            toolName: "get_weather",
            toolDescription: "Get weather for a location"
        )

        XCTAssertEqual(schema.type, "function")
        XCTAssertEqual(schema.function?.name, "get_weather")
        XCTAssertEqual(schema.function?.description, "Get weather for a location")
        XCTAssertNotNil(schema.function?.parameters.properties["location"])
    }

    func testSchemaGenerationWithProtocol() {
        struct WeatherArgs: Codable, Sendable, AIParameterSchema {
            @AIParameter(description: "The city name")
            var location: String = ""

            static var parameterSchemaInfo: [AIParameterSchemaEntry] {
                [
                    AIParameterSchemaEntry(
                        name: "location",
                        jsonType: "string",
                        description: "The city name",
                        required: true
                    )
                ]
            }
        }

        let schema = generateSchemaFromAIParameters(
            WeatherArgs.self,
            toolName: "get_weather",
            toolDescription: "Get weather for a location"
        )

        XCTAssertEqual(schema.type, "function")
        XCTAssertEqual(schema.function?.name, "get_weather")
        XCTAssertEqual(schema.function?.description, "Get weather for a location")
        XCTAssertNotNil(schema.function?.parameters.properties["location"])
        XCTAssertEqual(schema.function?.parameters.properties["location"]?.description, "The city name")
    }

    func testSchemaGenerationWithValidation() {
        struct SearchArgs: Codable, Sendable {
            @AIParameter(
                description: "Number of results",
                validation: .range(min: 1, max: 100)
            )
            var count: Int = 10

            @AIParameter(
                description: "Sort order",
                validation: .enumOf("asc", "desc")
            )
            var order: String = "asc"
        }

        // Create instance for reflection
        let args = SearchArgs()

        let schema = generateSchemaFromInstance(
            args,
            toolName: "search",
            toolDescription: "Search for items"
        )

        let countProp = schema.function?.parameters.properties["count"]
        XCTAssertEqual(countProp?.minimum, 1)
        XCTAssertEqual(countProp?.maximum, 100)

        let orderProp = schema.function?.parameters.properties["order"]
        XCTAssertEqual(orderProp?.enumValues, ["asc", "desc"])
    }

    func testSnakeCaseConversion() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(description: "User name")
            var userName: String = ""

            @AIParameter(description: "Max results")
            var maxResultCount: Int = 10
        }

        let args = TestArgs()

        let schema = generateSchemaFromInstance(
            args,
            toolName: "test",
            toolDescription: "Test"
        )

        // Verify snake_case conversion
        XCTAssertNotNil(schema.function?.parameters.properties["user_name"])
        XCTAssertNotNil(schema.function?.parameters.properties["max_result_count"])
    }

    func testSchemaGenerationFromEntries() {
        let entries = [
            AIParameterSchemaEntry(
                name: "location",
                jsonType: "string",
                description: "The city name",
                required: true
            ),
            AIParameterSchemaEntry(
                name: "unit",
                jsonType: "string",
                description: "Temperature unit",
                required: true,
                enumValues: ["celsius", "fahrenheit"]
            ),
            AIParameterSchemaEntry(
                name: "count",
                jsonType: "integer",
                description: "Number of results",
                required: false,
                minimum: 1,
                maximum: 100
            )
        ]

        let schema = generateSchemaFromEntries(
            entries,
            toolName: "weather",
            toolDescription: "Get weather"
        )

        XCTAssertEqual(schema.function?.name, "weather")
        XCTAssertEqual(schema.function?.parameters.properties.count, 3)
        XCTAssertEqual(schema.function?.parameters.properties["unit"]?.enumValues, ["celsius", "fahrenheit"])
        XCTAssertEqual(schema.function?.parameters.properties["count"]?.minimum, 1)
        XCTAssertEqual(schema.function?.parameters.required, ["location", "unit"])
    }

    // MARK: - Required Parameter Tests

    func testRequiredParameterInference() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(description: "Required field")
            var requiredField: String = ""
        }

        let args = TestArgs()
        XCTAssertTrue(args.$requiredField.parameterRequired)
    }

    func testExplicitRequiredFlag() {
        struct TestArgs: Codable, Sendable {
            @AIParameter(description: "Optional field", required: false)
            var optionalField: String = ""
        }

        let args = TestArgs()
        XCTAssertFalse(args.$optionalField.parameterRequired)
    }

    // MARK: - Validation Factory Tests

    func testEnumOfFactory() {
        let validation = AIParameterValidation.enumOf("a", "b", "c")
        XCTAssertEqual(validation.enumValues, ["a", "b", "c"])
        XCTAssertNil(validation.minimum)
        XCTAssertNil(validation.maximum)
    }

    func testRangeFactory() {
        let validation = AIParameterValidation.range(min: 0, max: 100)
        XCTAssertEqual(validation.minimum, 0)
        XCTAssertEqual(validation.maximum, 100)
        XCTAssertNil(validation.enumValues)
    }

    func testLengthFactory() {
        let validation = AIParameterValidation.length(min: 5, max: 50)
        XCTAssertEqual(validation.minLength, 5)
        XCTAssertEqual(validation.maxLength, 50)
    }

    func testMatchingFactory() {
        let pattern = "^[a-z]+$"
        let validation = AIParameterValidation.matching(pattern)
        XCTAssertEqual(validation.pattern, pattern)
    }

    func testArraySizeFactory() {
        let validation = AIParameterValidation.arraySize(min: 1, max: 10)
        XCTAssertEqual(validation.minItems, 1)
        XCTAssertEqual(validation.maxItems, 10)
    }

    // MARK: - Equatable Tests

    func testParameterEquatable() {
        @AIParameter(description: "Test")
        var param1: String = "value"

        @AIParameter(description: "Test")
        var param2: String = "value"

        XCTAssertEqual($param1, $param2)
    }

    func testValidationEquatable() {
        let v1 = AIParameterValidation.enumOf("a", "b")
        let v2 = AIParameterValidation.enumOf("a", "b")
        let v3 = AIParameterValidation.enumOf("a", "c")

        XCTAssertEqual(v1, v2)
        XCTAssertNotEqual(v1, v3)
    }
}
