//
//  Tier1ComponentTests.swift
//  AISDKTests
//
//  Tests for Tier 1 GenerativeUI components
//

#if canImport(SwiftUI)
import XCTest
@testable import AISDK

final class Tier1ComponentTests: XCTestCase {
    private let catalog = UICatalog.extended

    private func parseTree(_ json: String) throws -> UITree {
        try UITree.parse(from: json, validatingWith: catalog)
    }

    func test_metric_component_parses() throws {
        let json = """
        {
          "root": "metric",
          "elements": {
            "metric": {
              "type": "Metric",
              "props": {
                "label": "Revenue",
                "value": 125000,
                "format": "currency",
                "trend": "up",
                "change": 12.5
              }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Metric")
    }

    func test_badge_component_parses() throws {
        let json = """
        {
          "root": "badge",
          "elements": {
            "badge": {
              "type": "Badge",
              "props": {
                "text": "Active",
                "variant": "success",
                "size": "small"
              }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Badge")
    }

    func test_divider_component_parses() throws {
        let json = """
        {
          "root": "divider",
          "elements": {
            "divider": {
              "type": "Divider",
              "props": { "label": "OR", "style": "dashed" }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Divider")
    }

    func test_section_component_parses_children() throws {
        let json = """
        {
          "root": "section",
          "elements": {
            "section": {
              "type": "Section",
              "props": { "title": "Settings", "subtitle": "Profile" },
              "children": ["text1"]
            },
            "text1": {
              "type": "Text",
              "props": { "content": "Account" }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Section")
        XCTAssertEqual(tree.children(of: tree.rootNode).count, 1)
    }

    func test_progress_component_parses() throws {
        let json = """
        {
          "root": "progress",
          "elements": {
            "progress": {
              "type": "Progress",
              "props": { "value": 0.75, "label": "Upload", "showValue": true, "style": "linear" }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Progress")
    }

    func test_progress_component_rejects_out_of_range() {
        let json = """
        {
          "root": "progress",
          "elements": {
            "progress": {
              "type": "Progress",
              "props": { "value": 1.5 }
            }
          }
        }
        """

        XCTAssertThrowsError(try parseTree(json))
    }
}
#endif
