import Foundation
import AISDK
#if canImport(SwiftUI)
import SwiftUI
#endif

public struct CalculatorTool: Tool {
    public enum Operation: String, Codable, CaseIterable, Sendable {
        case add = "add"
        case subtract = "subtract"
        case multiply = "multiply"
        case divide = "divide"

        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
            switch raw {
            case "add", "+", "plus":
                self = .add
            case "subtract", "-", "minus":
                self = .subtract
            case "multiply", "*", "times", "x":
                self = .multiply
            case "divide", "/":
                self = .divide
            default:
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unknown operation: \(raw). Use: add, subtract, multiply, divide, +, -, *, /"
                )
            }
        }
    }

    public var name: String { "calculator" }
    public var description: String { "Perform arithmetic operations on two numbers. Operations: add (+), subtract (-), multiply (*), divide (/)." }

    @Parameter(description: "First number")
    public var a: Double = 0

    @Parameter(description: "Second number")
    public var b: Double = 0

    @Parameter(description: "Operation: add, subtract, multiply, or divide")
    public var operation: Operation = .add

    public init() {}

    public func execute() async throws -> ToolResult {
        let value: Double
        switch operation {
        case .add:
            value = a + b
        case .subtract:
            value = a - b
        case .multiply:
            value = a * b
        case .divide:
            if b == 0 {
                return ToolResult(content: "Error: cannot divide by zero.")
            }
            value = a / b
        }
        return ToolResult(content: String(format: "%.2f", value))
    }
}

public struct WeatherTool: Tool {
    public var name: String { "weather_lookup" }
    public var description: String { "Return demo weather information for a city." }

    @Parameter(description: "City name")
    public var city: String = ""

    public init() {}

    public func execute() async throws -> ToolResult {
        let clean = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let temperature = max(8, min(31, 14 + clean.count))
        let condition: String = clean.count.isMultiple(of: 2) ? "Cloudy" : "Sunny"
        let payload = "Weather in \(clean.isEmpty ? "Unknown" : clean): \(temperature)C, \(condition)"
        return ToolResult(content: payload)
    }
}

// MARK: - UITool Conformance

#if canImport(SwiftUI)
extension WeatherTool: UITool {
    public var body: some View {
        let clean = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let temp = max(8, min(31, 14 + clean.count))
        let cond = clean.count.isMultiple(of: 2) ? "Cloudy" : "Sunny"
        HStack(spacing: 12) {
            Image(systemName: cond == "Sunny" ? "sun.max.fill" : "cloud.fill")
                .font(.title)
                .foregroundStyle(cond == "Sunny" ? .yellow : .gray)
            VStack(alignment: .leading, spacing: 4) {
                Text(clean.isEmpty ? "Unknown" : clean)
                    .font(.headline)
                Text("\(temp)\u{00B0}C, \(cond)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
#endif
