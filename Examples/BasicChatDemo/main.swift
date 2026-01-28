//
//  main.swift
//  BasicChatDemo
//
//  Simple CLI demo for testing AISDK chat functionality
//

import Foundation
import AISDK

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif


struct BasicChatDemo {
    
    static func main() async {
        print("🤖 AISDK Basic Chat Demo")
        print("=" * 40)
        
        // Try to load .env file
        loadEnvironmentVariables()
        
        // Check for environment variables
        guard let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !openAIKey.isEmpty else {
            print("❌ Please set OPENAI_API_KEY environment variable")
            print("   Option 1: Create a .env file in the root directory with:")
            print("   OPENAI_API_KEY=your_key_here")
            print("   ")
            print("   Option 2: Export environment variable:")
            print("   export OPENAI_API_KEY=your_key_here")
            print("   ")
            print("   Option 3: Run with inline environment variable:")
            print("   OPENAI_API_KEY=your_key_here swift run BasicChatDemo")
            return
        }
        
        // Initialize providers
        let openAIProvider = OpenAIProvider(apiKey: openAIKey)
        
        // Check for Anthropic key (optional)
        let anthropicProvider: AnthropicProvider?
        if let anthropicKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !anthropicKey.isEmpty {
            anthropicProvider = AnthropicProvider(apiKey: anthropicKey)
        } else {
            anthropicProvider = nil
            print("ℹ️  Anthropic API key not found - only OpenAI tests will run")
        }
        
        print("\n🧪 Starting Tests...")
        
        // Test 1: Basic Chat Completion
        await testBasicChat(provider: openAIProvider, providerName: "OpenAI")
        
        if let anthropic = anthropicProvider {
            await testBasicChat(provider: anthropic, providerName: "Anthropic")
        }
        
        // Test 2: Streaming Chat
        await testStreamingChat(provider: openAIProvider, providerName: "OpenAI")
        
        // Test 3: Multimodal Tests (Images)
        await testImageURL(provider: openAIProvider, providerName: "OpenAI")
        await testImageBase64(provider: openAIProvider, providerName: "OpenAI")
        await testMultipleImages(provider: openAIProvider, providerName: "OpenAI")
        
        // Test 4: JSON & Structured Output Tests
        await testJSONMode(provider: openAIProvider, providerName: "OpenAI")
        await testStructuredOutput(provider: openAIProvider, providerName: "OpenAI")
        await testGenerateObjectMethod(provider: openAIProvider, providerName: "OpenAI")
        
        // Test Anthropic generateObject method
        if let anthropicProvider = anthropicProvider {
            await testAnthropicGenerateObject(provider: anthropicProvider)
        }
        
        // Test 5: AITool Calling Tests
        await testDirectToolCalls()
        await testToolWithLLM(provider: openAIProvider, providerName: "OpenAI")
        await testAgentWithTools(provider: openAIProvider)
        
        // Test 6: Interactive Chat
        await interactiveChat(provider: openAIProvider)
        
        print("\n✅ Demo completed!")
        
        do {
            print("🚀 Testing Agent with OpenAI Provider...")
            
            // Create OpenAI provider (uses smart default: gpt-4o)
            let openai = OpenAIProvider()
            
            // Create agent with the provider
            let agent = Agent(
                llm: openai,
                instructions: "You are a helpful assistant."
            )
            
            print("✅ Agent created successfully!")
            
            // Test a conversation
            let response = try await agent.send("Hello! What's 2+2?")
            print("🤖 Response: \(response.displayContent)")
            
            print("\n✅ Demo completed!")
            
        } catch {
            print("❌ Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Environment Loading

func loadEnvironmentVariables() {
    // Try to load from .env file
    let envPath = ".env"
    if let envContent = try? String(contentsOfFile: envPath) {
        for line in envContent.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                let parts = trimmedLine.components(separatedBy: "=")
                if parts.count >= 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
                    setenv(key, value, 0) // Don't overwrite existing env vars
                }
            }
        }
        print("📄 Loaded environment variables from .env file")
    }
}

// MARK: - Test Functions

func testBasicChat(provider: LLM, providerName: String) async {
    print("\n📝 Testing Basic Chat with \(providerName)...")
    
    do {
        let request = ChatCompletionRequest(
            model: providerName == "OpenAI" ? "gpt-4o-mini" : "claude-3-haiku-20240307",
            messages: [
                .system(content: .text("You are a helpful assistant. Keep responses brief.")),
                .user(content: .text("What is the capital of France? Answer in one sentence."))
            ],
            maxTokens: 50
        )
        
        let response = try await provider.sendChatCompletion(request: request)
        
        if let content = response.choices.first?.message.content {
            print("✅ \(providerName) Response: \(content)")
            print("📊 Usage: \(response.usage?.totalTokens ?? 0) tokens")
        } else {
            print("❌ No content in response")
        }
        
    } catch {
        print("❌ \(providerName) Error: \(error)")
    }
}

func testStreamingChat(provider: LLM, providerName: String) async {
    print("\n🔄 Testing Streaming Chat with \(providerName)...")
    
    do {
        let request = ChatCompletionRequest(
            model: providerName == "OpenAI" ? "gpt-4o-mini" : "claude-3-haiku-20240307",
            messages: [
                .user(content: .text("Count from 1 to 10, one number per response token."))
            ],
            maxTokens: 50,
            stream: true
        )
        
        print("📡 Streaming response: ", terminator: "")
        
        for try await chunk in try await provider.sendChatCompletionStream(request: request) {
            if let content = chunk.choices.first?.delta.content {
                print(content, terminator: "")
                fflush(stdout)
            }
        }
        
        print("\n✅ Streaming completed")
        
    } catch {
        print("❌ \(providerName) Streaming Error: \(error)")
    }
}

func interactiveChat(provider: LLM) async {
    print("\n💬 Interactive Chat Mode (type 'quit' to exit)")
    print("   Using OpenAI provider")
    
    var conversationHistory: [Message] = [
        .system(content: .text("You are a helpful assistant."))
    ]
    
    while true {
        print("\n👤 You: ", terminator: "")
        
        guard let input = readLine(), !input.isEmpty else {
            continue
        }
        
        if input.lowercased() == "quit" {
            break
        }
        
        // Add user message to conversation
        conversationHistory.append(.user(content: .text(input)))
        
        do {
            print("🤖 Assistant: ", terminator: "")
            
            // Use streaming for interactive feel
            let streamRequest = ChatCompletionRequest(
                model: "gpt-4o-mini",
                messages: conversationHistory,
                maxTokens: 150,
                stream: true
            )
            
            var assistantResponse = ""
            
            for try await chunk in try await provider.sendChatCompletionStream(request: streamRequest) {
                if let content = chunk.choices.first?.delta.content {
                    print(content, terminator: "")
                    assistantResponse += content
                    fflush(stdout)
                }
            }
            
            print() // New line after response
            
            // Add assistant response to conversation history
            conversationHistory.append(.assistant(content: .text(assistantResponse)))
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    print("👋 Goodbye!")
}

// MARK: - Multimodal Test Functions (Phase 1)

func testImageURL(provider: LLM, providerName: String) async {
    print("\n🖼️ Testing Image URL + Text with \(providerName)...")
    
    do {
        let imageURL = "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"
        
        let request = ChatCompletionRequest(
            model: providerName == "OpenAI" ? "gpt-4o" : "claude-sonnet-4-5-20250929",
            messages: [
                .user(content: .parts([
                    .text("What do you see in this image? Describe it in detail."),
                    .imageURL(.url(URL(string: imageURL)!))
                ]))
            ],
            maxTokens: 200
        )
        
        let response = try await provider.sendChatCompletion(request: request)
        
        if let content = response.choices.first?.message.content {
            print("✅ \(providerName) Image Analysis:")
            print("   \(content)")
            print("📊 Usage: \(response.usage?.totalTokens ?? 0) tokens")
        } else {
            print("❌ No content in response")
        }
        
    } catch {
        print("❌ \(providerName) Image URL Error: \(error)")
    }
}

func testImageBase64(provider: LLM, providerName: String) async {
    print("\n📸 Testing Base64 Image + Text with \(providerName)...")
    
    do {
        // Create a simple test image programmatically
        guard let testImageData = createTestImage() else {
            print("❌ Failed to create test image")
            return
        }
        
        let request = ChatCompletionRequest(
            model: providerName == "OpenAI" ? "gpt-4o" : "claude-sonnet-4-5-20250929",
            messages: [
                .user(content: .parts([
                    .text("This is a programmatically generated test image. What colors and shapes do you see?"),
                    .imageURL(.base64(testImageData))
                ]))
            ],
            maxTokens: 150
        )
        
        let response = try await provider.sendChatCompletion(request: request)
        
        if let content = response.choices.first?.message.content {
            print("✅ \(providerName) Base64 Image Analysis:")
            print("   \(content)")
            print("📊 Usage: \(response.usage?.totalTokens ?? 0) tokens")
        } else {
            print("❌ No content in response")
        }
        
    } catch {
        print("❌ \(providerName) Base64 Image Error: \(error)")
    }
}

func testMultipleImages(provider: LLM, providerName: String) async {
    print("\n🖼️🖼️ Testing Multiple Images with \(providerName)...")
    
    do {
        let imageURL1 = "https://www.wiggles.in/cdn/shop/articles/shutterstock_245621623.jpg?v=1706863987"
        let imageURL2 = "https://media1.popsugar-assets.com/files/thumbor/gFMaLiceRbGWkZUWwl2Xhkft6eU=/0x159:2003x2162/fit-in/2011x2514/filters:format_auto():quality(85):upscale()/2019/08/07/875/n/24155406/9ffb00255d4b2e079b0b23.01360060_.jpg"
        
        let request = ChatCompletionRequest(
            model: providerName == "OpenAI" ? "gpt-4o" : "claude-sonnet-4-5-20250929",
            messages: [
                .user(content: .parts([
                    .text("Compare these two images. What are the similarities and differences?"),
                    .imageURL(.url(URL(string: imageURL1)!)),
                    .imageURL(.url(URL(string: imageURL2)!))
                ]))
            ],
            maxTokens: 250
        )
        
        let response = try await provider.sendChatCompletion(request: request)
        
        if let content = response.choices.first?.message.content {
            print("✅ \(providerName) Multiple Images Analysis:")
            print("   \(content)")
            print("📊 Usage: \(response.usage?.totalTokens ?? 0) tokens")
        } else {
            print("❌ No content in response")
        }
        
    } catch {
        print("❌ \(providerName) Multiple Images Error: \(error)")
    }
}

// MARK: - JSON & Structured Output Test Functions (Phase 2)

func testJSONMode(provider: LLM, providerName: String) async {
    print("\n📝 Testing JSON Mode with \(providerName)...")
    
    do {
        let request = ChatCompletionRequest(
            model: providerName == "OpenAI" ? "gpt-4o" : "claude-sonnet-4-5-20250929",
            messages: [
                .system(content: .text("You are a helpful assistant that returns valid JSON.")),
                .user(content: .text("Create a list of 3 programming languages with their main characteristics. Return as JSON with 'languages' array."))
            ],
            maxTokens: 300,
            responseFormat: .jsonObject
        )
        
        let response = try await provider.sendChatCompletion(request: request)
        
        if let content = response.choices.first?.message.content {
            print("✅ \(providerName) JSON Response:")
            
            // Try to parse and format the JSON
            if let jsonData = content.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                print("   \(prettyString)")
            } else {
                print("   \(content)")
            }
            
            print("📊 Usage: \(response.usage?.totalTokens ?? 0) tokens")
        } else {
            print("❌ No content in response")
        }
        
    } catch {
        print("❌ \(providerName) JSON Mode Error: \(error)")
    }
}

func testStructuredOutput(provider: LLM, providerName: String) async {
    print("\n🏗️ Testing Structured Output with \(providerName)...")
    
    do {
        // Define a simple structured model
        struct Book: Codable {
            let title: String
            let author: String
            let year: Int
            let genre: String
        }
        
        let request = ChatCompletionRequest(
            model: providerName == "OpenAI" ? "gpt-4o" : "claude-sonnet-4-5-20250929",
            messages: [
                .system(content: .text("Return a JSON object with the exact structure: {\"title\": string, \"author\": string, \"year\": number, \"genre\": string}")),
                .user(content: .text("Recommend a classic science fiction book."))
            ],
            maxTokens: 150,
            responseFormat: .jsonObject
        )
        
        let response = try await provider.sendChatCompletion(request: request)
        
        if let content = response.choices.first?.message.content {
            print("✅ \(providerName) Structured Response:")
            
            // Try to parse into our Book struct
            if let jsonData = content.data(using: .utf8) {
                do {
                    let book = try JSONDecoder().decode(Book.self, from: jsonData)
                    print("   📚 Title: \(book.title)")
                    print("   ✍️  Author: \(book.author)")
                    print("   📅 Year: \(book.year)")
                    print("   🏷️  Genre: \(book.genre)")
                } catch {
                    print("   ⚠️  JSON parsing failed: \(error)")
                    print("   Raw: \(content)")
                }
            }
            
            print("📊 Usage: \(response.usage?.totalTokens ?? 0) tokens")
        } else {
            print("❌ No content in response")
        }
        
    } catch {
        print("❌ \(providerName) Structured Output Error: \(error)")
    }
}

func testGenerateObjectMethod(provider: LLM, providerName: String) async {
    print("\n🏗️ Testing Generate Object Method with \(providerName)...")
    
    do {
        // Define schema models using JSONSchemaModel and @Field (like the fruit example)
        struct Product: JSONSchemaModel {
            @Field(
                description: "The name of the product",
                validation: [
                    "type": .string("string"),
                    "minLength": .integer(1),
                    "maxLength": .integer(100)
                ]
            )
            var name: String = ""
            
            @Field(
                description: "The price of the product in USD",
                validation: [
                    "type": .string("number"),
                    "minimum": .number(0.01),
                    "maximum": .number(10000.0)
                ]
            )
            var price: Double = 0.0
            
            @Field(
                description: "The category of the product",
                validation: [
                    "type": .string("string"),
                    "enum": .array([.string("Electronics"), .string("Clothing"), .string("Books"), .string("Home")])
                ]
            )
            var category: String = ""
            
            @Field(
                description: "Whether the product is in stock",
                validation: [
                    "type": .string("boolean")
                ]
            )
            var inStock: Bool = false
            
            init() {}
        }
        
        struct UserPreferences: JSONSchemaModel {
            @Field(
                description: "The UI theme preference",
                validation: [
                    "type": .string("string"),
                    "enum": .array([.string("light"), .string("dark"), .string("auto")])
                ]
            )
            var theme: String = ""
            
            @Field(
                description: "Whether notifications are enabled",
                validation: [
                    "type": .string("boolean")
                ]
            )
            var notifications: Bool = false
            
            init() {}
        }
        
        struct User: JSONSchemaModel {
            @Field(
                description: "The user's unique identifier",
                validation: [
                    "type": .string("integer"),
                    "minimum": .integer(1),
                    "maximum": .integer(999999)
                ]
            )
            var id: Int = 0
            
            @Field(
                description: "The user's full name",
                validation: [
                    "type": .string("string"),
                    "minLength": .integer(1),
                    "maxLength": .integer(50)
                ]
            )
            var name: String = ""
            
            @Field(
                description: "The user's email address",
                validation: [
                    "type": .string("string"),
                    "format": .string("email")
                ]
            )
            var email: String = ""
            
            @Field(
                description: "The user's preferences object",
                validation: [
                    "type": .string("object")
                ]
            )
            var preferences: UserPreferences = UserPreferences()
            
            init() {}
        }
        
        // Test 1: Product generation using JSON Schema
        let productRequest = ChatCompletionRequest(
            model: providerName == "OpenAI" ? "gpt-4o" : "claude-sonnet-4-5-20250929",
            messages: [
                .system(content: .text("Return valid JSON following the schema")),
                .user(content: .text("Generate a laptop product with realistic data"))
            ],
            responseFormat: .jsonSchema(
                name: "product",
                description: "A product with name, price, category, and stock status",
                schemaBuilder: Product.schema()
                    .title("Product")
                    .description("A product object with all required fields"),
                strict: true
            )
        )
        
        // Use the generateObject method with JSON Schema
        let product: Product = try await provider.generateObject(request: productRequest)
        
        print("✅ \(providerName) Product Object Generated:")
        print("   📦 Name: \(product.name)")
        print("   💰 Price: $\(product.price)")
        print("   🏷️  Category: \(product.category)")
        print("   📊 In Stock: \(product.inStock)")
        
        // Test 2: User generation using JSON Schema with nested object
        let userRequest = ChatCompletionRequest(
            model: providerName == "OpenAI" ? "gpt-4o" : "claude-sonnet-4-5-20250929",
            messages: [
                .system(content: .text("Return valid JSON following the schema")),
                .user(content: .text("Generate a user profile for a software developer"))
            ],
            responseFormat: .jsonSchema(
                name: "user",
                description: "A user profile with preferences",
                schemaBuilder: User.schema()
                    .title("User Profile")
                    .description("A complete user profile with nested preferences"),
                strict: true
            )
        )
        
        // Use the generateObject method with complex nested schema
        let user: User = try await provider.generateObject(request: userRequest)
        
        print("✅ \(providerName) User Object Generated:")
        print("   🆔 ID: \(user.id)")
        print("   👤 Name: \(user.name)")
        print("   📧 Email: \(user.email)")
        print("   🎨 Theme: \(user.preferences.theme)")
        print("   🔔 Notifications: \(user.preferences.notifications)")
        
    } catch {
        print("❌ \(providerName) Generate Object Error: \(error)")
    }
}

// MARK: - Tool Testing Functions (Phase 3)

// Demo tools for testing
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
        // Simulate API delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Generate realistic weather data
        let temps = unit == .celsius ? (15...25) : (59...77)
        let temp = Int.random(in: temps)
        let conditions = ["sunny", "partly cloudy", "cloudy", "light rain"]
        let condition = conditions.randomElement()!
        
        return AIToolResult(content: "Weather in \(city): \(temp)°\(unit == .celsius ? "C" : "F"), \(condition)")
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
        let result: Double
        switch operation {
        case .plus: result = a + b
        case .minus: result = a - b
        case .multiply: result = a * b
        case .divide:
            guard b != 0 else { throw ToolError.executionFailed("Division by zero") }
            result = a / b
        }
        return AIToolResult(content: "Result: \(a) \(operation.rawValue) \(b) = \(result)")
    }
}

