# AISDK Package Structure

This document outlines the structure and organization of the AISDK Swift package, including module separation, dependencies, and build configuration.

## Package.swift Configuration

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AISDK",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
        .watchOS(.v11),
        .tvOS(.v18)
    ],
    products: [
        // Core library - Required
        .library(
            name: "AISDK",
            targets: ["AISDK"]
        ),
        
        // Feature libraries - Optional
        .library(
            name: "AISDKChat",
            targets: ["AISDKChat"]
        ),
        
        .library(
            name: "AISDKVoice",
            targets: ["AISDKVoice"]
        ),
        
        .library(
            name: "AISDKVision",
            targets: ["AISDKVision"]
        ),
        
        .library(
            name: "AISDKResearch",
            targets: ["AISDKResearch"]
        )
    ],
    dependencies: [
        // Network layer
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.8.0"),
        
        // JSON handling
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0"),
        
        // Markdown rendering for chat UI
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.0"),
        
        // Charts for data visualization
        .package(url: "https://github.com/danielgindi/Charts.git", from: "5.0.0"),
        
        // Vision/LiveKit support
        .package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.0.0"),
        
        // Development tools
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0")
    ],
    targets: [
        // MARK: - Core Target
        .target(
            name: "AISDK",
            dependencies: [
                "Alamofire",
                "SwiftyJSON"
            ],
            path: "Sources/AISDK",
            resources: [
                .process("Resources")
            ]
        ),
        
        // MARK: - Feature Targets
        .target(
            name: "AISDKChat",
            dependencies: [
                "AISDK",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Charts", package: "Charts")
            ],
            path: "Sources/AISDKChat"
        ),
        
        .target(
            name: "AISDKVoice",
            dependencies: ["AISDK"],
            path: "Sources/AISDKVoice"
        ),
        
        .target(
            name: "AISDKVision",
            dependencies: [
                "AISDK",
                .product(name: "LiveKit", package: "client-sdk-swift")
            ],
            path: "Sources/AISDKVision"
        ),
        
        .target(
            name: "AISDKResearch",
            dependencies: ["AISDK"],
            path: "Sources/AISDKResearch"
        ),
        
        // MARK: - Test Targets
        .testTarget(
            name: "AISDKTests",
            dependencies: ["AISDK"],
            path: "Tests/AISDKTests"
        ),
        
        .testTarget(
            name: "AISDKChatTests",
            dependencies: ["AISDKChat"],
            path: "Tests/AISDKChatTests"
        ),
        
        .testTarget(
            name: "AISDKVoiceTests",
            dependencies: ["AISDKVoice"],
            path: "Tests/AISDKVoiceTests"
        ),
        
        .testTarget(
            name: "AISDKVisionTests",
            dependencies: ["AISDKVision"],
            path: "Tests/AISDKVisionTests"
        ),
        
        .testTarget(
            name: "AISDKResearchTests",
            dependencies: ["AISDKResearch"],
            path: "Tests/AISDKResearchTests"
        )
    ]
)
```

## Directory Structure

```
AISDK/
├── Package.swift
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── Sources/
│   ├── AISDK/                      # Core functionality (required)
│   │   ├── Agents/
│   │   │   ├── Agent.swift
│   │   │   ├── AgentCallbacks.swift
│   │   │   ├── AgentState.swift
│   │   │   └── SubAgents/
│   │   │       ├── BaseAgent.swift
│   │   │       ├── ConversationalAgent.swift
│   │   │       └── SpecializedAgent.swift
│   │   ├── Core/
│   │   │   ├── Tool.swift
│   │   │   ├── ToolRegistry.swift
│   │   │   ├── Parameter.swift
│   │   │   ├── ToolMetadata.swift
│   │   │   ├── RenderableTool.swift
│   │   │   └── ToolSchema.swift
│   │   ├── LLMs/
│   │   │   ├── LLMProtocol.swift
│   │   │   ├── OpenAIProvider.swift
│   │   │   ├── ClaudeProvider.swift
│   │   │   └── AgenticModels.swift
│   │   ├── Models/
│   │   │   ├── Message.swift
│   │   │   ├── ChatCompletionRequest.swift
│   │   │   ├── ChatCompletionResponse.swift
│   │   │   ├── ChatCompletionChunk.swift
│   │   │   ├── ToolCall.swift
│   │   │   └── Usage.swift
│   │   ├── Client/
│   │   │   └── AISDKClient.swift
│   │   ├── Errors/
│   │   │   ├── AISDKError.swift
│   │   │   ├── AgentError.swift
│   │   │   └── ToolError.swift
│   │   ├── Utilities/
│   │   │   ├── JSONEncoder+Extensions.swift
│   │   │   ├── AsyncStream+Extensions.swift
│   │   │   ├── Analyzer.swift
│   │   │   └── Logger.swift
│   │   └── Resources/
│   │       └── Prompts/
│   │           └── DefaultPrompts.swift
│   │
│   ├── AISDKChat/                  # Chat features
│   │   ├── Manager/
│   │   │   ├── AIChatManager.swift
│   │   │   ├── ChatManager.swift
│   │   │   └── MetadataTracker.swift
│   │   ├── Models/
│   │   │   ├── ChatSession.swift
│   │   │   ├── ChatMessage.swift
│   │   │   ├── Attachment.swift
│   │   │   ├── SuggestedQuestion.swift
│   │   │   └── UserContent.swift
│   │   ├── Storage/
│   │   │   ├── ChatStorageProtocol.swift
│   │   │   ├── MemoryStorage.swift
│   │   │   └── Documentation/
│   │   │       ├── FirebaseAdapter.md
│   │   │       └── SupabaseAdapter.md
│   │   ├── Views/
│   │   │   ├── ChatCompanionView.swift
│   │   │   ├── AIConversationView.swift
│   │   │   ├── MessageBubble.swift
│   │   │   ├── AIMessageInputView.swift
│   │   │   ├── SuggestedQuestionsView.swift
│   │   │   ├── AttachmentMenuView.swift
│   │   │   ├── AttachmentPreviewBar.swift
│   │   │   ├── ImagePreviewBar.swift
│   │   │   ├── PDFViewerSheet.swift
│   │   │   ├── MetadataView.swift
│   │   │   ├── TypingIndicator.swift
│   │   │   └── ChatHistoryView.swift
│   │   ├── Tools/
│   │   │   ├── Examples/
│   │   │   │   ├── WeatherTool.swift
│   │   │   │   ├── CalculatorTool.swift
│   │   │   │   ├── SearchTool.swift
│   │   │   │   ├── TranslateTool.swift
│   │   │   │   └── ThinkTool.swift
│   │   │   └── UITools/
│   │   │       ├── DisplayMedicationTool.swift
│   │   │       ├── ChartTool.swift
│   │   │       ├── TableTool.swift
│   │   │       ├── ImageDisplayTool.swift
│   │   │       └── MapTool.swift
│   │   └── Features/
│   │       ├── TitleGenerator.swift
│   │       ├── SuggestedQuestionsGenerator.swift
│   │       └── AttachmentProcessor.swift
│   │
│   ├── AISDKVoice/                 # Voice features (native implementation)
│   │   ├── Core/
│   │   │   ├── AIVoiceMode.swift
│   │   │   ├── AudioEngine.swift
│   │   │   ├── SpeechRecognizer.swift
│   │   │   ├── SpeechSynthesizer.swift
│   │   │   └── VoiceActivityDetector.swift
│   │   ├── Models/
│   │   │   ├── AudioData.swift
│   │   │   ├── VoiceSettings.swift
│   │   │   └── TranscriptionResult.swift
│   │   ├── Components/
│   │   │   ├── AnimatedTranscriptView.swift
│   │   │   ├── AudioLevelView.swift
│   │   │   └── WaveformView.swift
│   │   └── Views/
│   │       ├── AIVoiceModeView.swift
│   │       ├── VoiceButton.swift
│   │       └── VoiceOverlay.swift
│   │
│   ├── AISDKVision/                # Vision features (LiveKit-based)
│   │   ├── Providers/
│   │   │   └── ChatContext.swift
│   │   ├── Services/
│   │   │   └── ConnectionDetails.swift
│   │   ├── UI/
│   │   │   └── CircleButtonStyle.swift
│   │   └── Views/
│   │       ├── ActionBarView.swift
│   │       ├── AgentView.swift
│   │       ├── ChatView.swift
│   │       ├── ConnectionView.swift
│   │       └── VisionCameraView.swift
│   │
│   └── AISDKResearch/              # Research capabilities
│       ├── Agent/
│       │   ├── ResearcherAgent.swift
│       │   ├── ExperimentalResearchAgent.swift
│       │   └── ResearcherAgentState.swift
│       ├── Models/
│       │   ├── ResearchMetadata.swift
│       │   ├── ResearchResult.swift
│       │   └── Evidence.swift
│       ├── Tools/
│       │   ├── CompleteResearchTool.swift
│       │   ├── ReadEvidenceTool.swift
│       │   ├── ReasonEvidenceTool.swift
│       │   ├── SearchMedicalEvidenceTool.swift
│       │   ├── StartResearchTool.swift
│       │   └── SummarizeTool.swift
│       └── Views/
│           └── ResearcherAgentDemoView.swift
│
├── Tests/
│   ├── AISDKTests/
│   │   ├── AgentTests.swift
│   │   ├── ToolTests.swift
│   │   ├── LLMProviderTests.swift
│   │   └── Mocks/
│   │       ├── MockLLMProvider.swift
│   │       ├── MockTool.swift
│   │       └── MockStorage.swift
│   ├── AISDKChatTests/
│   │   ├── ChatManagerTests.swift
│   │   ├── ChatSessionTests.swift
│   │   └── MessageBubbleTests.swift
│   ├── AISDKVoiceTests/
│   │   ├── VoiceModeTests.swift
│   │   └── SpeechRecognizerTests.swift
│   ├── AISDKVisionTests/
│   │   └── VisionModeTests.swift
│   └── AISDKResearchTests/
│       ├── ResearchAgentTests.swift
│       └── ResearchToolTests.swift
│
├── Examples/
│   ├── BasicChat/
│   │   ├── BasicChatApp.swift
│   │   └── README.md
│   ├── VoiceAssistant/
│   │   ├── VoiceAssistantApp.swift
│   │   └── README.md
│   ├── VisionDemo/
│   │   ├── VisionDemoApp.swift
│   │   └── README.md
│   ├── ResearchDemo/
│   │   ├── ResearchDemoApp.swift
│   │   └── README.md
│   └── ToolsDemo/
│       ├── ToolsDemoApp.swift
│       ├── CustomTools.swift
│       └── README.md
│
└── Documentation/
    ├── GettingStarted.md
    ├── APIReference.md
    ├── Architecture.md
    ├── Tools/
    │   ├── CreatingTools.md
    │   ├── RenderableTools.md
    │   ├── ToolExamples.md
    │   └── ToolBestPractices.md
    ├── Storage/
    │   ├── StorageProtocol.md
    │   ├── FirebaseAdapter.md
    │   ├── SupabaseAdapter.md
    │   └── CustomStorage.md
    ├── Features/
    │   ├── ChatFeatures.md
    │   ├── VoiceMode.md
    │   ├── VisionMode.md
    │   └── ResearchMode.md
    ├── Migration/
    │   └── FromHealthCompanion.md
    └── Tutorials/
        ├── 01-BasicSetup.md
        ├── 02-FirstChatApp.md
        ├── 03-CreatingTools.md
        ├── 04-AddingVoice.md
        └── 05-ResearchAgent.md
