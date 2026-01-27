import Foundation
// WeatherTool.swift

import SwiftUI

/// Example typed data after we fetch weather
struct WeatherRenderArgs: Codable {
    let city: String
    let temperature: Double
    let condition: String
}

struct WeatherToolUI: RenderableTool {
    let name = "get_weather"
    let description = "Get the current weather in a given city"
    let returnToolResponse = false
    
    init() {}
    
    @AIParameter(description: "City name")
    var city: String = ""
    
    // 1) Execute tool
    func execute() async throws -> AIToolResult {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Fake data
        let temperature = 85.0
        let condition = "Sunny"
        
        // The textual response
        let textResponse = "Weather in \(city): \(temperature)°F, \(condition)"
        
        // Build a typed object
        let args = WeatherRenderArgs(
            city: city,
            temperature: temperature,
            condition: condition
        )
        
        // Encode it to JSON
        let jsonData = try JSONEncoder().encode(args)
        
        // Create the RenderMetadata
        let metadata = RenderMetadata(toolName: name, jsonData: jsonData)
        
        return AIToolResult(content: textResponse, metadata: metadata)
    }
    
    // 2) Render from metadata
    func render(from data: Data) -> AnyView {
        guard let args = try? JSONDecoder().decode(WeatherRenderArgs.self, from: data) else {
            return AnyView(
                Text("Unable to render Weather UI.")
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            )
        }
        
        return AnyView(
            VStack(spacing: 16) {
                // Header with city name
                Text(args.city)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                
                // Temperature display
                HStack(alignment: .top, spacing: 0) {
                    Text("\(Int(args.temperature))")
                        .font(.system(size: 64, weight: .thin))
                    Text("°F")
                        .font(.system(size: 24, weight: .medium))
                        .padding(.top, 8)
                }
                
                // Weather condition
                Text(args.condition)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.secondary)
                
                // Weather icon (you might want to add SF Symbols based on condition)
                Image(systemName: weatherIcon(for: args.condition))
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        )
    }
    
    // Helper function to map weather conditions to SF Symbols
    private func weatherIcon(for condition: String) -> String {
        switch condition.lowercased() {
        case let c where c.contains("sun"): return "sun.max.fill"
        case let c where c.contains("cloud"): return "cloud.fill"
        case let c where c.contains("rain"): return "cloud.rain.fill"
        case let c where c.contains("snow"): return "cloud.snow.fill"
        case let c where c.contains("wind"): return "wind"
        case let c where c.contains("storm"): return "cloud.bolt.rain.fill"
        default: return "thermometer.medium"
        }
    }
}

// MARK: - Weather Tool
struct WeatherTool: AITool {
    let name = "get_weather"
    let description = "Get the current weather in a given city"
    
    init() {}
    
    @AIParameter(description: "City name")
    var city: String = ""
    
    func execute() async throws -> AIToolResult  {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        return AIToolResult(content: "Weather in \(city): 72°F, Sunny")
    }
}

// MARK: - Calculator Tool
struct CalculatorTool: AITool {
    let name = "calculate"
    let description = "Perform basic arithmetic calculations"
    
    init() {}
    
    @AIParameter(description: "First number", .range(-1000...1000))
    var a: Double = 0
    
    @AIParameter(description: "Second number", .range(-1000...1000))
    var b: Double = 0
    
    enum Operation: String, Codable, CaseIterable {
        case plus = "+"
        case minus = "-"
        case multiply = "*"
        case divide = "/"
    }

    @AIParameter(description: "Operation to perform")
    var operation: Operation = .plus
    
    func execute() async throws -> AIToolResult {
        let result: Double
        switch operation {
        case .plus: result = a + b
        case .minus: result = a - b
        case .multiply: result = a * b
        case .divide:
            guard b != 0 else { throw AgentError.toolExecutionFailed("Division by zero") }
            result = a / b
        }
        return AIToolResult(content: String(format: "%.2f %@ %.2f = %.2f", a, operation.rawValue, b, result))
    }
}

struct TimezoneTool: AITool {
    let name = "convert_timezone"
    let description = "Convert time between different timezones"
    let returnToolResponse = true  // Direct response without AI interpretation
    
    init() {}
    
    @AIParameter(description: "Source timezone (e.g. America/New_York)")
    var fromTimezone: String = ""
    
    @AIParameter(description: "Target timezone (e.g. Asia/Tokyo)")
    var toTimezone: String = ""
    
    @AIParameter(description: "Time to convert (format: HH:mm)")
    var time: String = ""
    
    func execute() async throws -> AIToolResult {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        return AIToolResult(content: "Tool response: \(time) in \(fromTimezone) to \(toTimezone)")
    }
}



struct ResearchTool: AITool {
    let name = "search_research"
    let description = "Search for medical research papers on a topic"
    
    init() {}
    
    @AIParameter(description: "Medical topic to search for")
    var topic: String = ""
    
    @AIParameter(description: "Maximum number of results", .range(1...5))
    var maxResults: Int = 3
    
    func execute() async throws -> AIToolResult {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Simulate finding research papers

        
        let evidence = MedicalEvidence(
            sources: [],
            evidenceLevel: "B",
            confidenceScore: 0.85,
            lastUpdated: Date()
        )
        
        let content = """
        Found 
        """
        
        return AIToolResult(content: content, metadata: evidence)
    }
} 
