//
//  Core8Components.swift
//  AISDK
//
//  Core 8 Component Definitions for Generative UI
//  Public component definitions with comprehensive accessibility support
//

import Foundation

// MARK: - Accessibility Props Protocol

/// Common accessibility properties for UI components
public protocol AccessibilityProps: Codable, Sendable {
    var accessibilityLabel: String? { get }
    var accessibilityHint: String? { get }
    var accessibilityTraits: [String]? { get }
}

// MARK: - Validation Helpers

/// Helper to validate that a required string is not empty or whitespace-only
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

/// Helper to validate accessibility traits (check for non-empty strings)
private func validateAccessibilityTraits(
    _ traits: [String]?,
    component: String
) throws {
    guard let traits else { return }
    for trait in traits where trait.trimmingCharacters(in: .whitespaces).isEmpty {
        throw UIComponentValidationError.invalidPropValue(
            component: component,
            prop: "accessibilityTraits",
            reason: "Accessibility trait cannot be empty"
        )
    }
}

// MARK: - Text Component

/// Text component for displaying text content
public struct TextComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable, AccessibilityProps {
        /// The text content to display (required)
        public let content: String

        /// Text style: "body", "headline", "subheadline", "caption", "title"
        public let style: String?

        /// Accessibility label for screen readers
        public let accessibilityLabel: String?

        /// Accessibility hint describing the result of the action
        public let accessibilityHint: String?

        /// Accessibility traits: "header", "link", "staticText"
        public let accessibilityTraits: [String]?

        public init(
            content: String,
            style: String? = nil,
            accessibilityLabel: String? = nil,
            accessibilityHint: String? = nil,
            accessibilityTraits: [String]? = nil
        ) {
            self.content = content
            self.style = style
            self.accessibilityLabel = accessibilityLabel
            self.accessibilityHint = accessibilityHint
            self.accessibilityTraits = accessibilityTraits
        }
    }

    public static let type = "Text"
    public static let description = "Display text content"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { content: string (required), style?: 'body'|'headline'|'subheadline'|'caption'|'title', \
        accessibilityLabel?: string, accessibilityHint?: string, accessibilityTraits?: string[] }
        """
    public static let allowedPropKeys: Set<String> = [
        "content", "style", "accessibilityLabel", "accessibilityHint", "accessibilityTraits"
    ]

    public static func validate(props: Props) throws {
        try validateRequiredString(props.content, prop: "content", component: type)

        // Validate style if provided
        if let style = props.style {
            let validStyles = ["body", "headline", "subheadline", "caption", "title"]
            if !validStyles.contains(style) {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "style",
                    reason: "Style must be one of: \(validStyles.joined(separator: ", "))"
                )
            }
        }

        try validateAccessibilityTraits(props.accessibilityTraits, component: type)
    }
}

// MARK: - Button Component

/// Button component for interactive actions
public struct ButtonComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable, AccessibilityProps {
        /// Button title text (required)
        public let title: String

        /// Action to trigger when pressed (required, must match registered action)
        public let action: String

        /// Button style: "primary", "secondary", "destructive", "plain"
        public let style: String?

        /// Whether the button is disabled
        public let disabled: Bool?

        /// Accessibility label for screen readers
        public let accessibilityLabel: String?

        /// Accessibility hint describing the result of the action
        public let accessibilityHint: String?

        /// Accessibility traits: "button" (default), "link"
        public let accessibilityTraits: [String]?

        public init(
            title: String,
            action: String,
            style: String? = nil,
            disabled: Bool? = nil,
            accessibilityLabel: String? = nil,
            accessibilityHint: String? = nil,
            accessibilityTraits: [String]? = nil
        ) {
            self.title = title
            self.action = action
            self.style = style
            self.disabled = disabled
            self.accessibilityLabel = accessibilityLabel
            self.accessibilityHint = accessibilityHint
            self.accessibilityTraits = accessibilityTraits
        }
    }

    public static let type = "Button"
    public static let description = "Interactive button that triggers an action"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { title: string (required), action: string (required), style?: 'primary'|'secondary'|'destructive'|'plain', \
        disabled?: boolean, accessibilityLabel?: string, accessibilityHint?: string, accessibilityTraits?: string[] }
        """
    public static let allowedPropKeys: Set<String> = [
        "title", "action", "style", "disabled",
        "accessibilityLabel", "accessibilityHint", "accessibilityTraits"
    ]

    public static func validate(props: Props) throws {
        try validateRequiredString(props.title, prop: "title", component: type)
        try validateRequiredString(props.action, prop: "action", component: type)

        // Validate style if provided
        if let style = props.style {
            let validStyles = ["primary", "secondary", "destructive", "plain"]
            if !validStyles.contains(style) {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "style",
                    reason: "Style must be one of: \(validStyles.joined(separator: ", "))"
                )
            }
        }

        try validateAccessibilityTraits(props.accessibilityTraits, component: type)
    }

    public static func validateWithCatalog(
        props: Props,
        actions: Set<String>,
        validators _: Set<String>
    ) throws {
        // Basic validation
        try validate(props: props)

        // Catalog-aware validation: check action exists in registered actions
        let trimmedAction = props.action.trimmingCharacters(in: .whitespacesAndNewlines)
        if !actions.contains(trimmedAction) {
            throw UIComponentValidationError.unknownAction(
                component: type,
                action: trimmedAction
            )
        }
    }
}