```

## Module Organization

### Core Module (AISDK)

The core module is the only required dependency and contains:

1. **Agents/**: Agent system, callbacks, and state management
2. **Core/**: Tool infrastructure and metadata handling
3. **LLMs/**: Language model provider implementations
4. **Models/**: Data structures for API communication
5. **Client/**: Network client for API calls
6. **Errors/**: Error types and handling
7. **Utilities/**: Helper functions and extensions

### Feature Modules

#### AISDKChat
Complete chat management system including:
- Session management with storage abstraction
- Rich UI components
- Tool examples with UI rendering
- Attachment handling
- Suggested questions

#### AISDKVoice
Native voice implementation using:
- AVFoundation for audio
- Speech framework for recognition
- AVSpeechSynthesizer for TTS
- No external dependencies

#### AISDKVision
LiveKit-based real-time video:
- Camera integration
- Real-time streaming
- Agent interaction with video

#### AISDKResearch
Specialized research capabilities:
- Research-specific agents
- Evidence management
- Academic search tools

## Dependency Management

### Core Dependencies

```swift
// Required for AISDK core
dependencies: [
    "Alamofire",      // Network layer
    "SwiftyJSON"      // JSON parsing
]
```

### Optional Dependencies

```swift
// For AISDKChat
dependencies: [
    "MarkdownUI",     // Markdown rendering
    "Charts"          // Data visualization
]

