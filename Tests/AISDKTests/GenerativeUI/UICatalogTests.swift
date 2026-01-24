//
//  UICatalogTests.swift
//  AISDKTests
//
//  Tests for UICatalog and UIComponentDefinition
//

import XCTest
@testable import AISDK

final class UICatalogTests: XCTestCase {

    // MARK: - Core 8 Catalog Tests

    func testCore8CatalogHasAllComponents() {
        let catalog = UICatalog.core8

        XCTAssertEqual(catalog.registeredComponentTypes.count, 8)
        XCTAssertTrue(catalog.hasComponent("Text"))
        XCTAssertTrue(catalog.hasComponent("Button"))
        XCTAssertTrue(catalog.hasComponent("Card"))
        XCTAssertTrue(catalog.hasComponent("Input"))
        XCTAssertTrue(catalog.hasComponent("List"))
        XCTAssertTrue(catalog.hasComponent("Image"))
        XCTAssertTrue(catalog.hasComponent("Stack"))
        XCTAssertTrue(catalog.hasComponent("Spacer"))
    }

    func testCore8CatalogComponentTypes() {
        let catalog = UICatalog.core8
        let expected = ["Button", "Card", "Image", "Input", "List", "Spacer", "Stack", "Text"]
        XCTAssertEqual(catalog.registeredComponentTypes, expected)
    }

    func testCore8CatalogHasActions() {
        let catalog = UICatalog.core8

        XCTAssertEqual(catalog.actions.count, 3)
        XCTAssertNotNil(catalog.actions["submit"])
        XCTAssertNotNil(catalog.actions["navigate"])
        XCTAssertNotNil(catalog.actions["dismiss"])
    }

    func testCore8CatalogHasValidators() {
        let catalog = UICatalog.core8

        XCTAssertEqual(catalog.validators.count, 5)
        XCTAssertNotNil(catalog.validators["required"])
        XCTAssertNotNil(catalog.validators["email"])
        XCTAssertNotNil(catalog.validators["minLength"])
        XCTAssertNotNil(catalog.validators["maxLength"])
        XCTAssertNotNil(catalog.validators["pattern"])
    }

    // MARK: - Component Lookup Tests

    func testComponentLookupByType() {
        let catalog = UICatalog.core8

        let textComponent = catalog.component(forType: "Text")
        XCTAssertNotNil(textComponent)
        XCTAssertEqual(textComponent?.type, "Text")
        XCTAssertEqual(textComponent?.description, "Display text content")
        XCTAssertFalse(textComponent?.hasChildren ?? true)

        let stackComponent = catalog.component(forType: "Stack")
        XCTAssertNotNil(stackComponent)
        XCTAssertTrue(stackComponent?.hasChildren ?? false)
    }

    func testComponentLookupNotFound() {
        let catalog = UICatalog.core8

        let unknownComponent = catalog.component(forType: "Unknown")
        XCTAssertNil(unknownComponent)
        XCTAssertFalse(catalog.hasComponent("Unknown"))
    }

    // MARK: - Registration Tests

    func testRegisterCustomComponent() throws {
        var catalog = UICatalog()
        XCTAssertEqual(catalog.registeredComponentTypes.count, 0)

        try catalog.register(TextComponentDefinition.self)
        XCTAssertEqual(catalog.registeredComponentTypes.count, 1)
        XCTAssertTrue(catalog.hasComponent("Text"))
    }

    func testRegisterDuplicateComponentThrows() throws {
        var catalog = UICatalog()
        try catalog.register(TextComponentDefinition.self)

        // Attempting to register again should throw
        XCTAssertThrowsError(try catalog.register(TextComponentDefinition.self)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .duplicateComponentType(let type) = validationError {
                XCTAssertEqual(type, "Text")
            } else {
                XCTFail("Expected duplicateComponentType error, got \(validationError)")
            }
        }
    }

    func testRegisterComponentWithWhitespaceTypeThrows() throws {
        // Test component with leading/trailing whitespace in type name
        struct WhitespaceTypeComponent: UIComponentDefinition {
            struct Props: Codable, Sendable {}
            static let type = "  Spaced  "
            static let description = "Component with whitespace type"
            static let hasChildren = false
            static let propsSchemaDescription = "{}"
            static let allowedPropKeys: Set<String> = []
        }

        var catalog = UICatalog()
        XCTAssertThrowsError(try catalog.register(WhitespaceTypeComponent.self)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .invalidComponentTypeName(let name) = validationError {
                XCTAssertEqual(name, "  Spaced  ")
            } else {
                XCTFail("Expected invalidComponentTypeName error, got \(validationError)")
            }
        }
    }

    func testRegisterAction() {
        var catalog = UICatalog()
        XCTAssertEqual(catalog.actions.count, 0)

        let action = UIActionDefinition(
            name: "customAction",
            description: "A custom action",
            parametersDescription: "{ data: string }"
        )
        catalog.registerAction(action)

        XCTAssertEqual(catalog.actions.count, 1)
        XCTAssertEqual(catalog.actions["customAction"]?.description, "A custom action")
    }

