//
//  ChartComponentTests.swift
//  AISDKTests
//
//  Tests for chart GenerativeUI components
//

#if canImport(SwiftUI)
import XCTest
@testable import AISDK

final class ChartComponentTests: XCTestCase {
    private let catalog = UICatalog.extended

    private func parseTree(_ json: String) throws -> UITree {
        try UITree.parse(from: json, validatingWith: catalog)
    }

    func test_bar_chart_parses() throws {
        let json = """
        {
          "root": "chart",
          "elements": {
            "chart": {
              "type": "BarChart",
              "props": {
                "data": [
                  { "label": "Jan", "value": 100 },
                  { "label": "Feb", "value": 150 }
                ],
                "orientation": "vertical",
                "showValues": true
              }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "BarChart")
    }

    func test_line_chart_parses() throws {
        let json = """
        {
          "root": "chart",
          "elements": {
            "chart": {
              "type": "LineChart",
              "props": {
                "series": [
                  {
                    "name": "Revenue",
                    "data": [
                      { "x": "Jan", "y": 100 },
                      { "x": "Feb", "y": 150 }
                    ]
                  }
                ],
                "showPoints": true
              }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "LineChart")
    }

    func test_pie_chart_parses() throws {
        let json = """
        {
          "root": "chart",
          "elements": {
            "chart": {
              "type": "PieChart",
              "props": {
                "data": [
                  { "label": "Desktop", "value": 60 },
                  { "label": "Mobile", "value": 40 }
                ],
                "donut": true
              }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "PieChart")
    }

    func test_gauge_parses() throws {
        let json = """
        {
          "root": "gauge",
          "elements": {
            "gauge": {
              "type": "Gauge",
              "props": { "value": 0.7, "min": 0, "max": 1, "showValue": true }
            }
          }
        }
        """

        let tree = try parseTree(json)
        XCTAssertEqual(tree.rootNode.type, "Gauge")
    }

    func test_gauge_rejects_invalid_range() {
        let json = """
        {
          "root": "gauge",
          "elements": {
            "gauge": {
              "type": "Gauge",
              "props": { "value": 50, "min": 100, "max": 10 }
            }
          }
        }
        """

        XCTAssertThrowsError(try parseTree(json))
    }
}
#endif
