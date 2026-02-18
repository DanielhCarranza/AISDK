# Getting Started with AISDK

This guide will help you get up and running with AISDK in your Swift project.

> **Note:** This guide covers AISDK 2.0 APIs. Legacy 1.x APIs (`Agent`, `LLM`, `Tool`, `ChatMessage`) are deprecated and will be removed in a future release. If you're migrating from 1.x, see the [Migration Guide](../../../docs/MIGRATION-GUIDE.md).

## Prerequisites

- Xcode 15.0 or later
- iOS 18.0+ / macOS 14.0+ / watchOS 11.0+ / tvOS 18.0+
- Swift 5.9+
- An API key from OpenAI or Anthropic (Claude)

## Installation

### Swift Package Manager

1. In Xcode, select **File -> Add Package Dependencies**
2. Enter the repository URL: `https://github.com/yourusername/AISDK.git`
3. Select the version rule (e.g., "Up to Next Major Version")
4. Choose the products you need:
   - `AISDK` - Core functionality (required)
   - `AISDKChat` - Chat UI components
   - `AISDKVoice` - Native voice features
   - `AISDKVision` - LiveKit vision features
   - `AISDKResearch` - Research capabilities

### Package.swift

If you're using Package.swift directly:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/AISDK.git", from: "2.0.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "AISDK", package: "AISDK"),
            .product(name: "AISDKChat", package: "AISDK"),
            .product(name: "AISDKVoice", package: "AISDK")
        ]
    )
]
```

## Quick Start

### 1. Basic Setup

```swift
import AISDK

// Create a provider client
let client = OpenRouterClient(apiKey: "your-api-key")

// Create an agent
let agent = AIAgentActor(
    model: client,
    instructions: "You are a helpful assistant."
)

// Send a message
let result = try await agent.execute(messages: [.user("Hello! How are you?")])
print(result.text)
```

### 2. Chat Interface with UI

```swift
import SwiftUI
import AISDK
import AISDKChat

@main
struct ChatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var chatManager: AIChatManager

    init() {
        let client = OpenRouterClient()
        let agent = AIAgentActor(model: client)
        _chatManager = State(initialValue: AIChatManager(
            agent: agent,
            storage: MemoryStorage()
        ))
    }

    var body: some View {
        ChatCompanionView(manager: chatManager)
    }
}
```

### 3. Using Tools with UI Rendering

```swift
// Define a tool that renders UI
struct WeatherTool: RenderableTool {
    let name = "get_weather"
    let description = "Get the current weather with visual display"

    @AIParameter(description: "The city to get weather for")
    var city: String = ""

    func execute() async throws -> AIToolResult {
        // Fetch weather data (mock for example)
        let weatherData = WeatherData(
            city: city,
            temp: 72,
            condition: "Sunny",
            icon: "sun.max.fill"
        )

        let jsonData = try JSONEncoder().encode(weatherData)
        let metadata = RenderMetadata(toolName: name, jsonData: jsonData)

        return AIToolResult(content: "It's 72F and sunny in \(city)", metadata: metadata)
    }

    func render(from data: Data) -> AnyView {
        let weather = try? JSONDecoder().decode(WeatherData.self, from: data)

        return AnyView(
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: weather?.icon ?? "sun.max.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.yellow)

                    VStack(alignment: .leading) {
                        Text(weather?.city ?? "Unknown")
                            .font(.headline)
                        Text("\(weather?.temp ?? 0)F")
                            .font(.largeTitle)
                            .bold()
                    }
                }

                Text(weather?.condition ?? "")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }
}

// Create agent with the tool
let client = OpenRouterClient(apiKey: "your-api-key")
let agent = AIAgentActor(
    model: client,
    tools: [WeatherTool.self]
)

// The UI will automatically render the weather widget when the tool is used
```

### 4. Voice-Enabled Chat

```swift
import AISDK
import AISDKVoice

struct VoiceChatView: View {
    @StateObject private var voiceMode = AIVoiceMode()
    private let agent: AIAgentActor