// MARK: - Card Component

/// Card container component with optional title and subtitle
public struct CardComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable, AccessibilityProps {
        /// Card title
        public let title: String?

        /// Card subtitle
        public let subtitle: String?

        /// Card style: "elevated", "outlined", "filled"
        public let style: String?

        /// Accessibility label for screen readers
        public let accessibilityLabel: String?

        /// Accessibility hint describing the result of the action
        public let accessibilityHint: String?

        /// Accessibility traits
        public let accessibilityTraits: [String]?

        public init(
            title: String? = nil,
            subtitle: String? = nil,
            style: String? = nil,
            accessibilityLabel: String? = nil,
            accessibilityHint: String? = nil,
            accessibilityTraits: [String]? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.style = style
            self.accessibilityLabel = accessibilityLabel
            self.accessibilityHint = accessibilityHint
            self.accessibilityTraits = accessibilityTraits
        }
    }

    public static let type = "Card"
    public static let description = "Container card with optional title and subtitle"
    public static let hasChildren = true
    public static let propsSchemaDescription = """
        { title?: string, subtitle?: string, style?: 'elevated'|'outlined'|'filled', \
        accessibilityLabel?: string, accessibilityHint?: string, accessibilityTraits?: string[] }
        """
    public static let allowedPropKeys: Set<String> = [
        "title", "subtitle", "style",
        "accessibilityLabel", "accessibilityHint", "accessibilityTraits"
    ]

    public static func validate(props: Props) throws {
        // Validate style if provided
        if let style = props.style {
            let validStyles = ["elevated", "outlined", "filled"]
            if !validStyles.contains(style) {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "style",
                    reason: "Style must be one of: \(validStyles.joined(separator: ", "))"
                )
            }
        }

        try validateAccessibilityTraits(props.accessibilityTraits, component: type)
    }
}

// MARK: - Input Component

/// Input component for text input fields
public struct InputComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable, AccessibilityProps {
        /// Input label text (required)
        public let label: String

        /// Field name for form submission (required)
        public let name: String

        /// Placeholder text
        public let placeholder: String?

        /// Input type: "text", "email", "password", "number"
        public let type: InputType?

        /// Whether the field is required
        public let required: Bool?

        /// Validator name (must match registered validator)
        public let validation: String?

        /// Accessibility label for screen readers
        public let accessibilityLabel: String?

        /// Accessibility hint describing the result of the action
        public let accessibilityHint: String?

        /// Accessibility traits
        public let accessibilityTraits: [String]?

