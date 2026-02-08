//
//  InteractiveComponents.swift
//  AISDK
//
//  Interactive component definitions for Generative UI
//

import Foundation

// MARK: - Validation Helpers

private func validateRequiredString(
    _ value: String,
    prop: String,
    component: String
) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        throw UIComponentValidationError.invalidPropValue(
            component: component,
            prop: prop,
            reason: "\(prop.capitalized) cannot be empty or whitespace-only"
        )
    }
}

private func validateNoSurroundingWhitespace(
    _ value: String,
    prop: String,
    component: String
) throws {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if value != trimmed {
        throw UIComponentValidationError.invalidPropValue(
            component: component,
            prop: prop,
            reason: "\(prop.capitalized) cannot have leading or trailing whitespace"
        )
    }
}

private func validateFiniteNumber(
    _ value: Double,
    prop: String,
    component: String
) throws {
    guard value.isFinite else {
        throw UIComponentValidationError.invalidPropValue(
            component: component,
            prop: prop,
            reason: "\(prop.capitalized) must be a finite number"
        )
    }
}

// MARK: - Shared Option Model

public struct UIOption: Codable, Sendable {
    public let value: String
    public let label: String
    public let icon: String?

    public init(value: String, label: String, icon: String? = nil) {
        self.value = value
        self.label = label
        self.icon = icon
    }
}

// MARK: - Toggle Component

public struct ToggleComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let label: String
        public let name: String
        public let value: Bool?
        public let disabled: Bool?

        public init(
            label: String,
            name: String,
            value: Bool? = nil,
            disabled: Bool? = nil
        ) {
            self.label = label
            self.name = name
            self.value = value
            self.disabled = disabled
        }
    }

    public static let type = "Toggle"
    public static let description = "Boolean toggle switch"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { label: string (required), name: string (required), value?: boolean, disabled?: boolean }
        """
    public static let allowedPropKeys: Set<String> = [
        "label", "name", "value", "disabled"
    ]

    public static func validate(props: Props) throws {
        try validateRequiredString(props.label, prop: "label", component: type)
        try validateRequiredString(props.name, prop: "name", component: type)
        try validateNoSurroundingWhitespace(props.name, prop: "name", component: type)
    }
}

// MARK: - Slider Component

public struct SliderComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let label: String
        public let name: String
        public let min: Double
        public let max: Double
        public let value: Double?
        public let step: Double?
        public let showValue: Bool?

        public init(
            label: String,
            name: String,
            min: Double,
            max: Double,
            value: Double? = nil,
            step: Double? = nil,
            showValue: Bool? = nil
        ) {
            self.label = label
            self.name = name
            self.min = min
            self.max = max
            self.value = value
            self.step = step
            self.showValue = showValue
        }
    }

    public static let type = "Slider"
    public static let description = "Continuous or stepped slider"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { label: string (required), name: string (required), min: number, max: number, value?: number, \
        step?: number, showValue?: boolean }
        """
    public static let allowedPropKeys: Set<String> = [
        "label", "name", "min", "max", "value", "step", "showValue"
    ]

    public static func validate(props: Props) throws {
        try validateRequiredString(props.label, prop: "label", component: type)
        try validateRequiredString(props.name, prop: "name", component: type)
        try validateNoSurroundingWhitespace(props.name, prop: "name", component: type)
        try validateFiniteNumber(props.min, prop: "min", component: type)
        try validateFiniteNumber(props.max, prop: "max", component: type)
        if props.min >= props.max {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "min",
                reason: "Min must be less than max"
            )
        }
        if let value = props.value {
            try validateFiniteNumber(value, prop: "value", component: type)
            if value < props.min || value > props.max {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "value",
                    reason: "Value must be between min and max"
                )
            }
        }
        if let step = props.step {
            try validateFiniteNumber(step, prop: "step", component: type)
            if step <= 0 {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "step",
                    reason: "Step must be greater than 0"
                )
            }
        }
    }
}

// MARK: - Stepper Component