func testDirectToolCalls() async {
    print("\n🔧 Testing Direct Tool Calls...")
    
    // Register tools
    AIToolRegistry.registerAll(tools: [WeatherTool.self, CalculatorTool.self])
    
    // Test Weather Tool
    do {
        print("   🌤️  Testing Weather Tool:")
        var weatherTool = WeatherTool()
        try weatherTool.setParameters(from: ["city": "San Francisco", "unit": "fahrenheit"])
        let result = try await weatherTool.execute()
        print("   ✅ \(result.content)")
    } catch {
        print("   ❌ Weather tool failed: \(error)")
    }
    
    // Test Calculator Tool
    do {
        print("   🧮 Testing Calculator Tool:")
        var calcTool = CalculatorTool()
        try calcTool.setParameters(from: ["a": 15.5, "b": 4.2, "operation": "*"])
        let result = try await calcTool.execute()
        print("   ✅ \(result.content)")
    } catch {
        print("   ❌ Calculator tool failed: \(error)")
    }
    
    // Test Schema Generation
    print("   📋 Testing Schema Generation:")
    let weatherSchema = WeatherTool.jsonSchema()
    print("   ✅ Weather tool schema generated: \(weatherSchema.function?.name ?? "N/A")")
    
    let calcSchema = CalculatorTool.jsonSchema()
    print("   ✅ Calculator tool schema generated: \(calcSchema.function?.name ?? "N/A")")
}