        public init(
            label: String,
            name: String,
            placeholder: String? = nil,
            type: InputType? = nil,
            required: Bool? = nil,
            validation: String? = nil,
            accessibilityLabel: String? = nil,
            accessibilityHint: String? = nil,
            accessibilityTraits: [String]? = nil
        ) {
            self.label = label
            self.name = name
            self.placeholder = placeholder
            self.type = type
            self.required = required
            self.validation = validation
            self.accessibilityLabel = accessibilityLabel
            self.accessibilityHint = accessibilityHint
            self.accessibilityTraits = accessibilityTraits
        }
    }

    public static let type = "Input"
    public static let description = "Text input field for user data entry"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { label: string (required), name: string (required), placeholder?: string, \
        type?: 'text'|'email'|'password'|'number', required?: boolean, validation?: string, \
        accessibilityLabel?: string, accessibilityHint?: string, accessibilityTraits?: string[] }
        """
    public static let allowedPropKeys: Set<String> = [
        "label", "placeholder", "name", "type", "required", "validation",
        "accessibilityLabel", "accessibilityHint", "accessibilityTraits"
    ]

    public static func validate(props: Props) throws {
        try validateRequiredString(props.label, prop: "label", component: type)
        try validateRequiredString(props.name, prop: "name", component: type)
        try validateAccessibilityTraits(props.accessibilityTraits, component: type)
    }

    public static func validateWithCatalog(
        props: Props,
        actions _: Set<String>,
        validators: Set<String>
    ) throws {
        // Basic validation
        try validate(props: props)

        // Catalog-aware validation: check validator exists in registered validators
        if let validation = props.validation {
            let trimmedValidation = validation.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedValidation.isEmpty {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "validation",
                    reason: "Validation cannot be empty when specified"
                )
            }
            if !validators.contains(trimmedValidation) {
                throw UIComponentValidationError.unknownValidator(
                    component: type,
                    validator: trimmedValidation
                )
            }
        }
    }
}

// MARK: - List Component

/// List container component for ordered/unordered lists
public struct ListComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable, AccessibilityProps {
        /// List style: "ordered", "unordered", "plain"
        public let style: UIListStyle?

        /// Accessibility label for screen readers
        public let accessibilityLabel: String?

        /// Accessibility hint describing the result of the action
        public let accessibilityHint: String?

        /// Accessibility traits
        public let accessibilityTraits: [String]?

        public init(
            style: UIListStyle? = nil,
            accessibilityLabel: String? = nil,
            accessibilityHint: String? = nil,
            accessibilityTraits: [String]? = nil
        ) {
            self.style = style
            self.accessibilityLabel = accessibilityLabel
            self.accessibilityHint = accessibilityHint
            self.accessibilityTraits = accessibilityTraits
        }
    }

    public static let type = "List"
    public static let description = "Ordered or unordered list container"
    public static let hasChildren = true
    public static let propsSchemaDescription = """
        { style?: 'ordered'|'unordered'|'plain', \
        accessibilityLabel?: string, accessibilityHint?: string, accessibilityTraits?: string[] }
        """
    public static let allowedPropKeys: Set<String> = [
        "style", "accessibilityLabel", "accessibilityHint", "accessibilityTraits"
    ]

    public static func validate(props: Props) throws {
        try validateAccessibilityTraits(props.accessibilityTraits, component: type)
    }
}

// MARK: - Image Component

/// Image component for displaying images
public struct ImageComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable, AccessibilityProps {
        /// Image URL (required)
        public let url: String

        /// Alt text for accessibility
        public let alt: String?

        /// Image width in points
        public let width: Double?

        /// Image height in points
        public let height: Double?

        /// Content mode: "fit", "fill", "stretch"
        public let contentMode: String?

        /// Accessibility label for screen readers (renderers may use alt as fallback)
        public let accessibilityLabel: String?

        /// Accessibility hint describing the result of the action
        public let accessibilityHint: String?

        /// Accessibility traits: "image" (default)
        public let accessibilityTraits: [String]?

        public init(
            url: String,
            alt: String? = nil,
            width: Double? = nil,
            height: Double? = nil,
            contentMode: String? = nil,
            accessibilityLabel: String? = nil,
            accessibilityHint: String? = nil,
            accessibilityTraits: [String]? = nil
        ) {
            self.url = url
            self.alt = alt
            self.width = width
            self.height = height
            self.contentMode = contentMode
            self.accessibilityLabel = accessibilityLabel
            self.accessibilityHint = accessibilityHint
            self.accessibilityTraits = accessibilityTraits
        }
    }

    public static let type = "Image"
    public static let description = "Display an image from URL"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { url: string (required), alt?: string, width?: number, height?: number, \
        contentMode?: 'fit'|'fill'|'stretch', accessibilityLabel?: string, accessibilityHint?: string, \
        accessibilityTraits?: string[] }
        """
    public static let allowedPropKeys: Set<String> = [
        "url", "alt", "width", "height", "contentMode",
        "accessibilityLabel", "accessibilityHint", "accessibilityTraits"
    ]

    public static func validate(props: Props) throws {
        try validateRequiredString(props.url, prop: "url", component: type)

        if let width = props.width, width <= 0 {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "width",
                reason: "Width must be positive"
            )
        }
        if let height = props.height, height <= 0 {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "height",
                reason: "Height must be positive"
            )
        }

        // Validate content mode if provided
        if let contentMode = props.contentMode {
            let validModes = ["fit", "fill", "stretch"]
            if !validModes.contains(contentMode) {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "contentMode",
                    reason: "Content mode must be one of: \(validModes.joined(separator: ", "))"
                )
            }
        }

        try validateAccessibilityTraits(props.accessibilityTraits, component: type)
    }
}