    func testRegisterValidator() {
        var catalog = UICatalog()
        XCTAssertEqual(catalog.validators.count, 0)

        let validator = UIValidatorDefinition(
            name: "customValidator",
            description: "A custom validator"
        )
        catalog.registerValidator(validator)

        XCTAssertEqual(catalog.validators.count, 1)
        XCTAssertEqual(catalog.validators["customValidator"]?.description, "A custom validator")
    }

    // MARK: - Prompt Generation Tests

    func testGeneratePromptContainsAllComponents() {
        let catalog = UICatalog.core8
        let prompt = catalog.generatePrompt()

        // Check all component types are mentioned
        XCTAssertTrue(prompt.contains("## Text"))
        XCTAssertTrue(prompt.contains("## Button"))
        XCTAssertTrue(prompt.contains("## Card"))
        XCTAssertTrue(prompt.contains("## Input"))
        XCTAssertTrue(prompt.contains("## List"))
        XCTAssertTrue(prompt.contains("## Image"))
        XCTAssertTrue(prompt.contains("## Stack"))
        XCTAssertTrue(prompt.contains("## Spacer"))
    }

    func testGeneratePromptContainsOutputFormat() {
        let catalog = UICatalog.core8
        let prompt = catalog.generatePrompt()

        XCTAssertTrue(prompt.contains("Output format: JSON"))
        XCTAssertTrue(prompt.contains("\"root\""))
        XCTAssertTrue(prompt.contains("\"elements\""))
        XCTAssertTrue(prompt.contains("\"type\""))
        XCTAssertTrue(prompt.contains("\"props\""))
        XCTAssertTrue(prompt.contains("\"children\""))
    }

    func testGeneratePromptContainsChildrenYes() {
        let catalog = UICatalog.core8
        let prompt = catalog.generatePrompt()

        // Card, List, Stack have children
        XCTAssertTrue(prompt.contains("Can contain children: Yes"))
    }

    func testGeneratePromptContainsChildrenNo() {
        let catalog = UICatalog.core8
        let prompt = catalog.generatePrompt()

        // Text, Button, Input, Image, Spacer do not have children
        XCTAssertTrue(prompt.contains("Can contain children: No"))
    }

    func testGeneratePromptContainsChildrenRules() {
        let catalog = UICatalog.core8
        let prompt = catalog.generatePrompt()

        // Verify rules about children handling
        XCTAssertTrue(prompt.contains("Only components marked \"Can contain children: Yes\" may have a \"children\" array"))
        XCTAssertTrue(prompt.contains("Components marked \"Can contain children: No\" must omit the \"children\" field"))
    }

    func testGeneratePromptContainsActions() {
        let catalog = UICatalog.core8
        let prompt = catalog.generatePrompt()

        XCTAssertTrue(prompt.contains("## Available Actions"))
        XCTAssertTrue(prompt.contains("**submit**"))
        XCTAssertTrue(prompt.contains("**navigate**"))
        XCTAssertTrue(prompt.contains("**dismiss**"))
    }

    func testGeneratePromptContainsValidators() {
        let catalog = UICatalog.core8
        let prompt = catalog.generatePrompt()

        XCTAssertTrue(prompt.contains("## Available Validators"))
        XCTAssertTrue(prompt.contains("**required**"))
        XCTAssertTrue(prompt.contains("**email**"))
        XCTAssertTrue(prompt.contains("**minLength**"))
    }

    func testGeneratePromptIsDeterministic() {
        let catalog = UICatalog.core8

        let prompt1 = catalog.generatePrompt()
        let prompt2 = catalog.generatePrompt()

        XCTAssertEqual(prompt1, prompt2, "Prompt generation should be deterministic")
    }

    // MARK: - Validation Tests

    func testValidateValidTextProps() throws {
        let catalog = UICatalog.core8
        let propsJSON = """
        {"content": "Hello, World!"}
        """
        let propsData = Data(propsJSON.utf8)

        XCTAssertNoThrow(try catalog.validate(type: "Text", propsData: propsData))
    }

    func testValidateInvalidTextProps() {
        let catalog = UICatalog.core8
        let propsJSON = """
        {"content": ""}
        """
        let propsData = Data(propsJSON.utf8)

        XCTAssertThrowsError(try catalog.validate(type: "Text", propsData: propsData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError")
                return
            }
            if case .invalidPropValue(let component, let prop, _) = validationError {
                XCTAssertEqual(component, "Text")
                XCTAssertEqual(prop, "content")
            } else {
                XCTFail("Expected invalidPropValue error")
            }
        }
    }

    func testValidateUnknownComponentType() {
        let catalog = UICatalog.core8
        let propsJSON = """
        {"content": "Hello"}
        """
        let propsData = Data(propsJSON.utf8)

        XCTAssertThrowsError(try catalog.validate(type: "Unknown", propsData: propsData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError")
                return
            }
            if case .unknownComponentType(let type) = validationError {
                XCTAssertEqual(type, "Unknown")
            } else {
                XCTFail("Expected unknownComponentType error")
            }
        }
    }