func testToolWithLLM(provider: LLM, providerName: String) async {
    print("\n⚙️ Testing Tool Calling with \(providerName)...")
    
    do {
        let tools = [WeatherTool.jsonSchema()]
        
        let request = ChatCompletionRequest(
            model: providerName == "OpenAI" ? "gpt-4o" : "claude-sonnet-4-5-20250929",
            messages: [
                .user(content: .text("What's the weather in Boston? Use fahrenheit."))
            ],
            maxTokens: 500,
            tools: tools,
            toolChoice: .function(ToolChoice.FunctionChoice(name: "get_weather"))
        )
        
        let response = try await provider.sendChatCompletion(request: request)
        
        if let toolCalls = response.choices.first?.message.toolCalls {
            for toolCall in toolCalls {
                if let function = toolCall.function {
                    print("   🛠️  Tool Called: \(function.name)")
                    print("   📝 Arguments: \(function.arguments)")
                    
                    // Actually execute the tool
                    let jsonData = function.arguments.data(using: .utf8)!
                    var tool = WeatherTool()
                    tool = try tool.validateAndSetParameters(jsonData)
                    let result = try await tool.execute()
                    print("   ✅ Tool Result: \(result.content)")
                }
            }
        } else if let content = response.choices.first?.message.content {
            print("   📄 LLM Response: \(content)")
        }
        
        print("   📊 Usage: \(response.usage?.totalTokens ?? 0) tokens")
        
    } catch {
        print("   ❌ \(providerName) Tool Error: \(error)")
    }
}