// For AISDKVision
dependencies: [
    "LiveKit"         // Real-time video
]
```

## Build Configuration

### Swift Settings

```swift
swiftSettings: [
    .enableExperimentalFeature("StrictConcurrency"),
    .define("AISDK_VERSION", to: "\"1.0.0\"")
]
```

### Platform-Specific Code

```swift
#if os(iOS)
    // iOS-specific implementation
#elseif os(macOS)
    // macOS-specific implementation
#endif
```

## Testing Structure

### Unit Tests
- Test individual components in isolation
- Mock external dependencies
- Aim for >80% coverage on core functionality

### Integration Tests
- Test module interactions
- Verify API contracts
- Test real tool execution

### Example Test

```swift
@testable import AISDK
import XCTest

final class AgentTests: XCTestCase {
    var agent: Agent!
    var mockProvider: MockLLMProvider!
    
    override func setUp() {
        super.setUp()
        mockProvider = MockLLMProvider()
        agent = try! Agent(
            model: .gpt4o,
            llm: mockProvider
        )
    }
    
    func testSendMessage() async throws {
        // Arrange
        mockProvider.mockResponse = ChatCompletionResponse(/* ... */)
        
        // Act
        let response = try await agent.send("Hello")
        
        // Assert
        XCTAssertEqual(response.content, "Expected response")
    }
}
```

## Module Imports

### Basic Usage

```swift
import AISDK  // Core functionality only
```

### With Chat UI

```swift
import AISDK
import AISDKChat
```

### Full Featured App

```swift
import AISDK
import AISDKChat
import AISDKVoice
import AISDKVision
```

## Best Practices

1. **Keep Core Minimal**: Only essential functionality in AISDK target
2. **Feature Isolation**: Each feature module should work independently
3. **Protocol-Oriented**: Use protocols for extensibility
4. **Dependency Injection**: Allow custom implementations
5. **Documentation**: Document all public APIs
6. **Testing**: Write tests for critical paths
7. **Examples**: Provide working examples for each feature

## Version Management

### Semantic Versioning

- **1.0.0**: Initial release
- **1.1.0**: New features (backward compatible)
- **1.0.1**: Bug fixes
- **2.0.0**: Breaking changes

### Release Process

```bash
# Tag release
git tag -a v1.0.0 -m "Initial release"
git push origin v1.0.0

# Generate documentation
swift package generate-documentation
```

## Storage Architecture

### Protocol Design

```swift
public protocol ChatStorageProtocol {
    // Core operations
    func save(session: ChatSession) async throws
    func load(id: String) async throws -> ChatSession?
    func delete(id: String) async throws
    func list() async throws -> [ChatSession]
    
    // Message operations
    func appendMessage(sessionId: String, message: ChatMessage) async throws
    func updateMessage(sessionId: String, messageId: String, message: ChatMessage) async throws
    
    // Metadata operations
    func updateTitle(sessionId: String, title: String) async throws
    func updateMetadata(sessionId: String, metadata: [String: Any]) async throws
}
```

### Default Implementation

```swift
/// In-memory storage for development and testing
public class MemoryStorage: ChatStorageProtocol {
    private var sessions: [String: ChatSession] = [:]
    
    public func save(session: ChatSession) async throws {
        sessions[session.id] = session
    }
    
    // ... other methods
}
```

### Custom Adapters

See documentation for implementing:
- Firebase Firestore adapter
- Supabase adapter
- Core Data adapter
- Custom backend adapter 