# Changelog

All notable changes to AISDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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