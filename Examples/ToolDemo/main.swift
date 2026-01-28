import Foundation
import AISDK

// MARK: - Demo Tools

struct WeatherTool: AITool {
    let name = "get_weather"
    let description = "Get current weather for a city"
    
    enum TemperatureUnit: String, Codable, CaseIterable {
        case celsius
        case fahrenheit
    }

    @AIParameter(description: "City name")
    var city: String = ""
    
    @AIParameter(description: "Temperature unit")
    var unit: TemperatureUnit = .celsius
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        print("🌤️  Getting weather for \(city) in \(unit.rawValue)...")
        
        // Simulate API delay
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Generate realistic weather data
        let temps = unit == .celsius ? (15...25) : (59...77)
        let temp = Int.random(in: temps)
        let conditions = ["sunny", "partly cloudy", "cloudy", "light rain"]
        let condition = conditions.randomElement()!
        
        let result = "Weather in \(city): \(temp)°\(unit == .celsius ? "C" : "F"), \(condition)"
        return AIToolResult(content: result)
    }
}

struct CalculatorTool: AITool {
    let name = "calculate"
    let description = "Perform basic arithmetic calculations"
    
    @AIParameter(description: "First number")
    var a: Double = 0.0
    
    @AIParameter(description: "Second number")
    var b: Double = 0.0
    
    enum Operation: String, Codable, CaseIterable {
        case plus = "+"
        case minus = "-"
        case multiply = "*"
        case divide = "/"
    }

    @AIParameter(description: "Operation")
    var operation: Operation = .plus
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        print("🧮 Calculating \(a) \(operation.rawValue) \(b)...")
        
        let result: Double
        switch operation {
        case .plus: result = a + b
        case .minus: result = a - b
        case .multiply: result = a * b
        case .divide:
            guard b != 0 else { 
                throw ToolError.executionFailed("Division by zero")
            }
            result = a / b
        }
        
        return AIToolResult(content: "Result: \(a) \(operation.rawValue) \(b) = \(result)")
    }
}

struct TimezoneTool: AITool {
    let name = "get_timezone"
    let description = "Get current time in specified timezone"
    let returnToolResponse = true // Return directly to user
    
    @AIParameter(description: "Timezone identifier (e.g. America/New_York)")
    var timezone: String = "UTC"
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        print("🕐 Getting time for timezone: \(timezone)...")
        
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timezone) ?? TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
        
        let timeString = formatter.string(from: Date())
        return AIToolResult(content: "Current time in \(timezone): \(timeString)")
    }
}

struct FileSearchTool: AITool {
    let name = "search_files"
    let description = "Search for files in current directory"
    
    @AIParameter(description: "File extension to search for")
    var fileExtension: String = ""
    
    @AIParameter(description: "Maximum number of results", .range(1...20))
    var maxResults: Int = 10
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        print("🔍 Searching for .\(fileExtension) files...")
        
        let fileManager = FileManager.default
        let currentPath = fileManager.currentDirectoryPath
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: currentPath)
            let filteredFiles = contents
                .filter { $0.hasSuffix(".\(fileExtension)") }
                .prefix(maxResults)
            
            if filteredFiles.isEmpty {
                return AIToolResult(content: "No .\(fileExtension) files found in current directory")
            } else {
                let fileList = filteredFiles.joined(separator: "\n• ")
                return AIToolResult(content: "Found \(filteredFiles.count) .\(fileExtension) files:\n• \(fileList)")
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
    AIToolRegistry.registerAll(tools: [
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
        let result = try await weatherTool.execute()
        print("✅ \(result.content)")
    } catch {
        print("❌ Weather tool failed: \(error)")
    }
    
    // Test Calculator Tool
    do {
        print("\n2️⃣ Testing Calculator Tool:")
        var calcTool = CalculatorTool()
        try calcTool.setParameters(from: ["a": 15.5, "b": 4.2, "operation": "*"])
        let result = try await calcTool.execute()
        print("✅ \(result.content)")
    } catch {
        print("❌ Calculator tool failed: \(error)")
    }
    
    // Test Timezone Tool
    do {
        print("\n3️⃣ Testing Timezone Tool:")
        var timeTool = TimezoneTool()
        try timeTool.setParameters(from: ["timezone": "America/New_York"])
        let result = try await timeTool.execute()
        print("✅ \(result.content)")
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
        let result = try await calcTool.execute()
        print("❌ Should have failed: \(result.content)")
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
        var tool = WeatherTool()
        let _ = try tool.validateAndSetParameters(invalidJSON.data(using: .utf8)!)
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
            var tool = WeatherTool()
            let _ = try tool.validateAndSetParameters(jsonData)
            let result = try await tool.execute()
            print("✅ \(result.content)")
            
        case "calculate":
            var tool = CalculatorTool()
            let _ = try tool.validateAndSetParameters(jsonData)
            let result = try await tool.execute()
            print("✅ \(result.content)")
            
        case "timezone":
            var tool = TimezoneTool()
            let _ = try tool.validateAndSetParameters(jsonData)
            let result = try await tool.execute()
            print("✅ \(result.content)")
            
        case "search":
            var tool = FileSearchTool()
            let _ = try tool.validateAndSetParameters(jsonData)
            let result = try await tool.execute()
            print("✅ \(result.content)")
            
        default:
            print("❌ Unknown tool: \(name)")
            print("Available: weather, calculate, timezone, search")
        }
    } catch {
        print("❌ Error: \(error)")
    }
}