func testAgentWithTools(provider: LLM) async {
    print("\n🤖 Testing Agent with Tools...")
    print("   ℹ️  Agent functionality requires additional setup - skipping for now")
    print("   📝 This would test agent integration with tools once Agent is properly exposed")
}

// MARK: - Helper Functions

func createTestImage() -> Data? {
    #if canImport(UIKit)
    // iOS/tvOS implementation
    let size = CGSize(width: 100, height: 100)
    let renderer = UIGraphicsImageRenderer(size: size)
    
    let image = renderer.image { context in
        // Fill with blue background
        UIColor.blue.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        
        // Add a red circle
        UIColor.red.setFill()
        let circleRect = CGRect(x: 25, y: 25, width: 50, height: 50)
        context.fillEllipse(in: circleRect)
    }
    
    return image.jpegData(compressionQuality: 0.8)
    
    #elseif canImport(AppKit)
    // macOS implementation
    let size = NSSize(width: 100, height: 100)
    let image = NSImage(size: size)
    
    image.lockFocus()
    defer { image.unlockFocus() }
    
    // Fill with blue background
    NSColor.blue.setFill()
    NSRect(origin: .zero, size: size).fill()
    
    // Add a red circle
    NSColor.red.setFill()
    let circleRect = NSRect(x: 25, y: 25, width: 50, height: 50)
    NSBezierPath(ovalIn: circleRect).fill()
    
    // Convert to data
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData) else {
        return nil
    }
    
    return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    
    #else
    // Fallback for other platforms - return nil to skip base64 test
    print("   ⚠️  Image generation not supported on this platform")
    return nil
    #endif
}

