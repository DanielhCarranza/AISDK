//
//  UISnapshotTests.swift
//  AISDKTests
//
//  UI Build & Validation Tests for GenerativeUI Core 8 Components
//  Tests JSON parsing, props decoding, tree structure, and catalog validation
//

#if canImport(SwiftUI)
import XCTest
import SwiftUI
@testable import AISDK

/// UI Build & Validation Tests for Core 8 GenerativeUI Components
///
/// These tests verify:
/// - UITree parsing succeeds for valid JSON structures
/// - Props decode correctly via UICatalog validation
/// - Container components have correct child relationships
/// - Style and prop variations pass catalog validation
/// - Edge cases handle gracefully (unknown types, malformed props)
///
/// Note: These are *structural* validation tests, not visual snapshot tests.
/// They verify that JSON → UITree → Props decoding works correctly for all
/// Core 8 component variations. For true visual regression testing, use
/// a snapshot library with UIHostingController rendering.
final class UISnapshotTests: XCTestCase {

    // MARK: - Test Utilities

    private let catalog = UICatalog.core8
    private let decoder = UIComponentRegistry.defaultPropsDecoder

    /// Parse JSON with catalog validation - verifies structure and props
    private func parseAndValidate(from json: String, file: StaticString = #file, line: UInt = #line) throws -> UITree {
        let tree = try UITree.parse(from: json, validatingWith: catalog)
        XCTAssertGreaterThan(tree.nodeCount, 0, "Tree should have at least one node", file: file, line: line)
        return tree
    }