// MARK: - Main Entry Point

// MARK: - Anthropic Tools Demo

/// Simple weather tool for Anthropic demo - clean and simple
struct AnthropicWeatherTool: AITool {
    let name = "get_weather"
    let description = "Get current weather for a location"
    
    enum TemperatureUnit: String, Codable, CaseIterable {
        case celsius
        case fahrenheit
    }

    @AIParameter(description: "City and state, e.g. San Francisco, CA")
    var location: String = ""
    
    @AIParameter(description: "Temperature unit")
    var unit: TemperatureUnit = .celsius
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        let result = "Weather in \(location): 72°\(unit == .celsius ? "C" : "F"), sunny"
        return AIToolResult(content: result)
    }
}

func runAnthropicToolsDemo() async {
    print("\n🔧 Anthropic Clean Tools Demo")
    print("============================")
    
    // Example 1: Clean tool creation
    print("\n📝 Example 1: Clean Tool Creation")
    print("----------------------------------")
    
    // ✅ NEW: Clean, type-safe tool creation
    let weatherTool = AnthropicTool(from: AnthropicWeatherTool.self)
    
    print("✅ Created Anthropic tool:")
    print("  - \(weatherTool.name): \(weatherTool.description)")
    print("  - Parameters: \(weatherTool.inputSchema.properties.count)")
    print("  - Required: \(weatherTool.inputSchema.required)")
    
    // Example 2: AITool execution flow
    print("\n🚀 Example 2: AITool Execution Flow")
    print("----------------------------------")
    
    // Simulate Claude's tool use response
    let mockToolUseBlock = createMockToolUseBlock()
    
    do {
        // ✅ NEW: Clean tool execution
        var tool = AnthropicWeatherTool()
        try tool.setParameters(from: mockToolUseBlock.typedInput)
        let result = try await tool.execute()
        
        print("✅ Tool executed successfully")
        print("   Result: \(result.content)")
        print("   Tool use ID: \(mockToolUseBlock.id)")
        print("   Tool name: \(mockToolUseBlock.name)")
    } catch {
        // ✅ NEW: Enhanced error handling
        print("❌ Tool execution failed: \(error)")
    }
    
    // Example 3: Server-side tools
    print("\n🌐 Example 3: Server-Side Tools")
    print("-------------------------------")
    
    // ✅ NEW: Server-side tool definitions (documentation only)
    let webSearchTool = AnthropicTool(
        name: "web_search_20250305",
        description: "Search the web for current information",
        inputSchema: AnthropicToolSchema(
            properties: [
                "query": AnthropicPropertySchema(
                    type: "string",
                    description: "The search query"
                )
            ],
            required: ["query"]
        )
    )
    
    print("✅ Web search tool created:")
    print("   Name: \(webSearchTool.name)")
    print("   Note: This executes on Anthropic's servers")
    
    // Example 4: Beta features
    print("\n🧪 Example 4: Beta Features")
    print("---------------------------")
    
    // ✅ NEW: Request with beta features  
    print("✅ Creating request with beta features")
    print("   Model: claude-sonnet-4-5-20250929")
    print("   Tools: Weather tool")
    
    // ✅ NEW: Beta features configuration
    print("✅ Beta features available:")
    print("   Token-efficient tools: Saves 14% tokens on average")
    print("   Parallel tool use: Tools can run simultaneously")  
    print("   Chain of thought: Better reasoning with <thinking> tags")
    
    // ✅ NEW: Enhanced tool choice options
    print("✅ Tool choice options:")
    print("   .auto - Let Claude decide whether to use tools")
    print("   .any - Force Claude to use any available tool")
    print("   .none - Disable tools completely for this request")
    print("   .tool(name: \"specific_tool\") - Force specific tool")
    
    print("✅ Request would be configured with beta features when used with AnthropicProvider")
    
    // ✅ NEW: Chain of thought prompts (example constants)
    print("\n🧠 Chain of Thought Prompts:")
    print("   Basic: Think step by step before using tools...")
    print("   Multi-tool: Consider which tools to use and in what order...")
    print("   Error handling: If a tool fails, analyze and determine next steps...")
    
    // Example 5: JSON Schema output
    print("\n📋 Example 5: JSON Schema Output")
    print("---------------------------------")
    
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(weatherTool)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "Failed to encode"
        
        print("✅ Weather tool JSON schema:")
        print(jsonString)
    } catch {
        print("❌ Failed to encode tool: \(error)")
    }
}

// Helper function to create a mock tool use block
func createMockToolUseBlock() -> AnthropicToolUseBlock {
    // Create a mock tool use block (this would be parsed from response)
    let jsonData = """
    {
        "id": "toolu_01234567890",
        "name": "get_weather",
        "input": {
            "location": "San Francisco, CA",
            "unit": "celsius"
        }
    }
    """.data(using: .utf8)!
    
    return try! JSONDecoder().decode(AnthropicToolUseBlock.self, from: jsonData)
}

@main
struct ToolDemo {
    static func main() async {
        let args = CommandLine.arguments
        
        if args.contains("--interactive") {
            await runInteractiveMode()
        } else if args.contains("--anthropic") {
            await runAnthropicToolsDemo()
        } else {
            await runToolDemo()
            
            // Also run Anthropic demo
            await runAnthropicToolsDemo()
        }
    }
}

// MARK: - String Extension

extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
} 