    init() {
        let client = OpenRouterClient()
        self.agent = AIAgentActor(model: client)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Transcript display
            ScrollView {
                Text(voiceMode.transcript)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Audio level indicator
            if voiceMode.isRecording {
                HStack(spacing: 4) {
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: 4, height: CGFloat.random(in: 10...30))
                            .animation(.easeInOut(duration: 0.3), value: voiceMode.audioLevel)
                    }
                }
                .frame(height: 30)
            }

            // Voice button
            Button(action: toggleVoice) {
                Image(systemName: voiceMode.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 50))
                    .foregroundStyle(voiceMode.isRecording ? .red : .blue)
                    .padding()
                    .background(Circle().fill(Color(.systemGray5)))
            }
        }
        .padding()
    }

    func toggleVoice() {
        if voiceMode.isRecording {
            voiceMode.stopRecording()
        } else {
            Task {
                try await voiceMode.startConversation(with: agent)
            }
        }
    }
}
```

## Step-by-Step Tutorial

### Step 1: Create a New SwiftUI Project

1. Open Xcode
2. Create a new project (iOS App)
3. Choose SwiftUI for the interface
4. Product Name: "AISDKDemo"
5. Select "Use Core Data" and "Include Tests" as needed

### Step 2: Add AISDK Package

1. Select your project in the navigator
2. Select your app target
3. Go to "Package Dependencies" tab
4. Click "+" to add a package
5. Enter: `https://github.com/yourusername/AISDK.git`
6. Add products: AISDK (required), AISDKChat (recommended)

### Step 3: Configure API Keys

#### Option A: Environment Variable (Recommended for Development)

Edit your scheme:
1. Product -> Scheme -> Edit Scheme
2. Select "Run" -> "Arguments"
3. Add environment variable: `OPENAI_API_KEY` = `your-key`

```swift
// In your code
let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
let client = OpenRouterClient(apiKey: apiKey)
let agent = AIAgentActor(model: client)
```

#### Option B: Secure Storage (Recommended for Production)

```swift
import Security

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)

        if let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}
```

### Step 4: Create Your First Agent

Create `AIManager.swift`:

```swift
import AISDK
import SwiftUI

@Observable
class AIManager {
    let agent: AIAgentActor
    var messages: [AIMessage] = []
    var isLoading = false
    var error: Error?

    init() {
        let client = OpenRouterClient()
        self.agent = AIAgentActor(
            model: client,
            instructions: """
                You are a helpful AI assistant. Be concise and friendly.
                Format your responses using markdown when appropriate.
                """
        )
    }

    func sendMessage(_ content: String) async {
        messages.append(.user(content))

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await agent.execute(messages: messages)
            messages.append(.assistant(result.text))
        } catch {
            self.error = error
            messages.append(.assistant("Error: \(error.localizedDescription)"))
        }
    }

    func sendStreamingMessage(_ content: String) async {
        messages.append(.user(content))

        var streamedText = ""

        isLoading = true
        defer { isLoading = false }

        do {
            for try await event in agent.streamExecute(messages: messages) {
                switch event {
                case .textDelta(let text):
                    streamedText += text
                case .finish:
                    break
                default:
                    break
                }
            }
            messages.append(.assistant(streamedText))
        } catch {
            self.error = error
        }
    }
}
```

### Step 5: Create the Chat UI

Update `ContentView.swift`:

```swift
import SwiftUI
import AISDK
import MarkdownUI

struct ContentView: View {
    @State private var aiManager = AIManager()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(aiManager.messages.enumerated()), id: \.offset) { index, message in
                                MessageRow(message: message)
                                    .id(index)
                            }

                            if aiManager.isLoading {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .padding()
                            }
                        }
                        .padding()
                    }
                    .onChange(of: aiManager.messages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(aiManager.messages.count - 1, anchor: .bottom)
                        }
                    }
                }

                Divider()

                // Input area
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Type a message...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .focused($isInputFocused)
                        .onSubmit {
                            sendMessage()
                        }

                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(inputText.isEmpty ? Color.gray : Color.blue)
                            .clipShape(Circle())
                    }
                    .disabled(inputText.isEmpty || aiManager.isLoading)
                }
                .padding()
            }
            .navigationTitle("AI Chat")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        inputText = ""

        Task {
            // Use streaming for better UX
            await aiManager.sendStreamingMessage(message)
        }
    }
}

struct MessageRow: View {
    let message: AIMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Markdown(message.textContent ?? "")
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? Color.blue : Color(.systemGray5))
                    )
                    .foregroundStyle(isUser ? .white : .primary)
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

struct TypingIndicator: View {
    @State private var animationAmount = 0.0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationAmount)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animationAmount
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            animationAmount = 1.2
        }
    }
}
```