// MARK: - Stack Component

/// Stack layout component for horizontal/vertical arrangement
public struct StackComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable, AccessibilityProps {
        /// Stack direction: "horizontal" or "vertical" (required)
        public let direction: StackDirection

        /// Spacing between children in points
        public let spacing: Double?

        /// Alignment: "leading", "center", "trailing"
        public let alignment: StackAlignment?

        /// Accessibility label for screen readers
        public let accessibilityLabel: String?

        /// Accessibility hint describing the result of the action
        public let accessibilityHint: String?

        /// Accessibility traits
        public let accessibilityTraits: [String]?

        public init(
            direction: StackDirection,
            spacing: Double? = nil,
            alignment: StackAlignment? = nil,
            accessibilityLabel: String? = nil,
            accessibilityHint: String? = nil,
            accessibilityTraits: [String]? = nil
        ) {
            self.direction = direction
            self.spacing = spacing
            self.alignment = alignment
            self.accessibilityLabel = accessibilityLabel
            self.accessibilityHint = accessibilityHint
            self.accessibilityTraits = accessibilityTraits
        }
    }

    public static let type = "Stack"
    public static let description = "Layout container for horizontal or vertical arrangement"
    public static let hasChildren = true
    public static let propsSchemaDescription = """
        { direction: 'horizontal'|'vertical' (required), spacing?: number, \
        alignment?: 'leading'|'center'|'trailing', \
        accessibilityLabel?: string, accessibilityHint?: string, accessibilityTraits?: string[] }
        """
    public static let allowedPropKeys: Set<String> = [
        "direction", "spacing", "alignment",
        "accessibilityLabel", "accessibilityHint", "accessibilityTraits"
    ]

    public static func validate(props: Props) throws {
        if let spacing = props.spacing, spacing < 0 {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "spacing",
                reason: "Spacing cannot be negative"
            )
        }

        try validateAccessibilityTraits(props.accessibilityTraits, component: type)
    }
}

// MARK: - Spacer Component

/// Spacer component for flexible spacing
public struct SpacerComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable, AccessibilityProps {
        /// Fixed size in points (optional, flexible if not set)
        public let size: Double?

        /// Accessibility label for screen readers
        public let accessibilityLabel: String?

        /// Accessibility hint describing the result of the action
        public let accessibilityHint: String?

        /// Accessibility traits
        public let accessibilityTraits: [String]?

        public init(
            size: Double? = nil,
            accessibilityLabel: String? = nil,
            accessibilityHint: String? = nil,
            accessibilityTraits: [String]? = nil
        ) {
            self.size = size
            self.accessibilityLabel = accessibilityLabel
            self.accessibilityHint = accessibilityHint
            self.accessibilityTraits = accessibilityTraits
        }
    }

    public static let type = "Spacer"
    public static let description = "Flexible space between elements"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { size?: number, accessibilityLabel?: string, accessibilityHint?: string, accessibilityTraits?: string[] }
        """
    public static let allowedPropKeys: Set<String> = [
        "size", "accessibilityLabel", "accessibilityHint", "accessibilityTraits"
    ]

    public static func validate(props: Props) throws {
        if let size = props.size, size < 0 {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "size",
                reason: "Size cannot be negative"
            )
        }

        try validateAccessibilityTraits(props.accessibilityTraits, component: type)
    }
}