    func testValidateButtonProps() throws {
        let catalog = UICatalog.core8
        let validPropsJSON = """
        {"title": "Submit", "action": "submit"}
        """
        let validPropsData = Data(validPropsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Button", propsData: validPropsData))

        // Missing action
        let invalidPropsJSON = """
        {"title": "Submit", "action": ""}
        """
        let invalidPropsData = Data(invalidPropsJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Button", propsData: invalidPropsData))
    }

    func testValidateStackProps() throws {
        let catalog = UICatalog.core8

        // Valid direction
        let validPropsJSON = """
        {"direction": "horizontal", "spacing": 8}
        """
        let validPropsData = Data(validPropsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Stack", propsData: validPropsData))

        // Invalid direction (enum validation)
        let invalidPropsJSON = """
        {"direction": "diagonal"}
        """
        let invalidPropsData = Data(invalidPropsJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Stack", propsData: invalidPropsData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .decodingFailed(let component, _) = validationError {
                XCTAssertEqual(component, "Stack")
            } else {
                XCTFail("Expected decodingFailed error for invalid enum, got \(validationError)")
            }
        }
    }

    func testValidateStackDirectionRequired() {
        let catalog = UICatalog.core8

        // Missing direction (required field)
        let missingDirectionJSON = """
        {"spacing": 8}
        """
        let missingDirectionData = Data(missingDirectionJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Stack", propsData: missingDirectionData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .missingRequiredProp(let component, let prop) = validationError {
                XCTAssertEqual(component, "Stack")
                XCTAssertEqual(prop, "direction")
            } else {
                XCTFail("Expected missingRequiredProp error for missing direction, got \(validationError)")
            }
        }
    }

    func testValidateStackAlignment() throws {
        let catalog = UICatalog.core8

        // Valid alignment
        let validPropsJSON = """
        {"direction": "vertical", "alignment": "center"}
        """
        let validPropsData = Data(validPropsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Stack", propsData: validPropsData))

        // Invalid alignment (enum validation)
        let invalidAlignmentJSON = """
        {"direction": "vertical", "alignment": "stretch"}
        """
        let invalidAlignmentData = Data(invalidAlignmentJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Stack", propsData: invalidAlignmentData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .decodingFailed(let component, _) = validationError {
                XCTAssertEqual(component, "Stack")
            } else {
                XCTFail("Expected decodingFailed error for invalid alignment, got \(validationError)")
            }
        }
    }

    func testValidateImageProps() throws {
        let catalog = UICatalog.core8

        // Valid props
        let validPropsJSON = """
        {"url": "https://example.com/image.png", "width": 100, "height": 100}
        """
        let validPropsData = Data(validPropsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Image", propsData: validPropsData))

        // Empty URL
        let emptyURLPropsJSON = """
        {"url": ""}
        """
        let emptyURLPropsData = Data(emptyURLPropsJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Image", propsData: emptyURLPropsData))

        // Negative width
        let negativeWidthPropsJSON = """
        {"url": "https://example.com/image.png", "width": -100}
        """
        let negativeWidthPropsData = Data(negativeWidthPropsJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Image", propsData: negativeWidthPropsData))
    }

    func testValidateSpacerProps() throws {
        let catalog = UICatalog.core8

        // Valid props
        let validPropsJSON = """
        {"size": 16}
        """
        let validPropsData = Data(validPropsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Spacer", propsData: validPropsData))

        // Negative size
        let negativePropsJSON = """
        {"size": -10}
        """
        let negativePropsData = Data(negativePropsJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Spacer", propsData: negativePropsData))
    }

    func testValidateInputTypeEnum() throws {
        let catalog = UICatalog.core8

        // Valid input types
        for inputType in ["text", "email", "password", "number"] {
            let propsJSON = """
            {"label": "Test", "name": "test", "type": "\(inputType)"}
            """
            let propsData = Data(propsJSON.utf8)
            XCTAssertNoThrow(try catalog.validate(type: "Input", propsData: propsData), "Expected \(inputType) to be valid")
        }

        // Invalid input type
        let invalidTypeJSON = """
        {"label": "Test", "name": "test", "type": "phone"}
        """
        let invalidTypeData = Data(invalidTypeJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Input", propsData: invalidTypeData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .decodingFailed(let component, _) = validationError {
                XCTAssertEqual(component, "Input")
            } else {
                XCTFail("Expected decodingFailed error for invalid input type, got \(validationError)")
            }
        }
    }

    func testValidateListStyleEnum() throws {
        let catalog = UICatalog.core8

        // Valid list styles
        for listStyle in ["ordered", "unordered", "plain"] {
            let propsJSON = """
            {"style": "\(listStyle)"}
            """
            let propsData = Data(propsJSON.utf8)
            XCTAssertNoThrow(try catalog.validate(type: "List", propsData: propsData), "Expected \(listStyle) to be valid")
        }

        // Invalid list style
        let invalidStyleJSON = """
        {"style": "numbered"}
        """
        let invalidStyleData = Data(invalidStyleJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "List", propsData: invalidStyleData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .decodingFailed(let component, _) = validationError {
                XCTAssertEqual(component, "List")
            } else {
                XCTFail("Expected decodingFailed error for invalid list style, got \(validationError)")
            }
        }
    }

    // MARK: - Unknown Prop Validation Tests

    func testUnknownPropRejected() {
        let catalog = UICatalog.core8

        // Extra prop "foo" should be rejected
        let unknownPropJSON = """
        {"content": "Hello", "foo": "bar"}
        """
        let unknownPropData = Data(unknownPropJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Text", propsData: unknownPropData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .unknownProp(let component, let prop) = validationError {
                XCTAssertEqual(component, "Text")
                XCTAssertEqual(prop, "foo")
            } else {
                XCTFail("Expected unknownProp error, got \(validationError)")
            }
        }
    }

    func testUnknownPropWithSnakeCase() {
        let catalog = UICatalog.core8

        // unknown_prop should be converted to unknownProp and rejected
        let unknownPropJSON = """
        {"content": "Hello", "unknown_prop": "value"}
        """
        let unknownPropData = Data(unknownPropJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Text", propsData: unknownPropData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .unknownProp(let component, _) = validationError {
                XCTAssertEqual(component, "Text")
            } else {
                XCTFail("Expected unknownProp error, got \(validationError)")
            }
        }
    }

    // MARK: - Action Validation Tests

    func testButtonWithUnknownActionRejected() {
        let catalog = UICatalog.core8

        // "customAction" is not a registered action
        let unknownActionJSON = """
        {"title": "Click", "action": "customAction"}
        """
        let unknownActionData = Data(unknownActionJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Button", propsData: unknownActionData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .unknownAction(let component, let action) = validationError {
                XCTAssertEqual(component, "Button")
                XCTAssertEqual(action, "customAction")
            } else {
                XCTFail("Expected unknownAction error, got \(validationError)")
            }
        }
    }

    func testButtonWithRegisteredActionAccepted() throws {
        let catalog = UICatalog.core8

        // All registered actions should be accepted
        for action in ["submit", "navigate", "dismiss"] {
            let validJSON = """
            {"title": "Click", "action": "\(action)"}
            """
            let validData = Data(validJSON.utf8)
            XCTAssertNoThrow(try catalog.validate(type: "Button", propsData: validData), "Expected action '\(action)' to be valid")
        }
    }

    func testButtonWithActionInEmptyCatalogRejected() throws {
        // When catalog has no actions registered, any action should be rejected
        var catalog = UICatalog()
        try catalog.register(ButtonComponentDefinition.self)

        let anyActionJSON = """
        {"title": "Click", "action": "anyAction"}
        """
        let anyActionData = Data(anyActionJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Button", propsData: anyActionData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .unknownAction(let component, let action) = validationError {
                XCTAssertEqual(component, "Button")
                XCTAssertEqual(action, "anyAction")
            } else {
                XCTFail("Expected unknownAction error, got \(validationError)")
            }
        }
    }

    // MARK: - Validator Validation Tests

    func testInputWithUnknownValidatorRejected() {
        let catalog = UICatalog.core8

        // "customValidator" is not a registered validator
        let unknownValidatorJSON = """
        {"label": "Email", "name": "email", "validation": "customValidator"}
        """
        let unknownValidatorData = Data(unknownValidatorJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Input", propsData: unknownValidatorData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .unknownValidator(let component, let validator) = validationError {
                XCTAssertEqual(component, "Input")
                XCTAssertEqual(validator, "customValidator")
            } else {
                XCTFail("Expected unknownValidator error, got \(validationError)")
            }
        }
    }