### Step 6: Add Tools with UI

Create `Tools.swift`:

```swift
import AISDK
import SwiftUI
import Charts

// MARK: - Data Models

struct WeatherData: Codable {
    let city: String
    let temp: Int
    let condition: String
    let icon: String
    let humidity: Int
    let windSpeed: Double
}

struct StockData: Codable {
    let symbol: String
    let price: Double
    let change: Double
    let changePercent: Double
    let volume: Int
}

// MARK: - Weather Tool

struct WeatherTool: RenderableTool {
    let name = "get_weather"
    let description = "Get current weather for a location"

    @AIParameter(description: "City name")
    var location: String = ""

    func execute() async throws -> AIToolResult {
        // Mock weather data - replace with real API
        let weather = WeatherData(
            city: location,
            temp: Int.random(in: 60...85),
            condition: ["Sunny", "Cloudy", "Rainy", "Partly Cloudy"].randomElement()!,
            icon: ["sun.max.fill", "cloud.fill", "cloud.rain.fill", "cloud.sun.fill"].randomElement()!,
            humidity: Int.random(in: 40...80),
            windSpeed: Double.random(in: 5...20)
        )

        let jsonData = try JSONEncoder().encode(weather)
        let metadata = RenderMetadata(toolName: name, jsonData: jsonData)

        let description = """
        Current weather in \(weather.city):
        - Temperature: \(weather.temp)F
        - Condition: \(weather.condition)
        - Humidity: \(weather.humidity)%
        - Wind: \(String(format: "%.1f", weather.windSpeed)) mph
        """

        return (description, metadata)
    }

    func render(from data: Data) -> AnyView {
        guard let weather = try? JSONDecoder().decode(WeatherData.self, from: data) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text(weather.city)
                            .font(.title2)
                            .bold()
                        Text(weather.condition)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: weather.icon)
                        .font(.system(size: 50))
                        .symbolRenderingMode(.multicolor)
                }

                // Temperature
                Text("\(weather.temp)")
                    .font(.system(size: 60, weight: .thin))
                    .frame(maxWidth: .infinity)

                // Details
                HStack(spacing: 20) {
                    Label("\(weather.humidity)%", systemImage: "humidity.fill")
                    Label("\(String(format: "%.1f", weather.windSpeed)) mph", systemImage: "wind")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.blue.opacity(0.1), .blue.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        )
    }
}

// MARK: - Stock Tool

struct StockTool: RenderableTool {
    let name = "get_stock_price"
    let description = "Get current stock price and information"

    @AIParameter(description: "Stock symbol (e.g., AAPL)")
    var symbol: String = ""

    func execute() async throws -> AIToolResult {
        // Mock stock data - replace with real API
        let basePrice = Double.random(in: 100...500)
        let change = Double.random(in: -10...10)

        let stock = StockData(
            symbol: symbol.uppercased(),
            price: basePrice,
            change: change,
            changePercent: (change / basePrice) * 100,
            volume: Int.random(in: 1000000...50000000)
        )

        let jsonData = try JSONEncoder().encode(stock)
        let metadata = RenderMetadata(toolName: name, jsonData: jsonData)

        let changeSign = stock.change >= 0 ? "+" : ""
        let description = """
        \(stock.symbol) Stock Information:
        - Price: $\(String(format: "%.2f", stock.price))
        - Change: \(changeSign)$\(String(format: "%.2f", stock.change)) (\(changeSign)\(String(format: "%.2f", stock.changePercent))%)
        - Volume: \(formatNumber(stock.volume))
        """

        return (description, metadata)
    }

    func render(from data: Data) -> AnyView {
        guard let stock = try? JSONDecoder().decode(StockData.self, from: data) else {
            return AnyView(EmptyView())
        }

        let isPositive = stock.change >= 0
        let changeColor = isPositive ? Color.green : Color.red
        let changeIcon = isPositive ? "arrow.up.right" : "arrow.down.right"

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                // Symbol and price
                HStack(alignment: .top) {
                    Text(stock.symbol)
                        .font(.title2)
                        .bold()

                    Spacer()

                    VStack(alignment: .trailing) {
                        Text("$\(String(format: "%.2f", stock.price))")
                            .font(.title)
                            .bold()

                        HStack(spacing: 4) {
                            Image(systemName: changeIcon)
                                .font(.caption)
                            Text("\(isPositive ? "+" : "")\(String(format: "%.2f", stock.change))")
                            Text("(\(isPositive ? "+" : "")\(String(format: "%.2f", stock.changePercent))%)")
                        }
                        .font(.subheadline)
                        .foregroundStyle(changeColor)
                    }
                }

                // Volume
                HStack {
                    Text("Volume")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatNumber(stock.volume))
                        .bold()
                }
                .font(.callout)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        )
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// Create agent with tools
let client = OpenRouterClient(apiKey: "your-key")
let agent = AIAgentActor(
    model: client,
    tools: [WeatherTool.self, StockTool.self],
    instructions: """
        You are a helpful assistant with access to weather and stock information.
        When users ask about weather or stocks, use the appropriate tools.
        """
)
```

