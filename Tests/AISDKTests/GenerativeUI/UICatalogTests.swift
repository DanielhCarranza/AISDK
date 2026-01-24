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

    func testRegisterCustomComponent() {
        var catalog = UICatalog()
        XCTAssertEqual(catalog.registeredComponentTypes.count, 0)

        catalog.register(TextComponentDefinitionPlaceholder.self)
        XCTAssertEqual(catalog.registeredComponentTypes.count, 1)
        XCTAssertTrue(catalog.hasComponent("Text"))
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
    }

    // MARK: - Component Definition Tests

    func testTextComponentDefinition() {
        XCTAssertEqual(TextComponentDefinitionPlaceholder.type, "Text")
        XCTAssertEqual(TextComponentDefinitionPlaceholder.description, "Display text content")
        XCTAssertFalse(TextComponentDefinitionPlaceholder.hasChildren)
    }

    func testButtonComponentDefinition() {
        XCTAssertEqual(ButtonComponentDefinitionPlaceholder.type, "Button")
        XCTAssertFalse(ButtonComponentDefinitionPlaceholder.hasChildren)
    }

    func testStackComponentDefinition() {
        XCTAssertEqual(StackComponentDefinitionPlaceholder.type, "Stack")
        XCTAssertTrue(StackComponentDefinitionPlaceholder.hasChildren)
    }

    // MARK: - AnyUIComponentDefinition Tests

    func testAnyUIComponentDefinitionWrapping() {
        let wrapped = AnyUIComponentDefinition(TextComponentDefinitionPlaceholder.self)

        XCTAssertEqual(wrapped.type, "Text")
        XCTAssertEqual(wrapped.description, "Display text content")
        XCTAssertFalse(wrapped.hasChildren)
    }

    func testAnyUIComponentDefinitionValidation() throws {
        let wrapped = AnyUIComponentDefinition(TextComponentDefinitionPlaceholder.self)

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
        let wrapped = AnyUIComponentDefinition(TextComponentDefinitionPlaceholder.self)

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
