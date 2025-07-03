# Changelog

All notable changes to AISDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-01-28

### Added

#### 🚀 Universal Message System
- **Cross-Provider Message Format**: Implemented `AIInputMessage` system that provides consistent API across all LLM providers
- **Unified Content Types**: Universal content types supporting text, images, audio, files, and video with automatic provider-specific conversion
- **Provider Conversion Extensions**: Automatic conversion to provider-specific formats:
  - `AIMessage+ChatConversions.swift`: OpenAI Chat Completions API conversion
  - `AIMessage+ResponseConversions.swift`: OpenAI Response API conversion  
  - `AIMessage+AnthropicConversions.swift`: Anthropic Claude API conversion
  - `AIMessage+GeminiConversions.swift`: Google Gemini API conversion
- **Order-Aware Multimodal**: Preserves content order across all providers (text + image + text sequences)
- **Type-Safe Tool Calls**: Universal `AIToolCall` system with provider-specific conversion
- **Comprehensive Testing**: 316 lines of unit tests covering all functionality, edge cases, and provider conversions

#### 📱 SwiftUI Modernization  
- **iOS 17+ Observation**: Migrated from `@ObservableObject/@Published` to modern `@Observable` pattern
- **Improved Performance**: Better state management with automatic dependency tracking
- **Cleaner API**: Simplified view model implementation without explicit `@Published` declarations

#### 🔧 Enhanced Response API Integration
- **Universal Message Support**: Response API now works seamlessly with universal message system
- **Simplified Conversions**: Automatic conversion from universal format to Response API structures
- **Background Processing**: Enhanced support for long-running Deep Research tasks
- **Rich Citation Support**: Improved citation and annotation handling

#### 📚 Documentation & Examples
- **Deep Research API Guide**: Comprehensive documentation for OpenAI's Deep Research API (`OpenAI-DeepResearch-API.md`)
- **Universal Message Usage**: Updated usage examples showing cross-provider compatibility
- **Implementation Plans**: Detailed technical documentation for universal message system and Response API improvements

### Technical Implementation

#### Universal Message Architecture
```swift
// Beautiful cross-provider syntax
let message = AIInputMessage.user([
    .text("Compare these medical scans:"),
    .image(scan1Data, detail: .high),
    .text("vs"),
    .image(scan2Data, detail: .high),
    .text("What are the key differences?")
])

// Works identically across all providers
let openaiResponse = try await openaiProvider.sendMessage(message)
let claudeResponse = try await anthropicProvider.sendMessage(message)  
let geminiResponse = try await geminiProvider.sendMessage(message)
```

#### Content Type System
- **AIContentPart**: Unified enum supporting all modalities
- **AIImageContent**: Images with data/URL support and quality settings
- **AIAudioContent**: Audio with format detection and optional transcripts
- **AIFileContent**: Files with type detection and MIME type handling
- **AIVideoContent**: Video support (future-ready extension)

#### Provider Compatibility Matrix
- **OpenAI**: ✅ Chat Completions & Response API full support
- **Anthropic**: ✅ Claude API with vision and tool support  
- **Gemini**: ✅ Full multimodal and tool support
- **Graceful Fallbacks**: Providers handle unsupported content elegantly

### Breaking Changes
- **SwiftUI Views**: Updated to use `@Observable` instead of `@ObservableObject` (iOS 17+ requirement)
- **View Models**: Removed `@Published` property wrappers in favor of automatic observation

### Migration Guide
```swift
// Before (iOS 16 compatible)
@MainActor  
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
}

// After (iOS 17+ optimized)
@Observable
class ChatViewModel {
    var messages: [ChatMessage] = []
}
```

### Performance Improvements
- **Automatic Observation**: Better performance with selective view updates
- **Memory Efficiency**: Reduced overhead from explicit property observation
- **Conversion Caching**: Optimized provider-specific message conversions

### Developer Experience
- **Consistent API**: Same message format works across all providers
- **Type Safety**: Full compile-time checking for all content types
- **Error Handling**: Comprehensive error handling with detailed error types
- **Testing Support**: Extensive test coverage for reliability

---

## [1.0.0] - 2025-06-28

### Added

#### 🤖 Core AISDK Features
- **Multi-Provider LLM Support**: Complete integration for OpenAI, Anthropic (Claude), and Google Gemini models
- **Unified Agent System**: Centralized AI agent orchestration with state management and callbacks
- **Advanced Tool Framework**: Extensible tool system with UI rendering capabilities via `RenderableTool` protocol
- **Streaming Support**: Real-time streaming responses with Server-Sent Events (SSE)
- **Modern Swift Architecture**: Built with Swift Concurrency, `@Observable`, and latest SwiftUI features