public struct StepperComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let label: String
        public let name: String
        public let min: Double?
        public let max: Double?
        public let value: Double?
        public let step: Double?
        public let showValue: Bool?

        public init(
            label: String,
            name: String,
            min: Double? = nil,
            max: Double? = nil,
            value: Double? = nil,
            step: Double? = nil,
            showValue: Bool? = nil
        ) {
            self.label = label
            self.name = name
            self.min = min
            self.max = max
            self.value = value
            self.step = step
            self.showValue = showValue
        }
    }

    public static let type = "Stepper"
    public static let description = "Increment/decrement control"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { label: string (required), name: string (required), min?: number, max?: number, value?: number, \
        step?: number, showValue?: boolean }
        """
    public static let allowedPropKeys: Set<String> = [
        "label", "name", "min", "max", "value", "step", "showValue"
    ]

    public static func validate(props: Props) throws {
        try validateRequiredString(props.label, prop: "label", component: type)
        try validateRequiredString(props.name, prop: "name", component: type)
        try validateNoSurroundingWhitespace(props.name, prop: "name", component: type)
        if let min = props.min {
            try validateFiniteNumber(min, prop: "min", component: type)
        }
        if let max = props.max {
            try validateFiniteNumber(max, prop: "max", component: type)
        }
        if let min = props.min, let max = props.max, min >= max {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "min",
                reason: "Min must be less than max"
            )
        }
        if let value = props.value {
            try validateFiniteNumber(value, prop: "value", component: type)
            let minValue = props.min ?? value
            let maxValue = props.max ?? value
            if value < minValue || value > maxValue {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "value",
                    reason: "Value must be between min and max"
                )
            }
        }
        if let step = props.step {
            try validateFiniteNumber(step, prop: "step", component: type)
            if step <= 0 {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "step",
                    reason: "Step must be greater than 0"
                )
            }
        }
    }
}

// MARK: - Segmented Control Component

public struct SegmentedControlComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let name: String
        public let options: [UIOption]
        public let selected: String?

        public init(
            name: String,
            options: [UIOption],
            selected: String? = nil
        ) {
            self.name = name
            self.options = options
            self.selected = selected
        }
    }

    public static let type = "SegmentedControl"
    public static let description = "Segmented control for option selection"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { name: string (required), options: [{ value: string, label: string, icon?: string }], selected?: string }
        """
    public static let allowedPropKeys: Set<String> = [
        "name", "options", "selected"
    ]

    public static func validate(props: Props) throws {
        try validateRequiredString(props.name, prop: "name", component: type)
        try validateNoSurroundingWhitespace(props.name, prop: "name", component: type)
        guard !props.options.isEmpty else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "options",
                reason: "Options must include at least one entry"
            )
        }
        for option in props.options {
            try validateRequiredString(option.value, prop: "value", component: type)
            try validateRequiredString(option.label, prop: "label", component: type)
        }
        if let selected = props.selected, !props.options.map({ $0.value }).contains(selected) {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "selected",
                reason: "Selected value must match one of the option values"
            )
        }
    }
}

// MARK: - Picker Component

public struct PickerComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let name: String
        public let options: [UIOption]
        public let selected: String?

        public init(
            name: String,
            options: [UIOption],
            selected: String? = nil
        ) {
            self.name = name
            self.options = options
            self.selected = selected
        }
    }

    public static let type = "Picker"
    public static let description = "Picker for selecting from options"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { name: string (required), options: [{ value: string, label: string, icon?: string }], selected?: string }
        """
    public static let allowedPropKeys: Set<String> = [
        "name", "options", "selected"
    ]

    public static func validate(props: Props) throws {
        try validateRequiredString(props.name, prop: "name", component: type)
        try validateNoSurroundingWhitespace(props.name, prop: "name", component: type)
        guard !props.options.isEmpty else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "options",
                reason: "Options must include at least one entry"
            )
        }
        for option in props.options {
            try validateRequiredString(option.value, prop: "value", component: type)
            try validateRequiredString(option.label, prop: "label", component: type)
        }
        if let selected = props.selected, !props.options.map({ $0.value }).contains(selected) {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "selected",
                reason: "Selected value must match one of the option values"
            )
        }
    }
}
