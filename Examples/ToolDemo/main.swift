#!/usr/bin/env swift

import Foundation
import AISDK

// MARK: - Demo Tools

struct WeatherTool: Tool {
    let name = "get_weather"
    let description = "Get current weather for a city"
    
    @Parameter(description: "City name")
    var city: String = ""
    
    @Parameter(description: "Temperature unit", validation: ["enum": ["celsius", "fahrenheit"]])
    var unit: String = "celsius"
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        print("🌤️  Getting weather for \(city) in \(unit)...")
        
        // Simulate API delay
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Generate realistic weather data
        let temps = unit == "celsius" ? (15...25) : (59...77)
        let temp = Int.random(in: temps)
        let conditions = ["sunny", "partly cloudy", "cloudy", "light rain"]
        let condition = conditions.randomElement()!
        
        let result = "Weather in \(city): \(temp)°\(unit == "celsius" ? "C" : "F"), \(condition)"
        return (result, nil)
    }
}

struct CalculatorTool: Tool {
    let name = "calculate"
    let description = "Perform basic arithmetic calculations"
    
    @Parameter(description: "First number")
    var a: Double = 0.0
    
    @Parameter(description: "Second number")
    var b: Double = 0.0
    
    @Parameter(description: "Operation", validation: ["enum": ["+", "-", "*", "/"]])
    var operation: String = "+"
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        print("🧮 Calculating \(a) \(operation) \(b)...")
        
        let result: Double
        switch operation {
        case "+": result = a + b
        case "-": result = a - b
        case "*": result = a * b
        case "/":
            guard b != 0 else { 
                throw ToolError.executionFailed("Division by zero")
            }
            result = a / b
        default:
            throw ToolError.executionFailed("Invalid operation: \(operation)")
        }
        
        return ("Result: \(a) \(operation) \(b) = \(result)", nil)
    }
}

struct TimezoneTool: Tool {
    let name = "get_timezone"
    let description = "Get current time in specified timezone"
    let returnToolResponse = true // Return directly to user
    
    @Parameter(description: "Timezone identifier (e.g. America/New_York)")
    var timezone: String = "UTC"
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        print("🕐 Getting time for timezone: \(timezone)...")
        
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timezone) ?? TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
        
        let timeString = formatter.string(from: Date())
        return ("Current time in \(timezone): \(timeString)", nil)
    }
}

struct FileSearchTool: Tool {
    let name = "search_files"
    let description = "Search for files in current directory"
    
    @Parameter(description: "File extension to search for")
    var extension: String = ""
    
    @Parameter(description: "Maximum number of results", validation: ["minimum": 1, "maximum": 20])
    var maxResults: Int = 10
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        print("🔍 Searching for .\(extension) files...")
        
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: currentPath)
            let filteredFiles = contents
                .filter { $0.hasSuffix(".\(extension)") }
                .prefix(maxResults)
            
            if filteredFiles.isEmpty {
                return ("No .\(extension) files found in current directory", nil)
            } else {
                let fileList = filteredFiles.joined(separator: "\n• ")
                return ("Found \(filteredFiles.count) .\(extension) files:\n• \(fileList)", nil)
            }
        } catch {
            throw ToolError.executionFailed("Failed to read directory: \(error.localizedDescription)")
        }
    }
}

// MARK: - Demo Functions

@MainActor
func runToolDemo() async {
    print("🛠️  AISDK Tool Calling Demo")
    print("=" * 50)
    
    // Register tools
    ToolRegistry.registerAll(tools: [
        WeatherTool.self,
        CalculatorTool.self,
        TimezoneTool.self,
        FileSearchTool.self
    ])
    
    // Test scenarios
    await testDirectToolCalls()
    await testAgentWithTools()
    await testToolErrorHandling()
    await testToolSchemaValidation()
    
    print("\n✅ Tool demo completed!")
}

func testDirectToolCalls() async {
    print("\n📋 Testing Direct Tool Calls")
    print("-" * 30)
    
    // Test Weather Tool
    do {
        print("\n1️⃣ Testing Weather Tool:")
        var weatherTool = WeatherTool()
        try weatherTool.setParameters(from: ["city": "San Francisco", "unit": "fahrenheit"])
        let (result, _) = try await weatherTool.execute()
        print("✅ \(result)")
    } catch {
        print("❌ Weather tool failed: \(error)")
    }
    
    // Test Calculator Tool
    do {
        print("\n2️⃣ Testing Calculator Tool:")
        var calcTool = CalculatorTool()
        try calcTool.setParameters(from: ["a": 15.5, "b": 4.2, "operation": "*"])
        let (result, _) = try await calcTool.execute()
        print("✅ \(result)")
    } catch {
        print("❌ Calculator tool failed: \(error)")
    }
    
    // Test Timezone Tool
    do {
        print("\n3️⃣ Testing Timezone Tool:")
        var timeTool = TimezoneTool()
        try timeTool.setParameters(from: ["timezone": "America/New_York"])
        let (result, _) = try await timeTool.execute()
        print("✅ \(result)")
    } catch {
        print("❌ Timezone tool failed: \(error)")
    }
}

