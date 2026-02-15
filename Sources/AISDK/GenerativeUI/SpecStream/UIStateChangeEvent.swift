//
//  UIStateChangeEvent.swift
//  AISDK
//
//  Event emitted when a user interacts with a generative UI component.
//  Enables bidirectional state flow between UI and agent.
//

import Foundation

// MARK: - UIStateChangeEvent

/// Event emitted when a user interacts with a generative UI component.
///
/// `UIStateChangeEvent` captures the state change from interactive components
/// (Toggle, Slider, TextField, Picker, etc.) and provides enough context for
/// the agent to react to the change.
///
/// ## Usage
/// ```swift
/// let event = UIStateChangeEvent(
///     componentName: "temperature_slider",
///     path: "/state/temperature",
///     value: .double(72.5),
///     previousValue: .double(68.0)
/// )
///
/// // Send to agent
/// await agent.injectStateChange(event)
/// ```
public struct UIStateChangeEvent: Sendable, Codable, Equatable {
    /// The component name (from interactive component's `name` prop)
    public let componentName: String

    /// The state path this change targets (e.g., "/state/temperature")
    public let path: String

    /// The new value after the change
    public let value: SpecValue

    /// The previous value before the change (nil for initial values)
    public let previousValue: SpecValue?

    /// Timestamp of the change
    public let timestamp: Date

    public init(
        componentName: String,
        path: String,
        value: SpecValue,
        previousValue: SpecValue? = nil,
        timestamp: Date = Date()
    ) {
        self.componentName = componentName
        self.path = path
        self.value = value
        self.previousValue = previousValue
        self.timestamp = timestamp
    }
}

// MARK: - UIStateChangeHandler

/// Handler for state changes from interactive components.
///
/// Called when a generative UI component's value changes due to user interaction.
/// Implementations should be lightweight — heavy processing should be dispatched.
public typealias UIStateChangeHandler = @Sendable (UIStateChangeEvent) -> Void