#### 🏗️ Model Management
- **Universal Model Protocol**: Standardized interface for all LLM providers with capabilities and metadata
- **Provider-Specific Models**: 
  - **OpenAI**: GPT-4.1, GPT-4o, o4-mini, o3 reasoning models, DALL-E, Whisper, TTS models
  - **Anthropic**: Claude 4 (Opus/Sonnet), Claude 3.7 Sonnet, Claude 3.5 (Sonnet/Haiku), Claude 3 series
  - **Google**: Gemini 2.5 (Pro/Flash), Gemini 2.0, Gemini 1.5, Imagen 4.0, Veo 2.0, Live API models
- **Capability-Based Selection**: Models organized by capabilities (reasoning, multimodal, tools, etc.)
- **Performance Tiers**: Classification by performance level (nano, mini, small, medium, large, pro, flagship, ultra)

#### 💬 AISDKChat Module
- **Complete Chat Management**: Session-based conversations with persistent storage
- **Rich UI Components**: Pre-built SwiftUI views for chat interfaces
  - `ChatCompanionView`: Full-featured chat interface
  - `MessageBubble`: Customizable message display
  - `AttachmentPreviewBar`: File and image attachment handling
  - `TypingIndicator`: Real-time typing feedback
- **Storage Protocol**: Flexible storage backend with adapters for Firebase, Supabase, and custom implementations
- **Attachment System**: Support for images, PDFs, and other file types
- **Suggested Questions**: Context-aware conversation starters

#### 🎙️ AISDKVoice Module
- **Native Speech Recognition**: Built with AVFoundation and Speech framework
- **Voice Activity Detection**: Automatic speech detection and recording
- **Text-to-Speech Integration**: Native speech synthesis capabilities
- **Voice UI Components**: 
  - `AIVoiceModeView`: Complete voice interaction interface
  - `AnimatedTranscriptView`: Real-time transcript display with animations
- **Audio Session Management**: Optimized for voice interactions

#### 👁️ AISDKVision Module
- **LiveKit Integration**: Real-time video streaming and processing
- **Camera Management**: Native camera access and video capture
- **Agent Video Interaction**: AI agents that can see and respond to video input
- **Real-time Processing**: Low-latency video analysis and response

#### 🔬 AISDKResearch Module
- **Specialized Research Agents**: AI agents optimized for research and analysis tasks
- **Evidence Management**: Tools for gathering, analyzing, and presenting research findings
- **Research Tools**: 
  - Medical record analysis
  - Evidence reasoning
  - Health profile search
  - Biomarker analysis
- **Research UI**: Dedicated interface for research workflows

#### 🛠️ Developer Experience
- **Comprehensive Documentation**: Detailed guides, API reference, and examples
- **Demo Applications**: Working examples for basic chat and tool usage
- **Test Suite**: Extensive testing framework with real API integration tests
- **Error Handling**: Robust error management with detailed error types
- **Multiplatform Support**: iOS 17+, macOS 14+, watchOS 10+, tvOS 17+

#### 🔧 Tools & Extensions
- **Parameter Validation**: Type-safe tool parameter definitions with validation
- **Metadata System**: Rich metadata support for tool execution results
- **UI Rendering**: Tools can render custom SwiftUI views for rich interactions
- **Tool Registry**: Centralized tool management and discovery
- **JSON Schema**: Automatic schema generation for tool parameters

#### 📦 Package Architecture
- **Modular Design**: Optional feature modules that can be adopted individually
- **Core Dependencies**: Minimal required dependencies (Alamofire, SwiftyJSON)
- **Feature Dependencies**: Additional dependencies only loaded when using specific modules
- **Clean API**: Consistent and intuitive Swift API design

### Technical Implementation

#### Architecture Highlights
- **Protocol-Oriented Design**: Extensible protocols for models, providers, and storage
- **Async/Await Support**: Modern Swift concurrency throughout
- **SwiftUI Integration**: Native SwiftUI components and state management
- **Memory Management**: Efficient handling of large language model responses
- **Configuration Management**: Centralized configuration with environment variable support

#### Performance Optimizations
- **Streaming Responses**: Chunked response processing for better user experience
- **Caching**: Model response caching and efficient data handling
- **Background Processing**: Non-blocking operations for UI responsiveness
- **Resource Management**: Optimized memory usage for large conversations

#### Security & Privacy
- **API Key Management**: Secure handling of authentication credentials
- **Local Processing**: On-device speech recognition and processing where possible
- **Data Encryption**: Secure storage protocols for sensitive information

### Platform Requirements
- **Xcode**: 15.0+
- **Swift**: 5.9+
- **iOS**: 17.0+
- **macOS**: 14.0+
- **watchOS**: 10.0+
- **tvOS**: 17.0+

### Dependencies
- **Alamofire**: 5.8.0+ (networking)
- **SwiftyJSON**: 5.0.0+ (JSON handling)
- **MarkdownUI**: 2.0.0+ (chat UI markdown rendering)
- **Charts**: 5.0.0+ (data visualization)
- **LiveKit**: 2.0.0+ (vision features)

---

*This release represents the initial stable version of AISDK, providing a comprehensive foundation for building AI-powered Swift applications across all Apple platforms.* 