    func testInputWithRegisteredValidatorAccepted() throws {
        let catalog = UICatalog.core8

        // All registered validators should be accepted
        for validator in ["required", "email", "minLength", "maxLength", "pattern"] {
            let validJSON = """
            {"label": "Field", "name": "field", "validation": "\(validator)"}
            """
            let validData = Data(validJSON.utf8)
            XCTAssertNoThrow(try catalog.validate(type: "Input", propsData: validData), "Expected validator '\(validator)' to be valid")
        }
    }

    func testInputWithNoValidationAccepted() throws {
        let catalog = UICatalog.core8

        // Input without validation should be accepted
        let noValidationJSON = """
        {"label": "Name", "name": "name"}
        """
        let noValidationData = Data(noValidationJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Input", propsData: noValidationData))
    }

    func testInputWithValidatorInEmptyCatalogRejected() throws {
        // When catalog has no validators registered, any validator should be rejected
        var catalog = UICatalog()
        try catalog.register(InputComponentDefinition.self)

        let anyValidatorJSON = """
        {"label": "Email", "name": "email", "validation": "anyValidator"}
        """
        let anyValidatorData = Data(anyValidatorJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Input", propsData: anyValidatorData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .unknownValidator(let component, let validator) = validationError {
                XCTAssertEqual(component, "Input")
                XCTAssertEqual(validator, "anyValidator")
            } else {
                XCTFail("Expected unknownValidator error, got \(validationError)")
            }
        }
    }