## Common Patterns

### Pattern 1: Custom Storage Implementation

```swift
import AISDK
import AISDKChat

// Create a custom storage adapter
class UserDefaultsStorage: ChatStorageProtocol {
    private let userDefaults = UserDefaults.standard
    private let sessionsKey = "chat_sessions"

    func save(session: ChatSession) async throws {
        var sessions = try await list()

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }

        let data = try JSONEncoder().encode(sessions)
        userDefaults.set(data, forKey: sessionsKey)
    }

    func load(id: String) async throws -> ChatSession? {
        let sessions = try await list()
        return sessions.first { $0.id == id }
    }

    func delete(id: String) async throws {
        var sessions = try await list()
        sessions.removeAll { $0.id == id }

        let data = try JSONEncoder().encode(sessions)
        userDefaults.set(data, forKey: sessionsKey)
    }

    func list() async throws -> [ChatSession] {
        guard let data = userDefaults.data(forKey: sessionsKey) else {
            return []
        }
        return try JSONDecoder().decode([ChatSession].self, from: data)
    }

    // Additional protocol methods...
}
```

### Pattern 2: Error Handling with Retry

```swift
@Observable
class RobustAIManager {
    let agent: AIAgentActor
    var messages: [AIMessage] = []
    var error: Error?

    init() {
        let client = OpenRouterClient()
        self.agent = AIAgentActor(model: client)
    }

    func sendMessageWithRetry(_ content: String, maxRetries: Int = 3) async {
        messages.append(.user(content))
        var retries = 0

        while retries < maxRetries {
            do {
                let result = try await agent.execute(messages: messages)
                messages.append(.assistant(result.text))
                return
            } catch AISDKError.rateLimitExceeded {
                // Wait before retry
                try? await Task.sleep(for: .seconds(2))
                retries += 1
            } catch AISDKError.networkError {
                // Network error, retry immediately
                retries += 1
            } catch {
                // Other errors, don't retry
                self.error = error
                return
            }
        }

        self.error = AISDKError.networkError(
            NSError(domain: "AISDK", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed after \(maxRetries) retries"
            ])
        )
    }
}
```

### Pattern 3: Voice with Visual Feedback

