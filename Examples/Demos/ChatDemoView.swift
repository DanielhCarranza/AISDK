//
//  ChatDemoView.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 30/12/24.
//

import MarkdownUI
import SwiftUI
import Alamofire
import Foundation


struct ChatDemoView: View {
    @State private var textOutput = ""
    @State private var isStreaming = false
    @State private var selectedProvider: ProviderType = .openAI
    
    // LLM instances
    let openAIClient = OpenAIProvider(apiKey: AgenticModels.gpt4.apiKey ?? " ")
    let claudeClient = ClaudeProvider(apiKey: AgenticModels.claude.apiKey ?? " ") // Use AgenticModels for API key
    
    // Computed property to get the current provider
    private var currentProvider: LLM {
        switch selectedProvider {
        case .openAI:
            return openAIClient
        case .claude:
            return claudeClient
        }
    }
    
    // Current model based on provider
    private var currentModel: String {
        switch selectedProvider {
        case .openAI:
            return "gpt-4o"
        case .claude:
            return "claude-3-7-sonnet-20250219"
        }
    }
    
    var body: some View {
        VStack {
            // Provider selector
            Picker("Provider", selection: $selectedProvider) {
                Text("OpenAI").tag(ProviderType.openAI)
                Text("Claude").tag(ProviderType.claude)
            }
            .pickerStyle(MenuPickerStyle())
            .padding()
            
            Text("Current Model: \(currentModel)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom)
            
            Text("Chat Output:")
                .font(.headline)
            ScrollView {
                Markdown(textOutput)
                    .padding()
            }
            Spacer()
            VStack {
                // Original buttons
                HStack {
                    Button("Send Non-Streaming") {
                        Task {
                            do {
                                let model = selectedProvider == .openAI ? "gpt-4o" : "claude-3-7-sonnet-20250219"
                                let req = ChatCompletionRequest(
                                    model: model,
                                    messages: [
                                        .user(content: .text("How many r's are in the word Endurant Healthspan?"))
                                    ]
                                )
                                let resp = try await currentProvider.sendChatCompletion(request: req)
                                if let msg = resp.choices.first?.message.content {
                                    textOutput.append(contentsOf: "\nAssistant: \(msg)\n")
                                }
                            } catch {
                                textOutput.append(contentsOf: "\nError: \(error)")
                            }
                        }
                    }
                    .disabled(isStreaming)
                    
                    Button("Start Streaming") {
                        textOutput = ""
                        isStreaming = true
                        Task {
                            let model = selectedProvider == .openAI ? "gpt-4o" : "claude-3-7-sonnet-20250219"
                            let streamReq = ChatCompletionRequest(
                                model: model,
                                messages: [
                                    .user(content: .text("Tell me a joke, token by token."))
                                ],
                                stream: true
                            )
                            
                            do {
                                for try await chunk in try await currentProvider.sendChatCompletionStream(request: streamReq) {
                                    for choice in chunk.choices {
                                        if let token = choice.delta.content {
                                            textOutput.append(token)
                                        }
                                    }
                                }
                                isStreaming = false
                                textOutput.append("\n-- End of Stream --\n")
                            } catch {
                                textOutput.append("\nError: \(error)")
                                isStreaming = false
                            }
                        }
                    }
                    .disabled(isStreaming)
                }
                
                // New buttons for image and tool examples
                HStack {
                    Button("Image Example") {
                        Task {
                            textOutput = ""
                            do {
                                // Example 1: Simple URL image
                                let model = selectedProvider == .openAI ? "gpt-4o" : "claude-3-7-sonnet-20250219"
                                let urlRequest = ChatCompletionRequest(
                                    model: model,
                                    messages: [
                                        .user(content: .parts([
                                            .text("What do you see in this image?"),
                                            .imageURL(.url(URL(string: "https://cropper.watch.aetnd.com/cdn.watch.aetnd.com/sites/2/2017/09/1st_Crusade_GettyImages-587492330.jpg?w=1440")!))
                                        ]))
                                    ]
                                )
                                
                                // Example 2: Local image with UIImage
                                if let image = UIImage(named: "sample_image"),
                                   let imageData = image.jpegData(compressionQuality: 0.9) {
                                    
                                    // Example 3: Multiple images with different detail levels
                                    let multiImageRequest = ChatCompletionRequest(
                                        model: model,
                                        messages: [
                                            .user(content: .parts([
                                                .text("What is in this image?"),
                                                // .imageURL(.url(URL(string: "https://cropper.watch.aetnd.com/cdn.watch.aetnd.com/sites/2/2017/09/1st_Crusade_GettyImages-587492330.jpg?w=1440")!), 
                                                //         detail: .high),
                                                .imageURL(.base64(imageData), 
                                                        detail: .low),
                                                .text("What are the differences between these images?")
                                            ]))
                                        ]
                                    )
                                    
                                    // Execute the request (using multiImageRequest as an example)
                                    let response = try await currentProvider.sendChatCompletion(request: multiImageRequest)
                                    if let msg = response.choices.first?.message.content {
                                        textOutput.append(contentsOf: "\nAssistant: \(msg)\n")
                                    }
                                } else {
                                    // Fallback to URL-only example if local image fails
                                    let response = try await currentProvider.sendChatCompletion(request: urlRequest)
                                    if let msg = response.choices.first?.message.content {
                                        textOutput.append(contentsOf: "\nAssistant: \(msg)\n")
                                    }
                                }
                            } catch {
                                textOutput.append(contentsOf: "\nError: \(error)")
                            }
                        }
                    }
                    .disabled(isStreaming)
                    
                    Button("Tool Example") {
                        Task {
                            textOutput = ""
                            do {
                                // Define the weather tool
                                struct WeatherTool: AITool {
                                    let name = "get_current_weather"
                                    let description = "Get the current weather in a given location"
                                    
                                    init() {}
                                    
                                    enum TemperatureUnit: String, Codable, CaseIterable {
                                        case celsius
                                        case fahrenheit
                                    }

                                    @AIParameter(description: "The city and state, e.g. San Francisco, CA")
                                    var location: String = ""
                                    
                                    @AIParameter(description: "Temperature unit")
                                    var unit: TemperatureUnit = .celsius

                                    func execute() async throws -> AIToolResult  {
                                        return AIToolResult(content: "Weather \(self.location) \(self.unit.rawValue)")
                                    }
                                }
                                
                                // Get the tool schema using the static method
                                let tools = [WeatherTool.jsonSchema()]
                                
                                let model = selectedProvider == .openAI ? "gpt-4o" : "claude-3-7-sonnet-20250219"
                                let toolRequest = ChatCompletionRequest(
                                    model: model,
                                    messages: [
                                        .user(content: .text("What's the weather in Boston today?"))
                                    ],
                                    maxTokens: 1000,
                                    temperature: 0.7,
                                    tools: tools,
                                    toolChoice: .function(ToolChoice.FunctionChoice(name: "get_current_weather")),
                                    parallelToolCalls: true
                                )
                                
                                let response = try await currentProvider.sendChatCompletion(request: toolRequest)
                                if let toolCalls = response.choices.first?.message.toolCalls {
                                    for toolCall in toolCalls {
                                        if let function = toolCall.function {
                                            textOutput.append(contentsOf: "\nTool: \(function.name)")
                                            textOutput.append(contentsOf: "\nArguments: \(function.arguments)\n")
                                            
                                            // Here you could parse the arguments and execute the tool
                                            // For demo purposes, we'll just show the call
                                        }
                                    }
                                } else if let content = response.choices.first?.message.content {
                                    textOutput.append(contentsOf: "\nAssistant: \(content)\n")
                                }
                            } catch {
                                if let afError = error as? AFError {
                                    textOutput.append(contentsOf: "\nAlamofire Error: \(afError.localizedDescription)")
                                    if let underlyingError = afError.underlyingError {
                                        textOutput.append(contentsOf: "\nUnderlying Error: \(underlyingError)")
                                    }
                                    if case let .responseSerializationFailed(reason) = afError {
                                        if case .inputDataNilOrZeroLength = reason {
                                            textOutput.append(contentsOf: "\nResponse Data was nil or zero length")
                                        }
                                    }
                                } else {
                                    textOutput.append(contentsOf: "\nError: \(error)")
                                }
                            }
                        }
                    }
                    .disabled(isStreaming)
                    
                    Button("JSON Example") {
                        Task {
                            textOutput = ""
                            do {
                                // Simple JSON Object example
                                let model = selectedProvider == .openAI ? "gpt-4o" : "claude-3-7-sonnet-20250219"
                                let jsonRequest = ChatCompletionRequest(
                                    model: model,
                                    messages: [
                                        .system(content: .text("Return valid JSON only")),
                                        .user(content: .text("Return a list of 3 fruits with their colors"))
                                    ],
                                    responseFormat: .jsonObject
                                )
                                
                                let response = try await currentProvider.sendChatCompletion(request: jsonRequest)
                                if let content = response.choices.first?.message.content {
                                    textOutput.append(contentsOf: "\nJSON Response:\n\(content)\n")
                                }
                                
                                // Schema example
                                let schema = FruitList.generateJSONSchema(
                                    title: "Fruit List",
                                    description: "A collection of fruits with their colors"
                                )
                                print("Full Schema:", schema)
                                
                                let schemaRequest = ChatCompletionRequest(
                                    model: model,
                                    messages: [
                                        .system(content: .text("Return valid JSON following the schema")),
                                        .user(content: .text("List 3 tropical fruits"))
                                    ],
                                    responseFormat: .jsonSchema(
                                        name: "fruit_list",
                                        description: "A list of fruits with their colors",
                                        schemaBuilder: FruitList.schema()
                                            .title("Fruit List")
                                            .description("A collection of fruits with their colors"),
                                        strict: true
                                    )
                                )
                                
                                // Use generateObject method for schema-validated responses
                                let fruitList: FruitList = try await currentProvider.generateObject(request: schemaRequest)
                                for fruit in fruitList.fruits {
                                    textOutput.append(contentsOf: "\n- \(fruit.name) is \(fruit.color)")
                                }
                            } catch {
                                textOutput.append(contentsOf: "\nError: \(error)")
                            }
                        }
                    }
                    .disabled(isStreaming)
                }
                
                // Button to test Claude's extended thinking (only for Claude provider)
                if selectedProvider == .claude {
                    Button("Claude Extended Thinking") {
                        Task {
                            textOutput = ""
                            do {
                                // Use the withExtendedThinking helper method for Claude
                                let basicRequest = ChatCompletionRequest(
                                    model: "claude-3-7-sonnet-20250219",
                                    messages: [
                                        .user(content: .text("Solve this complex problem: Find all positive integer solutions to the equation x² - y² = 2023. Explain your approach."))
                                    ]
                                )
                                
                                // Use the extended thinking helper
                                let extendedRequest = (claudeClient as? ClaudeProvider)?.withExtendedThinking(
                                    request: basicRequest,
                                    budgetTokens: 3000
                                ) ?? basicRequest
                                
                                let response = try await claudeClient.sendChatCompletion(request: extendedRequest)
                                if let msg = response.choices.first?.message.content {
                                    textOutput.append(contentsOf: "\nAssistant (with extended thinking): \(msg)\n")
                                }
                            } catch {
                                textOutput.append(contentsOf: "\nError: \(error)")
                            }
                        }
                    }
                    .disabled(isStreaming)
                }
                
                Button("Weather Tool Agent Test") {
                    Task {
                        textOutput = "Starting Weather Tool Agent Test...\n"
                        
                        do {
                            // Define the simple weather tool
                            struct WeatherToolForAgent: AITool {
                                let name = "get_current_weather"
                                let description = "Get the current weather in a given location"
                                
                                init() {}
                                
                                enum TemperatureUnit: String, Codable, CaseIterable {
                                    case celsius
                                    case fahrenheit
                                }

                                @AIParameter(description: "The city and state, e.g. San Francisco, CA")
                                var location: String = ""
                                
                                @AIParameter(description: "Temperature unit")
                                var unit: TemperatureUnit = .celsius

                                func execute() async throws -> AIToolResult  {
                                    // Add logging to verify execution
                                    print("🌦️ Weather tool executing for location: \(location), unit: \(unit.rawValue)")
                                    return AIToolResult(content: "Weather for \(self.location): 72°\(self.unit == .celsius ? "C" : "F"), partly cloudy")
                                }
                            }
                            
                            // Initialize an agent with just the weather tool
                            let agent = try Agent(
                                model: AgenticModels.gpt4,
                                tools: [WeatherToolForAgent.self],
                                instructions: "You are a helpful assistant that provides weather information."
                            )
                            
                            // Create test message
                            let userMessage = ChatMessage(message: .user(content: .text("What's the weather in Boston today?")))
                            
                            // Test with specific function requirement
                            textOutput += "🧪 TEST: Specific weather function\n"
                            for try await message in agent.sendStream(userMessage, requiredTool: "get_current_weather") {
                                if case .assistant(let content, _, _) = message.message {
                                    textOutput += "Assistant: \(content)\n"
                                } else if case .tool(let content, let name, _) = message.message {
                                    textOutput += "✅ Tool called: \(name)\n"
                                    textOutput += "Tool response: \(content)\n"
                                }
                            }
                            
                            textOutput += "\nWeather tool test completed!"
                            
                        } catch {
                            textOutput += "❌ Error: \(error.localizedDescription)"
                        }
                    }
                }
                .disabled(isStreaming)
            }
            .padding()
        }
        .padding()
    }
}

// Enum to track selected provider
enum ProviderType {
    case openAI
    case claude
}

struct Fruit: JSONSchemaModel {
    @Field(
        description: "The name of the fruit"

    )
    var name: String = ""
    
    @Field(
        description: "The color of the fruit"

    )
    var color: String = ""
    
    init() {}
}

struct FruitList: JSONSchemaModel {
    @Field(
        description: "List of fruits with their colors"

    )
    var fruits: [Fruit] = []
    
    init() {}
}