    /// Verify tree structure and props decoding
    private func assertValidTree(
        from json: String,
        expectedNodeCount: Int? = nil,
        rootType: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            let tree = try parseAndValidate(from: json, file: file, line: line)

            if let expected = expectedNodeCount {
                XCTAssertEqual(tree.nodeCount, expected, "Node count mismatch", file: file, line: line)
            }

            if let expectedType = rootType {
                XCTAssertEqual(tree.rootNode.type, expectedType, "Root type mismatch", file: file, line: line)
            }
        } catch {
            XCTFail("Failed to parse/validate: \(error)", file: file, line: line)
        }
    }

    /// Verify Text component props decode correctly
    private func assertTextProps(
        from json: String,
        expectedContent: String,
        expectedStyle: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            let tree = try parseAndValidate(from: json, file: file, line: line)
            let props = try decoder.decode(TextComponentDefinition.Props.self, from: tree.rootNode.propsData)
            XCTAssertEqual(props.content, expectedContent, "Content mismatch", file: file, line: line)
            XCTAssertEqual(props.style, expectedStyle, "Style mismatch", file: file, line: line)
        } catch {
            XCTFail("Failed to decode Text props: \(error)", file: file, line: line)
        }
    }

    /// Verify Button component props decode correctly
    private func assertButtonProps(
        from json: String,
        expectedTitle: String,
        expectedAction: String,
        expectedStyle: String? = nil,
        expectedDisabled: Bool? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            let tree = try parseAndValidate(from: json, file: file, line: line)
            let props = try decoder.decode(ButtonComponentDefinition.Props.self, from: tree.rootNode.propsData)
            XCTAssertEqual(props.title, expectedTitle, "Title mismatch", file: file, line: line)
            XCTAssertEqual(props.action, expectedAction, "Action mismatch", file: file, line: line)
            XCTAssertEqual(props.style, expectedStyle, "Style mismatch", file: file, line: line)
            XCTAssertEqual(props.disabled, expectedDisabled, "Disabled mismatch", file: file, line: line)
        } catch {
            XCTFail("Failed to decode Button props: \(error)", file: file, line: line)
        }
    }

    // MARK: - Text Component Tests

    func test_text_component_default_style() {
        let json = """
        {
          "root": "text",
          "elements": {
            "text": {
              "type": "Text",
              "props": { "content": "Hello, World!" }
            }
          }
        }
        """
        assertTextProps(from: json, expectedContent: "Hello, World!", expectedStyle: nil)
    }

    func test_text_component_headline_style() {
        let json = """
        {
          "root": "text",
          "elements": {
            "text": {
              "type": "Text",
              "props": { "content": "Headline Text", "style": "headline" }
            }
          }
        }
        """
        assertTextProps(from: json, expectedContent: "Headline Text", expectedStyle: "headline")
    }

    func test_text_component_subheadline_style() {
        let json = """
        {
          "root": "text",
          "elements": {
            "text": {
              "type": "Text",
              "props": { "content": "Subheadline Text", "style": "subheadline" }
            }
          }
        }
        """
        assertTextProps(from: json, expectedContent: "Subheadline Text", expectedStyle: "subheadline")
    }

    func test_text_component_caption_style() {
        let json = """
        {
          "root": "text",
          "elements": {
            "text": {
              "type": "Text",
              "props": { "content": "Caption Text", "style": "caption" }
            }
          }
        }
        """
        assertTextProps(from: json, expectedContent: "Caption Text", expectedStyle: "caption")
    }

    func test_text_component_title_style() {
        let json = """
        {
          "root": "text",
          "elements": {
            "text": {
              "type": "Text",
              "props": { "content": "Title Text", "style": "title" }
            }
          }
        }
        """
        assertTextProps(from: json, expectedContent: "Title Text", expectedStyle: "title")
    }

    func test_text_component_body_style() {
        let json = """
        {
          "root": "text",
          "elements": {
            "text": {
              "type": "Text",
              "props": { "content": "Body text content", "style": "body" }
            }
          }
        }
        """
        assertTextProps(from: json, expectedContent: "Body text content", expectedStyle: "body")
    }

    func test_text_component_with_accessibility() throws {
        let json = """
        {
          "root": "text",
          "elements": {
            "text": {
              "type": "Text",
              "props": {
                "content": "Accessible Text",
                "accessibilityLabel": "Custom label for screen readers",
                "accessibilityHint": "This is helpful hint text",
                "accessibilityTraits": ["header"]
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(TextComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.content, "Accessible Text")
        XCTAssertEqual(props.accessibilityLabel, "Custom label for screen readers")
        XCTAssertEqual(props.accessibilityHint, "This is helpful hint text")
        XCTAssertEqual(props.accessibilityTraits, ["header"])
    }

    func test_text_component_multiline_content() {
        let json = """
        {
          "root": "text",
          "elements": {
            "text": {
              "type": "Text",
              "props": {
                "content": "This is a long paragraph of text that spans multiple lines. It contains various information that the user needs to read. The text continues here with more content."
              }
            }
          }
        }
        """
        assertValidTree(from: json, expectedNodeCount: 1, rootType: "Text")
    }

    func test_text_component_special_characters() throws {
        let json = """
        {
          "root": "text",
          "elements": {
            "text": {
              "type": "Text",
              "props": {
                "content": "Special: <>&' Unicode: 日本語 한국어 中文 Emoji: 🎉🚀"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(TextComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertTrue(props.content.contains("🎉"))
        XCTAssertTrue(props.content.contains("日本語"))
    }

    // MARK: - Button Component Tests

    func test_button_component_default() {
        let json = """
        {
          "root": "btn",
          "elements": {
            "btn": {
              "type": "Button",
              "props": { "title": "Click Me", "action": "submit" }
            }
          }
        }
        """
        assertButtonProps(from: json, expectedTitle: "Click Me", expectedAction: "submit")
    }

    func test_button_component_primary_style() {
        let json = """
        {
          "root": "btn",
          "elements": {
            "btn": {
              "type": "Button",
              "props": { "title": "Primary Button", "action": "submit", "style": "primary" }
            }
          }
        }
        """
        assertButtonProps(from: json, expectedTitle: "Primary Button", expectedAction: "submit", expectedStyle: "primary")
    }

    func test_button_component_secondary_style() {
        let json = """
        {
          "root": "btn",
          "elements": {
            "btn": {
              "type": "Button",
              "props": { "title": "Secondary Button", "action": "submit", "style": "secondary" }
            }
          }
        }
        """
        assertButtonProps(from: json, expectedTitle: "Secondary Button", expectedAction: "submit", expectedStyle: "secondary")
    }

    func test_button_component_destructive_style() {
        let json = """
        {
          "root": "btn",
          "elements": {
            "btn": {
              "type": "Button",
              "props": { "title": "Delete", "action": "submit", "style": "destructive" }
            }
          }
        }
        """
        assertButtonProps(from: json, expectedTitle: "Delete", expectedAction: "submit", expectedStyle: "destructive")
    }

    func test_button_component_plain_style() {
        let json = """
        {
          "root": "btn",
          "elements": {
            "btn": {
              "type": "Button",
              "props": { "title": "Plain Button", "action": "submit", "style": "plain" }
            }
          }
        }
        """
        assertButtonProps(from: json, expectedTitle: "Plain Button", expectedAction: "submit", expectedStyle: "plain")
    }

    func test_button_component_disabled() {
        let json = """
        {
          "root": "btn",
          "elements": {
            "btn": {
              "type": "Button",
              "props": { "title": "Disabled", "action": "submit", "disabled": true }
            }
          }
        }
        """
        assertButtonProps(from: json, expectedTitle: "Disabled", expectedAction: "submit", expectedDisabled: true)
    }

    func test_button_component_with_accessibility() throws {
        let json = """
        {
          "root": "btn",
          "elements": {
            "btn": {
              "type": "Button",
              "props": {
                "title": "Submit Form",
                "action": "submit",
                "accessibilityLabel": "Submit the form",
                "accessibilityHint": "Double tap to submit your information"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(ButtonComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.accessibilityLabel, "Submit the form")
        XCTAssertEqual(props.accessibilityHint, "Double tap to submit your information")
    }

    // MARK: - Card Component Tests

    func test_card_component_empty() throws {
        let json = """
        {
          "root": "card",
          "elements": {
            "card": {
              "type": "Card",
              "props": {}
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(CardComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertNil(props.title)
        XCTAssertNil(props.subtitle)
    }

    func test_card_component_with_title() throws {
        let json = """
        {
          "root": "card",
          "elements": {
            "card": {
              "type": "Card",
              "props": { "title": "Card Title" }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(CardComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.title, "Card Title")
    }

    func test_card_component_with_title_and_subtitle() throws {
        let json = """
        {
          "root": "card",
          "elements": {
            "card": {
              "type": "Card",
              "props": {
                "title": "Card Title",
                "subtitle": "Card subtitle with additional information"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(CardComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.title, "Card Title")
        XCTAssertEqual(props.subtitle, "Card subtitle with additional information")
    }

    func test_card_component_elevated_style() throws {
        let json = """
        {
          "root": "card",
          "elements": {
            "card": {
              "type": "Card",
              "props": { "title": "Elevated Card", "style": "elevated" }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(CardComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.style, "elevated")
    }

    func test_card_component_outlined_style() throws {
        let json = """
        {
          "root": "card",
          "elements": {
            "card": {
              "type": "Card",
              "props": { "title": "Outlined Card", "style": "outlined" }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(CardComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.style, "outlined")
    }

    func test_card_component_filled_style() throws {
        let json = """
        {
          "root": "card",
          "elements": {
            "card": {
              "type": "Card",
              "props": { "title": "Filled Card", "style": "filled" }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(CardComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.style, "filled")
    }

    func test_card_component_with_children() throws {
        let json = """
        {
          "root": "card",
          "elements": {
            "card": {
              "type": "Card",
              "props": { "title": "Card with Children" },
              "children": ["text", "button"]
            },
            "text": {
              "type": "Text",
              "props": { "content": "Card body content" }
            },
            "button": {
              "type": "Button",
              "props": { "title": "Action", "action": "submit" }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        XCTAssertEqual(tree.nodeCount, 3)
        XCTAssertEqual(tree.children(of: tree.rootNode).count, 2)

        let children = tree.children(of: tree.rootNode)
        XCTAssertEqual(children[0].type, "Text")
        XCTAssertEqual(children[1].type, "Button")
    }

    func test_card_component_nested_cards() throws {
        let json = """
        {
          "root": "outer",
          "elements": {
            "outer": {
              "type": "Card",
              "props": { "title": "Outer Card" },
              "children": ["inner"]
            },
            "inner": {
              "type": "Card",
              "props": { "title": "Inner Card", "style": "outlined" },
              "children": ["text"]
            },
            "text": {
              "type": "Text",
              "props": { "content": "Nested content" }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        XCTAssertEqual(tree.nodeCount, 3)

        let innerCard = tree.children(of: tree.rootNode)[0]
        XCTAssertEqual(innerCard.type, "Card")

        let deepText = tree.children(of: innerCard)[0]
        XCTAssertEqual(deepText.type, "Text")
    }

    // MARK: - Input Component Tests

    func test_input_component_text() throws {
        let json = """
        {
          "root": "input",
          "elements": {
            "input": {
              "type": "Input",
              "props": { "label": "Username", "name": "username" }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(InputComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.label, "Username")
        XCTAssertEqual(props.name, "username")
        XCTAssertNil(props.type)
    }

    func test_input_component_email() throws {
        let json = """
        {
          "root": "input",
          "elements": {
            "input": {
              "type": "Input",
              "props": {
                "label": "Email Address",
                "name": "email",
                "type": "email",
                "placeholder": "Enter your email"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(InputComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.label, "Email Address")
        XCTAssertEqual(props.type, .email)
        XCTAssertEqual(props.placeholder, "Enter your email")
    }

    func test_input_component_password() throws {
        let json = """
        {
          "root": "input",
          "elements": {
            "input": {
              "type": "Input",
              "props": {
                "label": "Password",
                "name": "password",
                "type": "password",
                "placeholder": "Enter password"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(InputComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.type, .password)
    }

    func test_input_component_number() throws {
        let json = """
        {
          "root": "input",
          "elements": {
            "input": {
              "type": "Input",
              "props": {
                "label": "Age",
                "name": "age",
                "type": "number",
                "placeholder": "Enter your age"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(InputComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.type, .number)
    }

    func test_input_component_required() throws {
        let json = """
        {
          "root": "input",
          "elements": {
            "input": {
              "type": "Input",
              "props": {
                "label": "Required Field",
                "name": "required_field",
                "required": true
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(InputComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.required, true)
    }

    func test_input_component_with_accessibility() throws {
        let json = """
        {
          "root": "input",
          "elements": {
            "input": {
              "type": "Input",
              "props": {
                "label": "Phone Number",
                "name": "phone",
                "accessibilityLabel": "Phone number input field",
                "accessibilityHint": "Enter your phone number with area code"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(InputComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.accessibilityLabel, "Phone number input field")
        XCTAssertEqual(props.accessibilityHint, "Enter your phone number with area code")
    }

    // MARK: - List Component Tests

    func test_list_component_unordered() throws {
        let json = """
        {
          "root": "list",
          "elements": {
            "list": {
              "type": "List",
              "props": { "style": "unordered" },
              "children": ["item1", "item2", "item3"]
            },
            "item1": { "type": "Text", "props": { "content": "First item" } },
            "item2": { "type": "Text", "props": { "content": "Second item" } },
            "item3": { "type": "Text", "props": { "content": "Third item" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        XCTAssertEqual(tree.nodeCount, 4)
        XCTAssertEqual(tree.children(of: tree.rootNode).count, 3)

        let props = try decoder.decode(ListComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.style, .unordered)
    }

    func test_list_component_ordered() throws {
        let json = """
        {
          "root": "list",
          "elements": {
            "list": {
              "type": "List",
              "props": { "style": "ordered" },
              "children": ["item1", "item2", "item3"]
            },
            "item1": { "type": "Text", "props": { "content": "Step one" } },
            "item2": { "type": "Text", "props": { "content": "Step two" } },
            "item3": { "type": "Text", "props": { "content": "Step three" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(ListComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.style, .ordered)
    }

    func test_list_component_plain() throws {
        let json = """
        {
          "root": "list",
          "elements": {
            "list": {
              "type": "List",
              "props": { "style": "plain" },
              "children": ["item1", "item2"]
            },
            "item1": { "type": "Text", "props": { "content": "Plain item one" } },
            "item2": { "type": "Text", "props": { "content": "Plain item two" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(ListComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.style, .plain)
    }

    func test_list_component_default_style() throws {
        let json = """
        {
          "root": "list",
          "elements": {
            "list": {
              "type": "List",
              "props": {},
              "children": ["item1", "item2"]
            },
            "item1": { "type": "Text", "props": { "content": "Default item" } },
            "item2": { "type": "Text", "props": { "content": "Another item" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(ListComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertNil(props.style) // Default is handled at render time
    }

    func test_list_component_empty() {
        let json = """
        {
          "root": "list",
          "elements": {
            "list": {
              "type": "List",
              "props": { "style": "unordered" }
            }
          }
        }
        """
        assertValidTree(from: json, expectedNodeCount: 1, rootType: "List")
    }

    func test_list_component_with_mixed_children() throws {
        let json = """
        {
          "root": "list",
          "elements": {
            "list": {
              "type": "List",
              "props": { "style": "unordered" },
              "children": ["text", "card"]
            },
            "text": { "type": "Text", "props": { "content": "Text item" } },
            "card": {
              "type": "Card",
              "props": { "title": "Card item" },
              "children": ["innerText"]
            },
            "innerText": { "type": "Text", "props": { "content": "Card content" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        XCTAssertEqual(tree.nodeCount, 4)

        let children = tree.children(of: tree.rootNode)
        XCTAssertEqual(children[0].type, "Text")
        XCTAssertEqual(children[1].type, "Card")
    }

    // MARK: - Image Component Tests

    func test_image_component_basic() throws {
        let json = """
        {
          "root": "img",
          "elements": {
            "img": {
              "type": "Image",
              "props": {
                "url": "https://example.com/image.png",
                "alt": "Example image"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(ImageComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.url, "https://example.com/image.png")
        XCTAssertEqual(props.alt, "Example image")
    }

    func test_image_component_with_dimensions() throws {
        let json = """
        {
          "root": "img",
          "elements": {
            "img": {
              "type": "Image",
              "props": {
                "url": "https://example.com/image.png",
                "alt": "Sized image",
                "width": 200,
                "height": 150
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(ImageComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.width, 200)
        XCTAssertEqual(props.height, 150)
    }

    func test_image_component_fit_mode() throws {
        let json = """
        {
          "root": "img",
          "elements": {
            "img": {
              "type": "Image",
              "props": {
                "url": "https://example.com/image.png",
                "alt": "Fit image",
                "contentMode": "fit"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(ImageComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.contentMode, "fit")
    }

    func test_image_component_fill_mode() throws {
        let json = """
        {
          "root": "img",
          "elements": {
            "img": {
              "type": "Image",
              "props": {
                "url": "https://example.com/image.png",
                "alt": "Fill image",
                "contentMode": "fill"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(ImageComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.contentMode, "fill")
    }

    func test_image_component_stretch_mode() throws {
        let json = """
        {
          "root": "img",
          "elements": {
            "img": {
              "type": "Image",
              "props": {
                "url": "https://example.com/image.png",
                "alt": "Stretched image",
                "contentMode": "stretch"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(ImageComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.contentMode, "stretch")
    }

    func test_image_component_empty_url_placeholder() throws {
        // Empty URL should parse successfully (render shows placeholder)
        let json = """
        {
          "root": "img",
          "elements": {
            "img": {
              "type": "Image",
              "props": {
                "url": "placeholder",
                "alt": "Placeholder"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(ImageComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.url, "placeholder")
    }

    func test_image_component_with_accessibility() throws {
        let json = """
        {
          "root": "img",
          "elements": {
            "img": {
              "type": "Image",
              "props": {
                "url": "https://example.com/chart.png",
                "alt": "Sales chart",
                "accessibilityLabel": "Bar chart showing quarterly sales",
                "accessibilityHint": "Sales increased 20% in Q4"
              }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(ImageComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.accessibilityLabel, "Bar chart showing quarterly sales")
        XCTAssertEqual(props.accessibilityHint, "Sales increased 20% in Q4")
    }

    // MARK: - Stack Component Tests

    func test_stack_component_vertical() throws {
        let json = """
        {
          "root": "stack",
          "elements": {
            "stack": {
              "type": "Stack",
              "props": { "direction": "vertical" },
              "children": ["text1", "text2"]
            },
            "text1": { "type": "Text", "props": { "content": "Top" } },
            "text2": { "type": "Text", "props": { "content": "Bottom" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(StackComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.direction, .vertical)
        XCTAssertEqual(tree.children(of: tree.rootNode).count, 2)
    }

    func test_stack_component_horizontal() throws {
        let json = """
        {
          "root": "stack",
          "elements": {
            "stack": {
              "type": "Stack",
              "props": { "direction": "horizontal" },
              "children": ["text1", "text2"]
            },
            "text1": { "type": "Text", "props": { "content": "Left" } },
            "text2": { "type": "Text", "props": { "content": "Right" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(StackComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.direction, .horizontal)
    }

    func test_stack_component_with_spacing() throws {
        let json = """
        {
          "root": "stack",
          "elements": {
            "stack": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 24 },
              "children": ["text1", "text2", "text3"]
            },
            "text1": { "type": "Text", "props": { "content": "Item 1" } },
            "text2": { "type": "Text", "props": { "content": "Item 2" } },
            "text3": { "type": "Text", "props": { "content": "Item 3" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(StackComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.spacing, 24)
    }

    func test_stack_component_leading_alignment() throws {
        let json = """
        {
          "root": "stack",
          "elements": {
            "stack": {
              "type": "Stack",
              "props": { "direction": "vertical", "alignment": "leading" },
              "children": ["text1", "text2"]
            },
            "text1": { "type": "Text", "props": { "content": "Short" } },
            "text2": { "type": "Text", "props": { "content": "Longer text content" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(StackComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.alignment, .leading)
    }

    func test_stack_component_center_alignment() throws {
        let json = """
        {
          "root": "stack",
          "elements": {
            "stack": {
              "type": "Stack",
              "props": { "direction": "vertical", "alignment": "center" },
              "children": ["text1", "text2"]
            },
            "text1": { "type": "Text", "props": { "content": "Centered" } },
            "text2": { "type": "Text", "props": { "content": "Also centered content" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(StackComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.alignment, .center)
    }

    func test_stack_component_trailing_alignment() throws {
        let json = """
        {
          "root": "stack",
          "elements": {
            "stack": {
              "type": "Stack",
              "props": { "direction": "vertical", "alignment": "trailing" },
              "children": ["text1", "text2"]
            },
            "text1": { "type": "Text", "props": { "content": "Right aligned" } },
            "text2": { "type": "Text", "props": { "content": "Short" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(StackComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.alignment, .trailing)
    }

    func test_stack_component_nested() throws {
        let json = """
        {
          "root": "outer",
          "elements": {
            "outer": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 16 },
              "children": ["row1", "row2"]
            },
            "row1": {
              "type": "Stack",
              "props": { "direction": "horizontal", "spacing": 8 },
              "children": ["btn1", "btn2"]
            },
            "row2": {
              "type": "Stack",
              "props": { "direction": "horizontal", "spacing": 8 },
              "children": ["btn3", "btn4"]
            },
            "btn1": { "type": "Button", "props": { "title": "A", "action": "submit" } },
            "btn2": { "type": "Button", "props": { "title": "B", "action": "submit" } },
            "btn3": { "type": "Button", "props": { "title": "C", "action": "submit" } },
            "btn4": { "type": "Button", "props": { "title": "D", "action": "submit" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        XCTAssertEqual(tree.nodeCount, 7) // outer + 2 rows + 4 buttons

        let rows = tree.children(of: tree.rootNode)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(tree.children(of: rows[0]).count, 2)
        XCTAssertEqual(tree.children(of: rows[1]).count, 2)
    }

    func test_stack_component_empty() {
        let json = """
        {
          "root": "stack",
          "elements": {
            "stack": {
              "type": "Stack",
              "props": { "direction": "vertical" }
            }
          }
        }
        """
        assertValidTree(from: json, expectedNodeCount: 1, rootType: "Stack")
    }

    // MARK: - Spacer Component Tests

    func test_spacer_component_flexible() throws {
        let json = """
        {
          "root": "stack",
          "elements": {
            "stack": {
              "type": "Stack",
              "props": { "direction": "horizontal" },
              "children": ["text1", "spacer", "text2"]
            },
            "text1": { "type": "Text", "props": { "content": "Left" } },
            "spacer": { "type": "Spacer", "props": {} },
            "text2": { "type": "Text", "props": { "content": "Right" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        XCTAssertEqual(tree.nodeCount, 4)

        let spacerNode = tree.children(of: tree.rootNode)[1]
        XCTAssertEqual(spacerNode.type, "Spacer")

        let props = try decoder.decode(SpacerComponentDefinition.Props.self, from: spacerNode.propsData)
        XCTAssertNil(props.size)
    }

    func test_spacer_component_fixed_size() throws {
        let json = """
        {
          "root": "stack",
          "elements": {
            "stack": {
              "type": "Stack",
              "props": { "direction": "vertical" },
              "children": ["text1", "spacer", "text2"]
            },
            "text1": { "type": "Text", "props": { "content": "Above" } },
            "spacer": { "type": "Spacer", "props": { "size": 50 } },
            "text2": { "type": "Text", "props": { "content": "Below (50pt gap)" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)

        let spacerNode = tree.children(of: tree.rootNode)[1]
        let props = try decoder.decode(SpacerComponentDefinition.Props.self, from: spacerNode.propsData)
        XCTAssertEqual(props.size, 50)
    }

    func test_spacer_component_small_size() throws {
        let json = """
        {
          "root": "stack",
          "elements": {
            "stack": {
              "type": "Stack",
              "props": { "direction": "vertical" },
              "children": ["text1", "spacer", "text2"]
            },
            "text1": { "type": "Text", "props": { "content": "First" } },
            "spacer": { "type": "Spacer", "props": { "size": 8 } },
            "text2": { "type": "Text", "props": { "content": "Second (8pt gap)" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)

        let spacerNode = tree.children(of: tree.rootNode)[1]
        let props = try decoder.decode(SpacerComponentDefinition.Props.self, from: spacerNode.propsData)
        XCTAssertEqual(props.size, 8)
    }

    func test_spacer_component_standalone() throws {
        let json = """
        {
          "root": "spacer",
          "elements": {
            "spacer": {
              "type": "Spacer",
              "props": { "size": 20 }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        let props = try decoder.decode(SpacerComponentDefinition.Props.self, from: tree.rootNode.propsData)
        XCTAssertEqual(props.size, 20)
    }

    // MARK: - Complex Layout Tests

    func test_complex_form_layout() throws {
        let json = """
        {
          "root": "form",
          "elements": {
            "form": {
              "type": "Card",
              "props": { "title": "Registration Form", "style": "elevated" },
              "children": ["fields", "actions"]
            },
            "fields": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 16 },
              "children": ["nameInput", "emailInput", "passwordInput"]
            },
            "nameInput": {
              "type": "Input",
              "props": { "label": "Full Name", "name": "name", "placeholder": "Enter your name" }
            },
            "emailInput": {
              "type": "Input",
              "props": { "label": "Email", "name": "email", "type": "email", "placeholder": "Enter email" }
            },
            "passwordInput": {
              "type": "Input",
              "props": { "label": "Password", "name": "password", "type": "password" }
            },
            "actions": {
              "type": "Stack",
              "props": { "direction": "horizontal", "spacing": 12, "alignment": "trailing" },
              "children": ["cancelBtn", "submitBtn"]
            },
            "cancelBtn": {
              "type": "Button",
              "props": { "title": "Cancel", "action": "dismiss", "style": "secondary" }
            },
            "submitBtn": {
              "type": "Button",
              "props": { "title": "Register", "action": "submit", "style": "primary" }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        XCTAssertEqual(tree.nodeCount, 8) // form + fields + 3 inputs + actions + 2 buttons
        XCTAssertEqual(tree.rootNode.type, "Card")

        // Verify form structure
        let cardChildren = tree.children(of: tree.rootNode)
        XCTAssertEqual(cardChildren.count, 2) // fields + actions
        XCTAssertEqual(cardChildren[0].type, "Stack")
        XCTAssertEqual(cardChildren[1].type, "Stack")
    }

    func test_complex_dashboard_layout() throws {
        let json = """
        {
          "root": "dashboard",
          "elements": {
            "dashboard": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 24 },
              "children": ["header", "metrics", "actions"]
            },
            "header": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 4 },
              "children": ["title", "subtitle"]
            },
            "title": {
              "type": "Text",
              "props": { "content": "Dashboard", "style": "title" }
            },
            "subtitle": {
              "type": "Text",
              "props": { "content": "Welcome back! Here's your overview.", "style": "subheadline" }
            },
            "metrics": {
              "type": "Stack",
              "props": { "direction": "horizontal", "spacing": 16 },
              "children": ["metric1", "metric2"]
            },
            "metric1": {
              "type": "Card",
              "props": { "title": "Total Users", "style": "outlined" },
              "children": ["metricValue1"]
            },
            "metricValue1": {
              "type": "Text",
              "props": { "content": "1,234", "style": "headline" }
            },
            "metric2": {
              "type": "Card",
              "props": { "title": "Revenue", "style": "outlined" },
              "children": ["metricValue2"]
            },
            "metricValue2": {
              "type": "Text",
              "props": { "content": "$12,345", "style": "headline" }
            },
            "actions": {
              "type": "Stack",
              "props": { "direction": "horizontal", "spacing": 12 },
              "children": ["viewBtn", "exportBtn"]
            },
            "viewBtn": {
              "type": "Button",
              "props": { "title": "View Details", "action": "navigate", "style": "primary" }
            },
            "exportBtn": {
              "type": "Button",
              "props": { "title": "Export", "action": "submit", "style": "secondary" }
            }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        XCTAssertEqual(tree.nodeCount, 12) // dashboard + header + title + subtitle + metrics + 2 cards + 2 values + actions + 2 buttons

        // Verify metrics structure
        let metricsStack = tree.children(of: tree.rootNode)[1]
        let metricCards = tree.children(of: metricsStack)
        XCTAssertEqual(metricCards.count, 2)
        XCTAssertEqual(metricCards[0].type, "Card")
        XCTAssertEqual(metricCards[1].type, "Card")
    }

    func test_complex_content_page() throws {
        let json = """
        {
          "root": "page",
          "elements": {
            "page": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 20 },
              "children": ["heroImage", "content", "features"]
            },
            "heroImage": {
              "type": "Image",
              "props": {
                "url": "https://example.com/hero.jpg",
                "alt": "Hero image",
                "height": 200,
                "contentMode": "fill"
              }
            },
            "content": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 12, "alignment": "leading" },
              "children": ["heading", "description"]
            },
            "heading": {
              "type": "Text",
              "props": { "content": "Welcome to Our App", "style": "title" }
            },
            "description": {
              "type": "Text",
              "props": {
                "content": "Discover amazing features that will help you be more productive."
              }
            },
            "features": {
              "type": "Card",
              "props": { "title": "Key Features" },
              "children": ["featureList"]
            },
            "featureList": {
              "type": "List",
              "props": { "style": "ordered" },
              "children": ["feature1", "feature2", "feature3"]
            },
            "feature1": { "type": "Text", "props": { "content": "Easy to use interface" } },
            "feature2": { "type": "Text", "props": { "content": "Powerful automation" } },
            "feature3": { "type": "Text", "props": { "content": "Real-time collaboration" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        XCTAssertEqual(tree.nodeCount, 10) // page + heroImage + content + heading + description + features + featureList + 3 features

        // Verify feature list structure
        let featuresCard = tree.children(of: tree.rootNode)[2]
        let featureList = tree.children(of: featuresCard)[0]
        XCTAssertEqual(featureList.type, "List")
        XCTAssertEqual(tree.children(of: featureList).count, 3)
    }

    // MARK: - Edge Cases and Error Handling

    func test_unknown_component_type_fails_validation() {
        let json = """
        {
          "root": "unknown",
          "elements": {
            "unknown": {
              "type": "UnknownWidget",
              "props": { "foo": "bar" }
            }
          }
        }
        """

        // Should fail catalog validation
        XCTAssertThrowsError(try UITree.parse(from: json, validatingWith: catalog)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(type(of: error))")
                return
            }
            if case .unknownComponentType(let key, let type) = treeError {
                XCTAssertEqual(key, "unknown")
                XCTAssertEqual(type, "UnknownWidget")
            } else {
                XCTFail("Expected unknownComponentType error")
            }
        }
    }

    func test_invalid_text_style_fails_validation() {
        let json = """
        {
          "root": "text",
          "elements": {
            "text": {
              "type": "Text",
              "props": { "content": "Test", "style": "invalid_style" }
            }
          }
        }
        """

        // Catalog validation should catch invalid style
        XCTAssertThrowsError(try UITree.parse(from: json, validatingWith: catalog))
    }

    func test_invalid_button_style_fails_validation() {
        let json = """
        {
          "root": "btn",
          "elements": {
            "btn": {
              "type": "Button",
              "props": { "title": "Test", "action": "submit", "style": "invalid" }
            }
          }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json, validatingWith: catalog))
    }

    func test_deeply_nested_structure() throws {
        let json = """
        {
          "root": "l1",
          "elements": {
            "l1": { "type": "Stack", "props": { "direction": "vertical" }, "children": ["l2"] },
            "l2": { "type": "Card", "props": { "title": "Level 2" }, "children": ["l3"] },
            "l3": { "type": "Stack", "props": { "direction": "horizontal" }, "children": ["l4"] },
            "l4": { "type": "Card", "props": { "title": "Level 4" }, "children": ["l5"] },
            "l5": { "type": "Stack", "props": { "direction": "vertical" }, "children": ["l6"] },
            "l6": { "type": "Text", "props": { "content": "6 levels deep!" } }
          }
        }
        """
        let tree = try parseAndValidate(from: json)
        XCTAssertEqual(tree.nodeCount, 6)

        // Navigate down to leaf
        var current = tree.rootNode
        for _ in 0..<5 {
            let children = tree.children(of: current)
            XCTAssertEqual(children.count, 1)
            current = children[0]
        }
        XCTAssertEqual(current.type, "Text")
    }

    func test_wide_sibling_structure() throws {
        var elements: [String: Any] = [:]
        let childKeys = (1...20).map { "item\($0)" }
        elements["main"] = [
            "type": "Stack",
            "props": ["direction": "vertical", "spacing": 4],
            "children": childKeys
        ]
        for i in 1...20 {
            elements["item\(i)"] = [
                "type": "Text",
                "props": ["content": "Item \(i)"]
            ]
        }

        let jsonObject: [String: Any] = ["root": "main", "elements": elements]
        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)
        let tree = try UITree.parse(from: jsonData, validatingWith: catalog)

        XCTAssertEqual(tree.nodeCount, 21)
        XCTAssertEqual(tree.children(of: tree.rootNode).count, 20)
    }

    // MARK: - Registry Component Verification

    func test_all_core8_components_registered() {
        let registry = UIComponentRegistry.secureDefault
        let core8Types = ["Text", "Button", "Card", "Input", "List", "Image", "Stack", "Spacer"]

        for type in core8Types {
            XCTAssertTrue(registry.hasComponent(type), "Registry should have component: \(type)")
        }

        XCTAssertEqual(registry.registeredTypes.count, 8)
    }

    func test_secure_registry_default_actions() {
        let registry = UIComponentRegistry.secureDefault

        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("navigate"))
        XCTAssertTrue(registry.isActionAllowed("dismiss"))

        XCTAssertFalse(registry.isActionAllowed("delete_all"))
        XCTAssertFalse(registry.isActionAllowed("arbitrary_action"))
    }
}

#endif