```swift
import AISDKVoice

struct VoiceAssistantView: View {
    @StateObject private var voiceMode = AIVoiceMode()
    private let agent: AIAgentActor

    init() {
        let client = OpenRouterClient(apiKey: "your-key")
        self.agent = AIAgentActor(model: client)
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                // Animated waveform
                if voiceMode.isRecording {
                    WaveformView(audioLevel: voiceMode.audioLevel)
                        .frame(height: 100)
                        .padding(.horizontal)
                }

                // Transcript
                ScrollView {
                    Text(voiceMode.transcript)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(maxHeight: 300)

                // Voice button
                VoiceButton(isRecording: voiceMode.isRecording) {
                    toggleVoice()
                }
            }
            .padding()
        }
    }

    func toggleVoice() {
        Task {
            if voiceMode.isRecording {
                await voiceMode.stopRecording()
            } else {
                try await voiceMode.startConversation(with: agent)
            }
        }
    }
}

struct WaveformView: View {
    let audioLevel: Float
    @State private var phase = 0.0

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let midHeight = height / 2

                path.move(to: CGPoint(x: 0, y: midHeight))

                for x in stride(from: 0, through: width, by: 2) {
                    let relativeX = x / width
                    let sine = sin((relativeX + phase) * .pi * 4)
                    let y = midHeight + (sine * midHeight * CGFloat(audioLevel))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 2
            )
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

struct VoiceButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.blue)
                    .frame(width: 80, height: 80)

                if isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 4)
                        .frame(width: 100, height: 100)
                        .scaleEffect(isRecording ? 1.2 : 1)
                        .opacity(isRecording ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1)
                            .repeatForever(autoreverses: false),
                            value: isRecording
                        )
                }

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
        }
    }
}
```

## Best Practices

1. **API Key Security**
   - Never hardcode API keys in your source code
   - Use environment variables for development
   - Use Keychain or secure storage for production
   - Consider using a proxy server for client apps

2. **Error Handling**
   - Always handle network errors gracefully
   - Provide user-friendly error messages
   - Implement retry logic for transient failures
   - Log errors for debugging

3. **Performance**
   - Use streaming for better perceived performance
   - Implement message pagination for long conversations
   - Clear old messages to manage memory
   - Debounce rapid user inputs

4. **User Experience**
   - Show loading indicators during processing
   - Disable input controls while streaming
   - Provide visual feedback for voice recording
   - Implement proper keyboard handling

5. **Accessibility**
   - Add VoiceOver labels to all controls
   - Support Dynamic Type for text
   - Ensure sufficient color contrast
   - Provide haptic feedback where appropriate

## Next Steps

- Explore [Creating Custom Tools](../Documentation/Tools/CreatingTools.md)
- Learn about [Renderable Tools](../Documentation/Tools/RenderableTools.md)
- Implement [Custom Storage](../Documentation/Storage/CustomStorage.md)
- Try [Research Mode](../Documentation/Features/ResearchMode.md)

## Troubleshooting

### Common Issues

1. **"Missing API Key" Error**
   ```swift
   // Check environment variable
   print(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "Not set")

   // Verify in scheme editor
   // Product -> Scheme -> Edit Scheme -> Arguments
   ```

2. **Voice Permission Denied**
   ```swift
   // Add to Info.plist
   <key>NSMicrophoneUsageDescription</key>
   <string>This app needs microphone access for voice chat</string>

   <key>NSSpeechRecognitionUsageDescription</key>
   <string>This app needs speech recognition for voice input</string>
   ```

3. **Tool Not Executing**
   ```swift
   // Verify tool registration
   print(AIToolRegistry.registeredTools)

   // Check tool name matches
   let tool = WeatherTool()
   print("Tool name: \(tool.name)")
   ```

4. **UI Not Rendering for Tools**
   ```swift
   // Ensure tool implements RenderableTool
   if let renderable = tool as? RenderableTool {
       // Tool can render UI
   }

   // Check metadata is being passed
   print("Metadata: \(String(describing: message.metadata))")
   ```

### Getting Help

- GitHub Issues: [github.com/yourusername/AISDK/issues](https://github.com/yourusername/AISDK/issues)
- Discord Community: [discord.gg/aisdk](https://discord.gg/aisdk)
- Documentation: [docs.aisdk.dev](https://docs.aisdk.dev)
- Stack Overflow: Tag with `aisdk-swift`