// MARK: - Helper Extensions

extension String {
    static func *(left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

func testAnthropicGenerateObject(provider: AnthropicProvider) async {
    print("\n🏗️ Testing Anthropic Generate Object Method...")
    
    do {
        // Define schema models using JSONSchemaModel and @Field (like the fruit example)
        struct Product: JSONSchemaModel {
            @Field(
                description: "The name of the product",
                validation: [
                    "type": .string("string"),
                    "minLength": .integer(1),
                    "maxLength": .integer(100)
                ]
            )
            var name: String = ""
            
            @Field(
                description: "The price of the product in USD",
                validation: [
                    "type": .string("number"),
                    "minimum": .number(0.01),
                    "maximum": .number(10000.0)
                ]
            )
            var price: Double = 0.0
            
            @Field(
                description: "The category of the product",
                validation: [
                    "type": .string("string"),
                    "enum": .array([.string("Electronics"), .string("Clothing"), .string("Books"), .string("Home")])
                ]
            )
            var category: String = ""
            
            @Field(
                description: "Whether the product is in stock",
                validation: [
                    "type": .string("boolean")
                ]
            )
            var inStock: Bool = false
            
            init() {}
        }
        
        struct UserPreferences: JSONSchemaModel {
            @Field(
                description: "The UI theme preference",
                validation: [
                    "type": .string("string"),
                    "enum": .array([.string("light"), .string("dark"), .string("auto")])
                ]
            )
            var theme: String = ""
            
            @Field(
                description: "Whether notifications are enabled",
                validation: [
                    "type": .string("boolean")
                ]
            )
            var notifications: Bool = false
            
            init() {}
        }
        
        struct User: JSONSchemaModel {
            @Field(
                description: "The user's unique identifier",
                validation: [
                    "type": .string("integer"),
                    "minimum": .integer(1),
                    "maximum": .integer(999999)
                ]
            )
            var id: Int = 0
            
            @Field(
                description: "The user's full name",
                validation: [
                    "type": .string("string"),
                    "minLength": .integer(1),
                    "maxLength": .integer(50)
                ]
            )
            var name: String = ""
            
            @Field(
                description: "The user's email address",
                validation: [
                    "type": .string("string"),
                    "format": .string("email")
                ]
            )
            var email: String = ""
            
            @Field(
                description: "The user's preferences object",
                validation: [
                    "type": .string("object")
                ]
            )
            var preferences: UserPreferences = UserPreferences()
            
            init() {}
        }
        
        // Test 1: Product generation using JSON Schema
        let productRequest = ChatCompletionRequest(
            model: "claude-sonnet-4-5-20250929",
            messages: [
                .system(content: .text("Return valid JSON following the schema")),
                .user(content: .text("Generate a laptop product with realistic data"))
            ],
            responseFormat: .jsonSchema(
                name: "product",
                description: "A product with name, price, category, and stock status",
                schemaBuilder: Product.schema()
                    .title("Product")
                    .description("A product object with all required fields"),
                strict: true
            )
        )
        
        // Use the generateObject method with JSON Schema
        let product: Product = try await provider.generateObject(request: productRequest)
        
        print("✅ Anthropic Product Object Generated:")
        print("   📦 Name: \(product.name)")
        print("   💰 Price: $\(product.price)")
        print("   🏷️  Category: \(product.category)")
        print("   📊 In Stock: \(product.inStock)")
        
        // Test 2: User generation using JSON Schema with nested object
        let userRequest = ChatCompletionRequest(
            model: "claude-sonnet-4-5-20250929",
            messages: [
                .system(content: .text("Return valid JSON following the schema")),
                .user(content: .text("Generate a user profile for a software developer"))
            ],
            responseFormat: .jsonSchema(
                name: "user",
                description: "A user profile with preferences",
                schemaBuilder: User.schema()
                    .title("User Profile")
                    .description("A complete user profile with nested preferences"),
                strict: true
            )
        )
        
        // Use the generateObject method with complex nested schema
        let user: User = try await provider.generateObject(request: userRequest)
        
        print("✅ Anthropic User Object Generated:")
        print("   🆔 ID: \(user.id)")
        print("   👤 Name: \(user.name)")
        print("   📧 Email: \(user.email)")
        print("   🎨 Theme: \(user.preferences.theme)")
        print("   🔔 Notifications: \(user.preferences.notifications)")
        
    } catch {
        print("❌ Anthropic Generate Object Error: \(error)")
    }
} 
