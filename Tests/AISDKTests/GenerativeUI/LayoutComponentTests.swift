//
//  LayoutComponentTests.swift
//  AISDKTests
//
//  Tests for layout GenerativeUI components
//

#if canImport(SwiftUI)
import XCTest
@testable import AISDK

final class LayoutComponentTests: XCTestCase {
    private let catalog = UICatalog.extended

    private func parseTree(_ json: String) throws -> UITree {
        try UITree.parse(from: json, validatingWith: catalog)
    }

    func test_grid_parses() throws {
        let json = """
        {
          "root": "grid",
          "elements": {
            "grid": {
              "type": "Grid",
              "props": { "columns": 2, "spacing": 8 },
              "children": ["t1", "t2"]
            },
            "t1": { "type": "Text", "props": { "content": "One" } },
            "t2": { "type": "Text", "props": { "content": "Two" } }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Grid")
        XCTAssertEqual(tree.children(of: tree.rootNode).count, 2)
    }

    func test_tabs_parses() throws {
        let json = """
        {
          "root": "tabs",
          "elements": {
            "tabs": {
              "type": "Tabs",
              "props": {
                "tabs": [
                  { "key": "overview", "label": "Overview" },
                  { "key": "details", "label": "Details" }
                ],
                "selected": "overview"
              },
              "children": ["overview", "details"]
            },
            "overview": { "type": "Text", "props": { "content": "Overview content" } },
            "details": { "type": "Text", "props": { "content": "Details content" } }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Tabs")
        XCTAssertEqual(tree.children(of: tree.rootNode).count, 2)
    }

    func test_accordion_parses() throws {
        let json = """
        {
          "root": "accordion",
          "elements": {
            "accordion": {
              "type": "Accordion",
              "props": {
                "items": [
                  { "key": "one", "title": "First" },
                  { "key": "two", "title": "Second", "subtitle": "Details" }
                ]
              },
              "children": ["oneContent", "twoContent"]
            },
            "oneContent": { "type": "Text", "props": { "content": "First content" } },
            "twoContent": { "type": "Text", "props": { "content": "Second content" } }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Accordion")
        XCTAssertEqual(tree.children(of: tree.rootNode).count, 2)
    }

    func test_grid_rejects_invalid_columns() {
        let json = """
        {
          "root": "grid",
          "elements": {
            "grid": {
              "type": "Grid",
              "props": { "columns": 0 },
              "children": []
            }
          }
        }
        """

        XCTAssertThrowsError(try parseTree(json))
    }
}
#endif
