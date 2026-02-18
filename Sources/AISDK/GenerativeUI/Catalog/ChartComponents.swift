//
//  ChartComponents.swift
//  AISDK
//
//  Chart component definitions for Generative UI
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

// MARK: - Chart Data Models

public struct ChartDataPoint: Codable, Sendable {
    public let label: String
    public let value: Double
    public let color: String?

    public init(label: String, value: Double, color: String? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }
}

public struct ChartSeries: Codable, Sendable {
    public let name: String
    public let data: [SeriesPoint]
    public let color: String?

    public struct SeriesPoint: Codable, Sendable {
        public let x: String
        public let y: Double

        public init(x: String, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public init(name: String, data: [SeriesPoint], color: String? = nil) {
        self.name = name
        self.data = data
        self.color = color
    }
}

public struct PieSlice: Codable, Sendable {
    public let label: String
    public let value: Double
    public let color: String?

    public init(label: String, value: Double, color: String? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }
}

// MARK: - Bar Chart Component

public struct BarChartComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let data: [ChartDataPoint]
        public let orientation: Orientation?
        public let showLabels: Bool?
        public let showValues: Bool?
        public let barColor: String?
        public let height: Double?

        public init(
            data: [ChartDataPoint],
            orientation: Orientation? = nil,
            showLabels: Bool? = nil,
            showValues: Bool? = nil,
            barColor: String? = nil,
            height: Double? = nil
        ) {
            self.data = data
            self.orientation = orientation
            self.showLabels = showLabels
            self.showValues = showValues
            self.barColor = barColor
            self.height = height
        }
    }

    public enum Orientation: String, Codable, Sendable {
        case vertical
        case horizontal
    }

    public static let type = "BarChart"
    public static let description = "Bar chart visualization"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { data: [{ label: string, value: number, color?: string }], orientation?: 'vertical'|'horizontal', \
        showLabels?: boolean, showValues?: boolean, barColor?: string, height?: number }
        """
    public static let allowedPropKeys: Set<String> = [
        "data", "orientation", "showLabels", "showValues", "barColor", "height"
    ]

    public static func validate(props: Props) throws {
        guard !props.data.isEmpty else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "data",
                reason: "Data must include at least one point"
            )
        }
        for point in props.data {
            try validateRequiredString(point.label, prop: "label", component: type)
            try validateFiniteNumber(point.value, prop: "value", component: type)
        }
        if let height = props.height {
            try validateFiniteNumber(height, prop: "height", component: type)
            if height <= 0 {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "height",
                    reason: "Height must be greater than 0"
                )
            }
        }
    }
}

// MARK: - Line Chart Component

public struct LineChartComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let series: [ChartSeries]
        public let showPoints: Bool?
        public let smooth: Bool?
        public let showGrid: Bool?
        public let height: Double?

        public init(
            series: [ChartSeries],
            showPoints: Bool? = nil,
            smooth: Bool? = nil,
            showGrid: Bool? = nil,
            height: Double? = nil
        ) {
            self.series = series
            self.showPoints = showPoints
            self.smooth = smooth
            self.showGrid = showGrid
            self.height = height
        }
    }

    public static let type = "LineChart"
    public static let description = "Line chart visualization"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { series: [{ name: string, data: [{ x: string, y: number }], color?: string }], \
        showPoints?: boolean, smooth?: boolean, showGrid?: boolean, height?: number }
        """
    public static let allowedPropKeys: Set<String> = [
        "series", "showPoints", "smooth", "showGrid", "height"
    ]

    public static func validate(props: Props) throws {
        guard !props.series.isEmpty else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "series",
                reason: "Series must include at least one entry"
            )
        }
        for series in props.series {
            try validateRequiredString(series.name, prop: "name", component: type)
            guard !series.data.isEmpty else {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "data",
                    reason: "Series must include at least one data point"
                )
            }
            for point in series.data {
                try validateRequiredString(point.x, prop: "x", component: type)
                try validateFiniteNumber(point.y, prop: "y", component: type)
            }
        }
        if let height = props.height {
            try validateFiniteNumber(height, prop: "height", component: type)
            if height <= 0 {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "height",
                    reason: "Height must be greater than 0"
                )
            }
        }
    }
}

// MARK: - Pie Chart Component

public struct PieChartComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let data: [PieSlice]
        public let donut: Bool?
        public let showLegend: Bool?
        public let showLabels: Bool?

        public init(
            data: [PieSlice],
            donut: Bool? = nil,
            showLegend: Bool? = nil,
            showLabels: Bool? = nil
        ) {
            self.data = data
            self.donut = donut
            self.showLegend = showLegend
            self.showLabels = showLabels
        }
    }

    public static let type = "PieChart"
    public static let description = "Pie or donut chart visualization"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { data: [{ label: string, value: number, color?: string }], donut?: boolean, \
        showLegend?: boolean, showLabels?: boolean }
        """
    public static let allowedPropKeys: Set<String> = [
        "data", "donut", "showLegend", "showLabels"
    ]

    public static func validate(props: Props) throws {
        guard !props.data.isEmpty else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "data",
                reason: "Data must include at least one slice"
            )
        }
        for slice in props.data {
            try validateRequiredString(slice.label, prop: "label", component: type)
            try validateFiniteNumber(slice.value, prop: "value", component: type)
            if slice.value < 0 {
                throw UIComponentValidationError.invalidPropValue(
                    component: type,
                    prop: "value",
                    reason: "Slice values must be non-negative"
                )
            }
        }
    }
}

// MARK: - Gauge Component

public struct GaugeComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let value: Double
        public let label: String?
        public let min: Double?
        public let max: Double?
        public let showValue: Bool?
        public let color: String?

        public init(
            value: Double,
            label: String? = nil,
            min: Double? = nil,
            max: Double? = nil,
            showValue: Bool? = nil,
            color: String? = nil
        ) {
            self.value = value
            self.label = label
            self.min = min
            self.max = max
            self.showValue = showValue
            self.color = color
        }
    }

    public static let type = "Gauge"
    public static let description = "Circular gauge for progress or usage"
    public static let hasChildren = false
    public static let propsSchemaDescription = """
        { value: number, label?: string, min?: number, max?: number, showValue?: boolean, color?: string }
        """
    public static let allowedPropKeys: Set<String> = [
        "value", "label", "min", "max", "showValue", "color"
    ]

    public static func validate(props: Props) throws {
        try validateFiniteNumber(props.value, prop: "value", component: type)
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
        let minValue = props.min ?? 0
        let maxValue = props.max ?? 1
        if props.value < minValue || props.value > maxValue {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "value",
                reason: "Value must be between min and max"
            )
        }
        try validateOptionalString(props.label, prop: "label", component: type)
    }
}
