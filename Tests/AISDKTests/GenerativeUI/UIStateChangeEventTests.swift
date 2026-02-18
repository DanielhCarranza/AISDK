//
//  UIStateChangeEventTests.swift
//  AISDKTests
//
//  Tests for UIStateChangeEvent and bidirectional state flow.
//

import XCTest
@testable import AISDK

// MARK: - UIStateChangeEvent Tests

final class UIStateChangeEventTests: XCTestCase {

    func testBasicInitialization() {
        let event = UIStateChangeEvent(
            componentName: "toggle_dark_mode",
            path: "/state/darkMode",
            value: SpecValue(true)
        )

        XCTAssertEqual(event.componentName, "toggle_dark_mode")
        XCTAssertEqual(event.path, "/state/darkMode")
        XCTAssertEqual(event.value, SpecValue(true))
        XCTAssertNil(event.previousValue)
    }

    func testInitializationWithPreviousValue() {
        let event = UIStateChangeEvent(
            componentName: "temperature_slider",
            path: "/state/temperature",
            value: SpecValue(72.5),
            previousValue: SpecValue(68.0)
        )

        XCTAssertEqual(event.componentName, "temperature_slider")
        XCTAssertEqual(event.value, SpecValue(72.5))
        XCTAssertEqual(event.previousValue, SpecValue(68.0))
    }

    func testStringValueChange() {
        let event = UIStateChangeEvent(
            componentName: "name_field",
            path: "/state/userName",
            value: SpecValue("Alice"),
            previousValue: SpecValue("")
        )

        XCTAssertEqual(event.value, SpecValue("Alice"))
        XCTAssertEqual(event.previousValue, SpecValue(""))
    }

    func testTimestampIsSet() {
        let before = Date()
        let event = UIStateChangeEvent(
            componentName: "test",
            path: "/state/test",
            value: SpecValue(1)
        )
        let after = Date()

        XCTAssertGreaterThanOrEqual(event.timestamp, before)
        XCTAssertLessThanOrEqual(event.timestamp, after)
    }

    func testCustomTimestamp() {
        let customDate = Date(timeIntervalSince1970: 1000)
        let event = UIStateChangeEvent(
            componentName: "test",
            path: "/state/test",
            value: SpecValue(1),
            timestamp: customDate
        )

        XCTAssertEqual(event.timestamp, customDate)
    }

    func testEquality() {
        let date = Date(timeIntervalSince1970: 1000)
        let event1 = UIStateChangeEvent(
            componentName: "toggle",
            path: "/state/enabled",
            value: SpecValue(true),
            timestamp: date
        )
        let event2 = UIStateChangeEvent(
            componentName: "toggle",
            path: "/state/enabled",
            value: SpecValue(true),
            timestamp: date
        )

        XCTAssertEqual(event1, event2)
    }

    func testInequality() {
        let date = Date(timeIntervalSince1970: 1000)
        let event1 = UIStateChangeEvent(
            componentName: "toggle",
            path: "/state/enabled",
            value: SpecValue(true),
            timestamp: date
        )
        let event2 = UIStateChangeEvent(
            componentName: "toggle",
            path: "/state/enabled",
            value: SpecValue(false),
            timestamp: date
        )

        XCTAssertNotEqual(event1, event2)
    }

    func testCodableRoundTrip() throws {
        let original = UIStateChangeEvent(
            componentName: "slider",
            path: "/state/volume",
            value: SpecValue(0.75),
            previousValue: SpecValue(0.5),
            timestamp: Date(timeIntervalSince1970: 1234567890)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UIStateChangeEvent.self, from: data)

        XCTAssertEqual(decoded.componentName, original.componentName)
        XCTAssertEqual(decoded.path, original.path)
        XCTAssertEqual(decoded.value, original.value)
        XCTAssertEqual(decoded.previousValue, original.previousValue)
    }

    func testNullValue() {
        let event = UIStateChangeEvent(
            componentName: "clearable_field",
            path: "/state/selection",
            value: .null,
            previousValue: SpecValue("option_a")
        )

        XCTAssertEqual(event.value, .null)
    }
}

// MARK: - ViewModel State Change Tests

#if canImport(SwiftUI)
@MainActor
final class ViewModelStateChangeTests: XCTestCase {

    func testStateChangeHandlerCalled() {
        let viewModel = GenerativeUIViewModel()
        var receivedEvents: [UIStateChangeEvent] = []

        viewModel.onStateChange = { (event: UIStateChangeEvent) in
            receivedEvents.append(event)
        }

        let event = UIStateChangeEvent(
            componentName: "toggle",
            path: "/state/enabled",
            value: SpecValue(true)
        )

        viewModel.handleStateChange(event)

        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents[0].componentName, "toggle")
        XCTAssertEqual(receivedEvents[0].value, SpecValue(true))
    }

    func testMultipleStateChanges() {
        let viewModel = GenerativeUIViewModel()
        var receivedEvents: [UIStateChangeEvent] = []

        viewModel.onStateChange = { (event: UIStateChangeEvent) in
            receivedEvents.append(event)
        }

        viewModel.handleStateChange(UIStateChangeEvent(
            componentName: "slider",
            path: "/state/volume",
            value: SpecValue(0.3)
        ))
        viewModel.handleStateChange(UIStateChangeEvent(
            componentName: "slider",
            path: "/state/volume",
            value: SpecValue(0.7)
        ))
        viewModel.handleStateChange(UIStateChangeEvent(
            componentName: "toggle",
            path: "/state/mute",
            value: SpecValue(true)
        ))

        XCTAssertEqual(receivedEvents.count, 3)
        XCTAssertEqual(receivedEvents[0].value, SpecValue(0.3))
        XCTAssertEqual(receivedEvents[1].value, SpecValue(0.7))
        XCTAssertEqual(receivedEvents[2].componentName, "toggle")
    }

    func testNoHandlerDoesNotCrash() {
        let viewModel = GenerativeUIViewModel()

        // Should not crash when no handler is set
        let event = UIStateChangeEvent(
            componentName: "toggle",
            path: "/state/test",
            value: SpecValue(true)
        )
        viewModel.handleStateChange(event)
    }

    func testStateChangeDoesNotAffectViewModel() {
        let viewModel = GenerativeUIViewModel()
        var called = false

        viewModel.onStateChange = { (_: UIStateChangeEvent) in
            called = true
        }

        viewModel.handleStateChange(UIStateChangeEvent(
            componentName: "test",
            path: "/state/test",
            value: SpecValue(42)
        ))

        XCTAssertTrue(called)
        // State changes are forwarded to the handler, not applied to ViewModel state
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
    }
}
#endif