    // MARK: - Decoding Error Tests

    func testDecodingMissingRequiredProp() {
        let catalog = UICatalog.core8

        // Missing required 'content' for Text
        let missingContentJSON = """
        {"style": "bold"}
        """
        let missingContentData = Data(missingContentJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Text", propsData: missingContentData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .missingRequiredProp(let component, let prop) = validationError {
                XCTAssertEqual(component, "Text")
                XCTAssertEqual(prop, "content")
            } else {
                XCTFail("Expected missingRequiredProp error, got \(validationError)")
            }
        }
    }

    func testDecodingTypeMismatchThrowsDecodingFailed() {
        let catalog = UICatalog.core8

        // Type mismatch: spacing should be number, not string
        let typeMismatchJSON = """
        {"direction": "vertical", "spacing": "large"}
        """
        let typeMismatchData = Data(typeMismatchJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Stack", propsData: typeMismatchData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .decodingFailed(let component, _) = validationError {
                XCTAssertEqual(component, "Stack")
            } else {
                XCTFail("Expected decodingFailed error for type mismatch, got \(validationError)")
            }
        }
    }

    func testDecodingInvalidJSON() {
        let catalog = UICatalog.core8

        // Invalid JSON
        let invalidJSON = """
        {not valid json}
        """
        let invalidData = Data(invalidJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Text", propsData: invalidData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .decodingFailed(let component, _) = validationError {
                XCTAssertEqual(component, "Text")
            } else {
                XCTFail("Expected decodingFailed error for invalid JSON, got \(validationError)")
            }
        }
    }

    // MARK: - Error Description Tests

    func testValidationErrorDescriptions() {
        let missingPropError = UIComponentValidationError.missingRequiredProp(
            component: "Button",
            prop: "title"
        )
        XCTAssertTrue(missingPropError.errorDescription?.contains("Button") ?? false)
        XCTAssertTrue(missingPropError.errorDescription?.contains("title") ?? false)

        let invalidValueError = UIComponentValidationError.invalidPropValue(
            component: "Stack",
            prop: "direction",
            reason: "Must be horizontal or vertical"
        )
        XCTAssertTrue(invalidValueError.errorDescription?.contains("Stack") ?? false)
        XCTAssertTrue(invalidValueError.errorDescription?.contains("direction") ?? false)

        let unknownTypeError = UIComponentValidationError.unknownComponentType("Custom")
        XCTAssertTrue(unknownTypeError.errorDescription?.contains("Custom") ?? false)

        let decodingFailedError = UIComponentValidationError.decodingFailed(
            component: "Input",
            reason: "Invalid type value"
        )
        XCTAssertTrue(decodingFailedError.errorDescription?.contains("Input") ?? false)
        XCTAssertTrue(decodingFailedError.errorDescription?.contains("decoding failed") ?? false)

        let unknownPropError = UIComponentValidationError.unknownProp(
            component: "Text",
            prop: "foo"
        )
        XCTAssertTrue(unknownPropError.errorDescription?.contains("Text") ?? false)
        XCTAssertTrue(unknownPropError.errorDescription?.contains("foo") ?? false)
        XCTAssertTrue(unknownPropError.errorDescription?.contains("unknown") ?? false)

        let unknownActionError = UIComponentValidationError.unknownAction(
            component: "Button",
            action: "customAction"
        )
        XCTAssertTrue(unknownActionError.errorDescription?.contains("Button") ?? false)
        XCTAssertTrue(unknownActionError.errorDescription?.contains("customAction") ?? false)
        XCTAssertTrue(unknownActionError.errorDescription?.contains("action") ?? false)

        let unknownValidatorError = UIComponentValidationError.unknownValidator(
            component: "Input",
            validator: "customValidator"
        )
        XCTAssertTrue(unknownValidatorError.errorDescription?.contains("Input") ?? false)
        XCTAssertTrue(unknownValidatorError.errorDescription?.contains("customValidator") ?? false)
        XCTAssertTrue(unknownValidatorError.errorDescription?.contains("validator") ?? false)

        let duplicateTypeError = UIComponentValidationError.duplicateComponentType("Text")
        XCTAssertTrue(duplicateTypeError.errorDescription?.contains("Text") ?? false)
        XCTAssertTrue(duplicateTypeError.errorDescription?.contains("Duplicate") ?? false)
    }

    // MARK: - Component Definition Tests

    func testTextComponentDefinition() {
        XCTAssertEqual(TextComponentDefinition.type, "Text")
        XCTAssertEqual(TextComponentDefinition.description, "Display text content")
        XCTAssertFalse(TextComponentDefinition.hasChildren)
    }

    func testButtonComponentDefinition() {
        XCTAssertEqual(ButtonComponentDefinition.type, "Button")
        XCTAssertFalse(ButtonComponentDefinition.hasChildren)
    }

    func testStackComponentDefinition() {
        XCTAssertEqual(StackComponentDefinition.type, "Stack")
        XCTAssertTrue(StackComponentDefinition.hasChildren)
    }

    func testCardComponentDefinition() {
        XCTAssertEqual(CardComponentDefinition.type, "Card")
        XCTAssertTrue(CardComponentDefinition.hasChildren)
    }

    func testInputComponentDefinition() {
        XCTAssertEqual(InputComponentDefinition.type, "Input")
        XCTAssertFalse(InputComponentDefinition.hasChildren)
    }

    func testListComponentDefinition() {
        XCTAssertEqual(ListComponentDefinition.type, "List")
        XCTAssertTrue(ListComponentDefinition.hasChildren)
    }

    func testImageComponentDefinition() {
        XCTAssertEqual(ImageComponentDefinition.type, "Image")
        XCTAssertFalse(ImageComponentDefinition.hasChildren)
    }

    func testSpacerComponentDefinition() {
        XCTAssertEqual(SpacerComponentDefinition.type, "Spacer")
        XCTAssertFalse(SpacerComponentDefinition.hasChildren)
    }

    // MARK: - AnyUIComponentDefinition Tests

    func testAnyUIComponentDefinitionWrapping() {
        let wrapped = AnyUIComponentDefinition(TextComponentDefinition.self)

        XCTAssertEqual(wrapped.type, "Text")
        XCTAssertEqual(wrapped.description, "Display text content")
        XCTAssertFalse(wrapped.hasChildren)
    }

    func testAnyUIComponentDefinitionValidation() throws {
        let wrapped = AnyUIComponentDefinition(TextComponentDefinition.self)

        let validPropsJSON = """
        {"content": "Hello"}
        """
        let validPropsData = Data(validPropsJSON.utf8)
        XCTAssertNoThrow(try wrapped.validate(propsData: validPropsData))

        let invalidPropsJSON = """
        {"content": ""}
        """
        let invalidPropsData = Data(invalidPropsJSON.utf8)
        XCTAssertThrowsError(try wrapped.validate(propsData: invalidPropsData))
    }

    func testAnyUIComponentDefinitionDecodingError() throws {
        let wrapped = AnyUIComponentDefinition(TextComponentDefinition.self)

        // Missing required prop
        let missingPropJSON = """
        {}
        """
        let missingPropData = Data(missingPropJSON.utf8)
        XCTAssertThrowsError(try wrapped.validate(propsData: missingPropData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .missingRequiredProp(let component, let prop) = validationError {
                XCTAssertEqual(component, "Text")
                XCTAssertEqual(prop, "content")
            } else {
                XCTFail("Expected missingRequiredProp error, got \(validationError)")
            }
        }
    }

    // MARK: - Accessibility Props Tests

    func testTextAccessibilityProps() throws {
        let catalog = UICatalog.core8

        // Valid accessibility props
        let propsJSON = """
        {
            "content": "Hello, World!",
            "accessibilityLabel": "Greeting text",
            "accessibilityHint": "A welcome message",
            "accessibilityTraits": ["staticText"]
        }
        """
        let propsData = Data(propsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Text", propsData: propsData))
    }

    func testTextInvalidAccessibilityTrait() {
        let catalog = UICatalog.core8

        // Invalid accessibility trait
        let propsJSON = """
        {
            "content": "Hello",
            "accessibilityTraits": ["invalid_trait"]
        }
        """
        let propsData = Data(propsJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Text", propsData: propsData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .invalidPropValue(let component, let prop, _) = validationError {
                XCTAssertEqual(component, "Text")
                XCTAssertEqual(prop, "accessibilityTraits")
            } else {
                XCTFail("Expected invalidPropValue error, got \(validationError)")
            }
        }
    }

    func testButtonAccessibilityProps() throws {
        let catalog = UICatalog.core8

        // Valid accessibility props
        let propsJSON = """
        {
            "title": "Submit",
            "action": "submit",
            "accessibilityLabel": "Submit button",
            "accessibilityHint": "Double-tap to submit the form",
            "accessibilityTraits": ["button"]
        }
        """
        let propsData = Data(propsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Button", propsData: propsData))
    }

    func testButtonStyleValidation() throws {
        let catalog = UICatalog.core8

        // Valid button styles
        for style in ["primary", "secondary", "destructive", "plain"] {
            let propsJSON = """
            {"title": "Click", "action": "submit", "style": "\(style)"}
            """
            let propsData = Data(propsJSON.utf8)
            XCTAssertNoThrow(try catalog.validate(type: "Button", propsData: propsData), "Expected style '\(style)' to be valid")
        }

        // Invalid button style
        let invalidStyleJSON = """
        {"title": "Click", "action": "submit", "style": "danger"}
        """
        let invalidStyleData = Data(invalidStyleJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Button", propsData: invalidStyleData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .invalidPropValue(let component, let prop, _) = validationError {
                XCTAssertEqual(component, "Button")
                XCTAssertEqual(prop, "style")
            } else {
                XCTFail("Expected invalidPropValue error for invalid style, got \(validationError)")
            }
        }
    }

    func testCardAccessibilityProps() throws {
        let catalog = UICatalog.core8

        // Card with all accessibility props
        let propsJSON = """
        {
            "title": "Welcome",
            "subtitle": "Get started",
            "style": "elevated",
            "accessibilityLabel": "Welcome card",
            "accessibilityHint": "Shows getting started options"
        }
        """
        let propsData = Data(propsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Card", propsData: propsData))
    }

    func testCardStyleValidation() throws {
        let catalog = UICatalog.core8

        // Valid card styles
        for style in ["elevated", "outlined", "filled"] {
            let propsJSON = """
            {"style": "\(style)"}
            """
            let propsData = Data(propsJSON.utf8)
            XCTAssertNoThrow(try catalog.validate(type: "Card", propsData: propsData), "Expected style '\(style)' to be valid")
        }

        // Invalid card style
        let invalidStyleJSON = """
        {"style": "flat"}
        """
        let invalidStyleData = Data(invalidStyleJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Card", propsData: invalidStyleData))
    }

    func testInputAccessibilityProps() throws {
        let catalog = UICatalog.core8

        let propsJSON = """
        {
            "label": "Email",
            "name": "email",
            "type": "email",
            "validation": "email",
            "accessibilityLabel": "Email input field",
            "accessibilityHint": "Enter your email address"
        }
        """
        let propsData = Data(propsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Input", propsData: propsData))
    }

    func testImageAccessibilityProps() throws {
        let catalog = UICatalog.core8

        let propsJSON = """
        {
            "url": "https://example.com/photo.jpg",
            "alt": "Profile photo",
            "width": 200,
            "height": 200,
            "contentMode": "fit",
            "accessibilityLabel": "User profile picture",
            "accessibilityTraits": ["image"]
        }
        """
        let propsData = Data(propsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Image", propsData: propsData))
    }

    func testImageContentModeValidation() throws {
        let catalog = UICatalog.core8

        // Valid content modes
        for mode in ["fit", "fill", "stretch"] {
            let propsJSON = """
            {"url": "https://example.com/img.png", "contentMode": "\(mode)"}
            """
            let propsData = Data(propsJSON.utf8)
            XCTAssertNoThrow(try catalog.validate(type: "Image", propsData: propsData), "Expected contentMode '\(mode)' to be valid")
        }

        // Invalid content mode
        let invalidModeJSON = """
        {"url": "https://example.com/img.png", "contentMode": "cover"}
        """
        let invalidModeData = Data(invalidModeJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Image", propsData: invalidModeData))
    }

    func testStackAccessibilityProps() throws {
        let catalog = UICatalog.core8

        let propsJSON = """
        {
            "direction": "vertical",
            "spacing": 16,
            "alignment": "center",
            "accessibilityLabel": "Main content stack"
        }
        """
        let propsData = Data(propsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Stack", propsData: propsData))
    }

    func testListAccessibilityProps() throws {
        let catalog = UICatalog.core8

        let propsJSON = """
        {
            "style": "ordered",
            "accessibilityLabel": "Todo list"
        }
        """
        let propsData = Data(propsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "List", propsData: propsData))
    }

    func testSpacerAccessibilityProps() throws {
        let catalog = UICatalog.core8

        let propsJSON = """
        {
            "size": 32,
            "accessibilityLabel": "Visual separator"
        }
        """
        let propsData = Data(propsJSON.utf8)
        XCTAssertNoThrow(try catalog.validate(type: "Spacer", propsData: propsData))
    }

    func testTextStyleValidation() throws {
        let catalog = UICatalog.core8

        // Valid text styles
        for style in ["body", "headline", "subheadline", "caption", "title"] {
            let propsJSON = """
            {"content": "Hello", "style": "\(style)"}
            """
            let propsData = Data(propsJSON.utf8)
            XCTAssertNoThrow(try catalog.validate(type: "Text", propsData: propsData), "Expected style '\(style)' to be valid")
        }

        // Invalid text style
        let invalidStyleJSON = """
        {"content": "Hello", "style": "large"}
        """
        let invalidStyleData = Data(invalidStyleJSON.utf8)
        XCTAssertThrowsError(try catalog.validate(type: "Text", propsData: invalidStyleData)) { error in
            guard let validationError = error as? UIComponentValidationError else {
                XCTFail("Expected UIComponentValidationError, got \(error)")
                return
            }
            if case .invalidPropValue(let component, let prop, _) = validationError {
                XCTAssertEqual(component, "Text")
                XCTAssertEqual(prop, "style")
            } else {
                XCTFail("Expected invalidPropValue error for invalid style, got \(validationError)")
            }
        }
    }

    // MARK: - Props Struct Direct Tests

    func testTextPropsInitialization() {
        let props = TextComponentDefinition.Props(
            content: "Hello",
            style: "headline",
            accessibilityLabel: "Greeting",
            accessibilityHint: "A greeting message",
            accessibilityTraits: ["header", "staticText"]
        )

        XCTAssertEqual(props.content, "Hello")
        XCTAssertEqual(props.style, "headline")
        XCTAssertEqual(props.accessibilityLabel, "Greeting")
        XCTAssertEqual(props.accessibilityHint, "A greeting message")
        XCTAssertEqual(props.accessibilityTraits, ["header", "staticText"])
    }

    func testButtonPropsInitialization() {
        let props = ButtonComponentDefinition.Props(
            title: "Submit",
            action: "submit",
            style: "primary",
            disabled: false,
            accessibilityLabel: "Submit form button",
            accessibilityHint: "Double-tap to submit",
            accessibilityTraits: ["button"]
        )

        XCTAssertEqual(props.title, "Submit")
        XCTAssertEqual(props.action, "submit")
        XCTAssertEqual(props.style, "primary")
        XCTAssertEqual(props.disabled, false)
        XCTAssertEqual(props.accessibilityLabel, "Submit form button")
    }

    func testCardPropsInitialization() {
        let props = CardComponentDefinition.Props(
            title: "Welcome",
            subtitle: "Get started today",
            style: "elevated",
            accessibilityLabel: "Welcome card"
        )

        XCTAssertEqual(props.title, "Welcome")
        XCTAssertEqual(props.subtitle, "Get started today")
        XCTAssertEqual(props.style, "elevated")
        XCTAssertEqual(props.accessibilityLabel, "Welcome card")
    }

    func testInputPropsInitialization() {
        let props = InputComponentDefinition.Props(
            label: "Email",
            name: "email",
            placeholder: "Enter email",
            type: .email,
            required: true,
            validation: "email",
            accessibilityLabel: "Email field"
        )

        XCTAssertEqual(props.label, "Email")
        XCTAssertEqual(props.name, "email")
        XCTAssertEqual(props.placeholder, "Enter email")
        XCTAssertEqual(props.type, .email)
        XCTAssertEqual(props.required, true)
        XCTAssertEqual(props.validation, "email")
    }

    func testImagePropsInitialization() {
        let props = ImageComponentDefinition.Props(
            url: "https://example.com/image.png",
            alt: "Example image",
            width: 100,
            height: 100,
            contentMode: "fit",
            accessibilityLabel: "Example image"
        )

        XCTAssertEqual(props.url, "https://example.com/image.png")
        XCTAssertEqual(props.alt, "Example image")
        XCTAssertEqual(props.width, 100)
        XCTAssertEqual(props.height, 100)
        XCTAssertEqual(props.contentMode, "fit")
    }

    func testStackPropsInitialization() {
        let props = StackComponentDefinition.Props(
            direction: .horizontal,
            spacing: 8,
            alignment: .center,
            accessibilityLabel: "Horizontal stack"
        )

        XCTAssertEqual(props.direction, .horizontal)
        XCTAssertEqual(props.spacing, 8)
        XCTAssertEqual(props.alignment, .center)
    }

    func testListPropsInitialization() {
        let props = ListComponentDefinition.Props(
            style: .ordered,
            accessibilityLabel: "Ordered list"
        )

        XCTAssertEqual(props.style, .ordered)
        XCTAssertEqual(props.accessibilityLabel, "Ordered list")
    }

    func testSpacerPropsInitialization() {
        let props = SpacerComponentDefinition.Props(
            size: 16,
            accessibilityLabel: "Spacer"
        )

        XCTAssertEqual(props.size, 16)
        XCTAssertEqual(props.accessibilityLabel, "Spacer")
    }

    // MARK: - Snake Case Decoding Tests

    func testPropsDecodingWithSnakeCase() throws {
        let catalog = UICatalog.core8

        // Snake case props should be decoded correctly
        let propsJSON = """
        {"accessibility_label": "Test label", "content": "Hello"}
        """
        let propsData = Data(propsJSON.utf8)

        // This should not throw
        XCTAssertNoThrow(try catalog.validate(type: "Text", propsData: propsData))
    }

    // MARK: - Empty Catalog Tests

    func testEmptyCatalog() {
        let catalog = UICatalog()

        XCTAssertEqual(catalog.registeredComponentTypes.count, 0)
        XCTAssertEqual(catalog.actions.count, 0)
        XCTAssertEqual(catalog.validators.count, 0)
        XCTAssertNil(catalog.component(forType: "Text"))
    }

    func testEmptyCatalogPrompt() {
        let catalog = UICatalog()
        let prompt = catalog.generatePrompt()

        XCTAssertTrue(prompt.contains("You can generate UI using these components"))
        XCTAssertTrue(prompt.contains("Output format: JSON"))
        // Should not contain actions or validators sections
        XCTAssertFalse(prompt.contains("## Available Actions"))
        XCTAssertFalse(prompt.contains("## Available Validators"))
    }
}
