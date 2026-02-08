//
//  InteractiveComponentTests.swift
//  AISDKTests
//
//  Tests for interactive GenerativeUI components
//

#if canImport(SwiftUI)
import XCTest
@testable import AISDK

final class InteractiveComponentTests: XCTestCase {
    private let catalog = UICatalog.extended

    private func parseTree(_ json: String) throws -> UITree {
        try UITree.parse(from: json, validatingWith: catalog)
    }

    func test_toggle_parses() throws {
        let json = """
        {
          "root": "toggle",
          "elements": {
            "toggle": {
              "type": "Toggle",
              "props": { "label": "Enable", "name": "enable", "value": true }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Toggle")
    }

    func test_slider_parses() throws {
        let json = """
        {
          "root": "slider",
          "elements": {
            "slider": {
              "type": "Slider",
              "props": { "label": "Volume", "name": "volume", "min": 0, "max": 100, "value": 50 }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Slider")
    }

    func test_stepper_parses() throws {
        let json = """
        {
          "root": "stepper",
          "elements": {
            "stepper": {
              "type": "Stepper",
              "props": { "label": "Guests", "name": "guests", "min": 1, "max": 10, "value": 2 }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Stepper")
    }

    func test_segmented_control_parses() throws {
        let json = """
        {
          "root": "segmented",
          "elements": {
            "segmented": {
              "type": "SegmentedControl",
              "props": {
                "name": "view",
                "options": [
                  { "value": "list", "label": "List" },
                  { "value": "grid", "label": "Grid" }
                ],
                "selected": "list"
              }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "SegmentedControl")
    }

    func test_picker_parses() throws {
        let json = """
        {
          "root": "picker",
          "elements": {
            "picker": {
              "type": "Picker",
              "props": {
                "name": "theme",
                "options": [
                  { "value": "light", "label": "Light" },
                  { "value": "dark", "label": "Dark" }
                ]
              }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Picker")
    }

    func test_slider_rejects_invalid_range() {
        let json = """
        {
          "root": "slider",
          "elements": {
            "slider": {
              "type": "Slider",
              "props": { "label": "Volume", "name": "volume", "min": 10, "max": 5 }
            }
          }
        }
        """

        XCTAssertThrowsError(try parseTree(json))
    }
}
#endif