func testAgentWithTools() async {
    print("\n🤖 Testing Agent with Tools")
    print("-" * 30)
    
    // Note: This would require actual LLM provider setup
    print("ℹ️  Agent tool integration requires LLM provider configuration")
    print("   Example usage:")
    print("""
    let agent = try Agent(
        model: AgenticModels.gpt4,
        tools: [WeatherTool.self, CalculatorTool.self],
        instructions: "You are a helpful assistant."
    )
    
    let response = try await agent.sendMessage("What's 15 * 4.2?")
    """)
}

func testToolErrorHandling() async {
    print("\n⚠️ Testing Tool Error Handling")
    print("-" * 30)
    
    // Test division by zero
    do {
        print("\n1️⃣ Testing Division by Zero:")
        var calcTool = CalculatorTool()
        try calcTool.setParameters(from: ["a": 10.0, "b": 0.0, "operation": "/"])
        let (result, _) = try await calcTool.execute()
        print("❌ Should have failed: \(result)")
    } catch {
        print("✅ Correctly caught error: \(error)")
    }
    
    // Test invalid parameters
    do {
        print("\n2️⃣ Testing Invalid Parameters:")
        var weatherTool = WeatherTool()
        try weatherTool.setParameters(from: ["city": "NYC", "unit": "invalid"])
        print("❌ Should have failed parameter validation")
    } catch {
        print("✅ Correctly caught parameter error: \(error)")
    }
    
    // Test invalid JSON
    do {
        print("\n3️⃣ Testing Invalid JSON:")
        let invalidJSON = "{ invalid json }"
        let tool = try WeatherTool().validateAndSetParameters(invalidJSON.data(using: .utf8)!)
        print("❌ Should have failed JSON parsing: \(tool)")
    } catch {
        print("✅ Correctly caught JSON error: \(error)")
    }
}

func testToolSchemaValidation() async {
    print("\n📋 Testing Tool Schema Generation")
    print("-" * 30)
    
    let schemas = [
        ("Weather Tool", WeatherTool.jsonSchema()),
        ("Calculator Tool", CalculatorTool.jsonSchema()),
        ("Timezone Tool", TimezoneTool.jsonSchema()),
        ("File Search Tool", FileSearchTool.jsonSchema())
    ]
    
    for (name, schema) in schemas {
        print("\n📄 \(name) Schema:")
        print("   Name: \(schema.function?.name ?? "N/A")")
        print("   Description: \(schema.function?.description ?? "N/A")")
        print("   Parameters: \(schema.function?.parameters.properties.keys.sorted().joined(separator: ", ") ?? "None")")
        
        if let required = schema.function?.parameters.required, !required.isEmpty {
            print("   Required: \(required.joined(separator: ", "))")
        }
    }
}

// MARK: - Interactive Mode

func runInteractiveMode() async {
    print("\n🎮 Interactive Tool Testing Mode")
    print("Available tools: weather, calculate, timezone, search")
    print("Type 'quit' to exit\n")
    
    while true {
        print("Enter tool name and parameters (JSON format):")
        print("Example: weather {\"city\": \"Paris\", \"unit\": \"celsius\"}")
        print("> ", terminator: "")
        
        guard let input = readLine(), !input.isEmpty else { continue }
        
        if input.lowercased() == "quit" {
            break
        }
        
        let components = input.split(separator: " ", maxSplits: 1)
        guard components.count == 2 else {
            print("❌ Invalid format. Use: toolname {json}")
            continue
        }
        
        let toolName = String(components[0])
        let jsonString = String(components[1])
        
        await executeInteractiveTool(name: toolName, jsonString: jsonString)
        print()
    }
}

func executeInteractiveTool(name: String, jsonString: String) async {
    guard let jsonData = jsonString.data(using: .utf8) else {
        print("❌ Invalid JSON format")
        return
    }
    
    do {
        switch name.lowercased() {
        case "weather":
            let tool = try WeatherTool().validateAndSetParameters(jsonData)
            let (result, _) = try await tool.execute()
            print("✅ \(result)")
            
        case "calculate":
            let tool = try CalculatorTool().validateAndSetParameters(jsonData)
            let (result, _) = try await tool.execute()
            print("✅ \(result)")
            
        case "timezone":
            let tool = try TimezoneTool().validateAndSetParameters(jsonData)
            let (result, _) = try await tool.execute()
            print("✅ \(result)")
            
        case "search":
            let tool = try FileSearchTool().validateAndSetParameters(jsonData)
            let (result, _) = try await tool.execute()
            print("✅ \(result)")
            
        default:
            print("❌ Unknown tool: \(name)")
            print("Available: weather, calculate, timezone, search")
        }
    } catch {
        print("❌ Error: \(error)")
    }
}

// MARK: - Main Entry Point

@main
struct ToolDemo {
    static func main() async {
        let args = CommandLine.arguments
        
        if args.contains("--interactive") {
            await runInteractiveMode()
        } else {
            await runToolDemo()
        }
    }
}

// MARK: - String Extension

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
} 