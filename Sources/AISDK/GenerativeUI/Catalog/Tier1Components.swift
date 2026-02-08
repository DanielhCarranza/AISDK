//
//  Tier1Components.swift
//  AISDK
//
//  Tier 1 component definitions for Generative UI
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

private func validateOptionalString(
    _ value: String?,
    prop: String,
    component: String
) throws {
    guard let value else { return }
    try validateRequiredString(value, prop: prop, component: component)
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

// MARK: - Metric Component

public struct MetricComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let label: String
        public let value: Double
        public let format: MetricFormat?
        public let trend: Trend?
        public let change: Double?
        public let prefix: String?
        public let suffix: String?

        public init(
            label: String,
            value: Double,
            format: MetricFormat? = nil,
            trend: Trend? = nil,
            change: Double? = nil,
            prefix: String? = nil,
            suffix: String? = nil
        ) {
            self.label = label
            self.value = value
            self.format = format
            self.trend = trend
            self.change = change
            self.prefix = prefix
            self.suffix = suffix
        }
    }

    public enum MetricFormat: String, Codable, Sendable {
        case number
        case currency
        case percent
        case compact
    }

    public enum Trend: String, Codable, Sendable {
        case up
        case down
        case neutral
    }

    public static let type = "Metric"
    public static let description = "Display a key metric with optional trend and change"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { label: string (required), value: number (required), format?: 'number'|'currency'|'percent'|'compact', \
        trend?: 'up'|'down'|'neutral', change?: number, prefix?: string, suffix?: string }
        """
    public static let allowedPropKeys: Set<String> = [
        "label", "value", "format", "trend", "change", "prefix", "suffix"
    ]

    public static func validate(props: Props) throws {
        try validateRequiredString(props.label, prop: "label", component: type)
        try validateFiniteNumber(props.value, prop: "value", component: type)
        if let change = props.change {
            try validateFiniteNumber(change, prop: "change", component: type)
        }
        try validateOptionalString(props.prefix, prop: "prefix", component: type)
        try validateOptionalString(props.suffix, prop: "suffix", component: type)
    }
}

// MARK: - Badge Component

public struct BadgeComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let text: String
        public let variant: BadgeVariant?
        public let size: BadgeSize?

        public init(
            text: String,
            variant: BadgeVariant? = nil,
            size: BadgeSize? = nil
        ) {
            self.text = text
            self.variant = variant
            self.size = size
        }
    }

    public enum BadgeVariant: String, Codable, Sendable {
        case `default`
        case success
        case warning
        case error
        case info
    }

    public enum BadgeSize: String, Codable, Sendable {
        case small
        case medium
        case large
    }

    public static let type = "Badge"
    public static let description = "Display a small status badge"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { text: string (required), variant?: 'default'|'success'|'warning'|'error'|'info', size?: 'small'|'medium'|'large' }
        """
    public static let allowedPropKeys: Set<String> = [
        "text", "variant", "size"
    ]

    public static func validate(props: Props) throws {
        try validateRequiredString(props.text, prop: "text", component: type)
    }
}

// MARK: - Divider Component

public struct DividerComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let label: String?
        public let style: DividerStyle?

        public init(
            label: String? = nil,
            style: DividerStyle? = nil
        ) {
            self.label = label
            self.style = style
        }
    }

    public enum DividerStyle: String, Codable, Sendable {
        case solid
        case dashed
    }

    public static let type = "Divider"
    public static let description = "Visual separator with optional label"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { label?: string, style?: 'solid'|'dashed' }
        """
    public static let allowedPropKeys: Set<String> = [
        "label", "style"
    ]

    public static func validate(props: Props) throws {
        try validateOptionalString(props.label, prop: "label", component: type)
    }
}

// MARK: - Section Component

public struct SectionComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let title: String?
        public let subtitle: String?
        public let collapsible: Bool?

        public init(
            title: String? = nil,
            subtitle: String? = nil,
            collapsible: Bool? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.collapsible = collapsible
        }
    }

    public static let type = "Section"
    public static let description = "Group content with optional header and subtitle"
    public static let hasChildren = true
    public static let propsSchemaDescription = """
        { title?: string, subtitle?: string, collapsible?: boolean }
        """
    public static let allowedPropKeys: Set<String> = [
        "title", "subtitle", "collapsible"
    ]

    public static func validate(props: Props) throws {
        try validateOptionalString(props.title, prop: "title", component: type)
        try validateOptionalString(props.subtitle, prop: "subtitle", component: type)
    }
}

// MARK: - Progress Component

public struct ProgressComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let value: Double?
        public let label: String?
        public let showValue: Bool?
        public let style: ProgressStyle?
        public let color: ProgressColor?

        public init(
            value: Double? = nil,
            label: String? = nil,
            showValue: Bool? = nil,
            style: ProgressStyle? = nil,
            color: ProgressColor? = nil
        ) {
            self.value = value
            self.label = label
            self.showValue = showValue
            self.style = style
            self.color = color
        }
    }

    public enum ProgressStyle: String, Codable, Sendable {
        case linear
        case circular
    }

    public enum ProgressColor: String, Codable, Sendable {
        case accent
        case success
        case warning
        case error
    }

    public static let type = "Progress"
    public static let description = "Progress indicator, determinate or indeterminate"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { value?: number (0.0-1.0), label?: string, showValue?: boolean, style?: 'linear'|'circular', \
        color?: 'accent'|'success'|'warning'|'error' }
        """
    public static let allowedPropKeys: Set<String> = [
        "value", "label", "showValue", "style", "color"
    ]

    public static func validate(props: Props) throws {
        if let value = props.value {
            try validateFiniteNumber(value, prop: "value", component: type)
            guard (0.0...1.0).contains(value) else {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "value",
                    reason: "Value must be between 0.0 and 1.0"
                )
            }
        }
        try validateOptionalString(props.label, prop: "label", component: type)
    }
}
