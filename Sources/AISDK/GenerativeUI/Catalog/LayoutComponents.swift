//
//  LayoutComponents.swift
//  AISDK
//
//  Layout component definitions for Generative UI
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

// MARK: - Grid Component

public struct GridComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let columns: Int
        public let spacing: Double?
        public let alignment: GridAlignment?

        public init(
            columns: Int,
            spacing: Double? = nil,
            alignment: GridAlignment? = nil
        ) {
            self.columns = columns
            self.spacing = spacing
            self.alignment = alignment
        }
    }

    public enum GridAlignment: String, Codable, Sendable {
        case leading
        case center
        case trailing
    }

    public static let type = "Grid"
    public static let description = "Multi-column grid layout"
    public static let hasChildren = true
    public static let propsSchemaDescription = """
        { columns: number (required), spacing?: number, alignment?: 'leading'|'center'|'trailing' }
        """
    public static let allowedPropKeys: Set<String> = [
        "columns", "spacing", "alignment"
    ]

    public static func validate(props: Props) throws {
        guard props.columns > 0 else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "columns",
                reason: "Columns must be greater than 0"
            )
        }
        if let spacing = props.spacing {
            try validateFiniteNumber(spacing, prop: "spacing", component: type)
            if spacing < 0 {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "spacing",
                    reason: "Spacing must be 0 or greater"
                )
            }
        }
    }
}

// MARK: - Tabs Component

public struct TabsComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let tabs: [TabItem]
        public let selected: String?

        public init(tabs: [TabItem], selected: String? = nil) {
            self.tabs = tabs
            self.selected = selected
        }
    }

    public struct TabItem: Codable, Sendable {
        public let key: String
        public let label: String
        public let icon: String?

        public init(key: String, label: String, icon: String? = nil) {
            self.key = key
            self.label = label
            self.icon = icon
        }
    }

    public static let type = "Tabs"
    public static let description = "Tabbed content container"
    public static let hasChildren = true
    public static let propsSchemaDescription = """
        { tabs: [{ key: string, label: string, icon?: string }], selected?: string }
        """
    public static let allowedPropKeys: Set<String> = [
        "tabs", "selected"
    ]

    public static func validate(props: Props) throws {
        guard !props.tabs.isEmpty else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "tabs",
                reason: "Tabs must include at least one entry"
            )
        }
        for tab in props.tabs {
            try validateRequiredString(tab.key, prop: "key", component: type)
            try validateRequiredString(tab.label, prop: "label", component: type)
        }
        if let selected = props.selected, !props.tabs.map({ $0.key }).contains(selected) {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "selected",
                reason: "Selected tab must match one of the tab keys"
            )
        }
    }
}

// MARK: - Accordion Component

public struct AccordionComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let items: [AccordionItem]

        public init(items: [AccordionItem]) {
            self.items = items
        }
    }

    public struct AccordionItem: Codable, Sendable {
        public let key: String
        public let title: String
        public let subtitle: String?

        public init(key: String, title: String, subtitle: String? = nil) {
            self.key = key
            self.title = title
            self.subtitle = subtitle
        }
    }

    public static let type = "Accordion"
    public static let description = "Collapsible sections"
    public static let hasChildren = true
    public static let propsSchemaDescription = """
        { items: [{ key: string, title: string, subtitle?: string }] }
        """
    public static let allowedPropKeys: Set<String> = [
        "items"
    ]

    public static func validate(props: Props) throws {
        guard !props.items.isEmpty else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "items",
                reason: "Items must include at least one entry"
            )
        }
        for item in props.items {
            try validateRequiredString(item.key, prop: "key", component: type)
            try validateRequiredString(item.title, prop: "title", component: type)
        }
    }
}
