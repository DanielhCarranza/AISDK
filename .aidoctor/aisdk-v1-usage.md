# AISDK v1 Usage in AIDoctor — Reference for the v2 Team

> **Purpose:** This is how our major application called AIDoctor uses version 1 of the AISDK that is currently in the main branch. This file will be important because it will be used to understand how AIDoctor uses v1 of the SDK and how testing on this app will work via the new v2 of the AISDK.

---

This document describes how AISDK v1 is used throughout the AIDoctor iOS application. It is written for the AISDK v2 engineering team and their agents, so they understand what the current SDK provides, where and how it integrates, and what capabilities the modernization must preserve or improve.

---

## 1. Application Background

AIDoctor is a health management iOS app built with SwiftUI. It helps users track their health, get AI-powered insights, manage medications, keep a health journal, and generate medical reports. The app runs on iOS 17+ and uses Firebase for backend services (Firestore, Auth, Remote Config, Storage).

The AISDK is a **first-party Swift package** that provides the foundational AI layer for the entire application. It is the abstraction through which all client-side LLM interactions flow — chat, tool execution, structured output generation, vision analysis, and research. Without it, none of the AI-powered features function.

### Core Feature Set Powered by AISDK

| Feature | What it does | Primary AISDK surface |
|---|---|---|
| AI Chat | Conversational health companion with streaming responses | `Agent`, `sendStream()`, `ChatMessage` |
| Tool Use | AI-initiated actions (journal logging, health events, reports, search) | `Tool` protocol, `@Parameter`, `ToolMetadata` |
| Medication Info | Structured medication details from LLM | `generateObject()`, `JSONSchemaModel` |
| Medication Extraction | Extract drug info from packaging photos | `ChatCompletionRequest` with vision parts |
| Suggested Questions | AI-generated follow-up prompts | `ChatCompletionRequest`, `JSONSchemaModel` |
| Health Profile Summaries | AI-generated profile summaries | `OpenAIProvider`, `ChatCompletionRequest` |
| Research Mode | Evidence-based medical research workflow | `ExperimentalResearchAgent`, specialized tools |
| Document Analysis | Parse medical documents and extract biomarkers | AISDK types for structured extraction |

Features that use **server-side AI** (health plans, assessments, dynamic home messages, insights reports) call the AIDoctor backend API rather than AISDK directly, but their request/response types are defined using AISDK models.

---

## 2. AISDK v1 Package Structure

The AISDK is a modular Swift package with these products:

```
AISDK           — Core: Agent, providers, tools, message types (required)
AISDKChat       — Chat session management utilities (optional)
AISDKVoice      — Voice interaction support (optional)
AISDKVision     — Camera/video AI features (optional)
AISDKResearch   — Research agent capabilities (optional)
```

In practice, the app imports primarily `AISDK` (the core module). The optional modules are used for specialized features like voice mode and research.

---

## 3. Core Abstractions

### Agent

The `Agent` class is the central orchestrator. It manages a multi-turn conversation with an LLM, handles tool calls, tracks state, and exposes streaming.

```swift
// From AIChatManager.setup()
self.agent = Agent(
    llm: OpenAIProvider(
        model: gpt52Model,
        apiKey: ConfigManager.shared["OPENAI_API_KEY"] ?? "No API key"
    ),
    tools: [
        LogJournalEntryTool.self,
        GeneralSearchTool.self,
        ManageHealthEventTool.self,
        ManageHealthReportTool.self,
        DisplayMedicationTool.self,
        ThinkTool.self
    ],
    instructions: systemPrompt
)
```

Key `Agent` methods the app depends on:
- `sendStream(_ message: ChatMessage, requiredTool: String?) -> AsyncSequence<ChatMessage>` — stream a response
- `setMessages(_ messages: [ChatMessage])` — sync conversation history
- `addCallbacks(_ tracker: MetadataTracker)` — register for tool execution callbacks
- `onStateChange: ((AgentState) -> Void)?` — observe agent state transitions

### AgentState

An enum the app observes to drive UI state:

```swift
enum AgentState {
    case idle
    case thinking
    case executingTool(String)  // tool name
    case responding
    case error(AIError)
}
```

The app binds this to show typing indicators, tool execution labels, error cards, and to trigger suggested question generation when the agent returns to `.idle`.

### LLMModelAdapter

Describes a model's capabilities and constraints:

```swift
let gpt52Model = LLMModelAdapter(
    name: "gpt-5.2",
    displayName: "GPT-5.2",
    description: "GPT-5.2 flagship model...",
    provider: .openai,
    category: .chat,
    versionType: .stable,
    capabilities: [
        .text, .vision, .audio,
        .tools, .functionCalling, .structuredOutputs, .jsonMode,
        .reasoning, .thinking,
        .streaming, .caching, .longContext,
        .multilingual
    ],
    tier: .flagship,
    latency: .moderate,
    inputTokenLimit: 256_000,
    outputTokenLimit: 16_384,
    knowledgeCutoff: "August 2025"
)
```

### OpenAIProvider

The LLM provider used for all client-side AI calls. Key methods:
- `sendChatCompletion(request:)` — single-shot completion
- `sendChatCompletionStream(request:)` — streaming completion
- `generateObject<T: JSONSchemaModel>(request:) -> T` — structured output with schema validation

### ChatMessage

The universal message type used across the SDK and app:

```swift
// Message role variants
ChatMessage(message: .user(content: .text("...")))
ChatMessage(message: .user(content: .parts([.text("..."), .imageURL(.base64(data))])))
ChatMessage(message: .assistant(content: .text("...")))
ChatMessage(message: .system(content: .text("...")))
ChatMessage(message: .tool(content: .text("...")))
ChatMessage(message: .developer(content: .text("...")))
```

Properties the app depends on:
- `id: String` — unique identifier
- `message: Message` — enum with role-specific content
- `isPending: Bool` — flag for in-progress streaming messages
- `feedback: ChatMessage.Feedback?` — user upvote/downvote
- `attachments: [AISDK.Attachment]` — file/image attachments
- `displayContent: String` — rendered text for UI

`ChatMessage` conforms to `Codable` and `Equatable`. The app stores arrays of `ChatMessage` directly in Firestore via `ChatSession`.

### ChatCompletionRequest

Used for direct LLM calls outside the Agent pattern:

```swift
let request = ChatCompletionRequest(
    model: "gpt-5-nano",
    messages: [
        .system(content: .text(systemPrompt)),
        .user(content: .text("Provide medication_information for \(name)"))
    ],
    responseFormat: .jsonSchema(
        name: "medication_information",
        schemaBuilder: MedicationInformation.schema(),
        strict: true
    )
)
```

### UserContent.Part

For multimodal messages:
- `.text(String)` — text content
- `.imageURL(.base64(Data), detail: .high)` — inline image
- `.imageURL(.url(URL))` — remote image

---

## 4. Tool System

### Tool Protocol

Every tool conforms to this pattern:

```swift
struct LogJournalEntryTool: Tool {
    let name = "log_journal"
    let description = "Records health events, observations, symptoms, mood..."

    init() {}

    @Parameter(description: "Entry to log")
    var entry: String = ""

    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Perform the action, return result string + optional metadata
        try await Self.journal.saveAsync(entry: journalEntry, mediaData: nil, mediaType: nil)
        return (content: "Journal Entry Logged - \(timestamp)\n...", metadata: nil)
    }
}
```

Key elements:
- `name: String` — identifier the LLM uses to call the tool
- `description: String` — tells the LLM when/how to use it
- `@Parameter` — property wrapper that generates JSON schema parameters with descriptions and optional validation
- `execute() async throws -> (content: String, metadata: ToolMetadata?)` — the action
- `ToolMetadata` — optional structured metadata returned alongside the text result

### Parameter Validation

The `@Parameter` property wrapper supports validation rules:

```swift
@Parameter(description: "Type of event", validation: ["enum": ["procedure", "diagnosis", "milestone", "change", "other"]])
var eventType: String = "other"
```

### Registered Tools in Production

**AIChatManager** registers these tools:

| Tool | Purpose | Side Effects |
|---|---|---|
| `LogJournalEntryTool` | Log health observations to journal | Writes to Firestore |
| `GeneralSearchTool` | Web search for non-medical queries | Simulated (returns placeholder) |
| `ManageHealthEventTool` | Create health timeline events | Simulated |
| `ManageHealthReportTool` | Generate/retrieve health reports | Simulated |
| `DisplayMedicationTool` | Show medication information | Read-only lookup |
| `ThinkTool` | Internal reasoning (no data modification) | None |
| `SearchMedicalEvidenceTool` | Medical literature search | API call (currently commented out) |

**ResearcherAgent** registers 12 additional specialized tools for evidence-based research workflows.

### ToolMetadata

Metadata types the app defines for tool results:

```swift
struct Source: ToolMetadata {
    let title: String
    let content: String?
    let url: String
    let evidenceType: String
}

struct MedicalEvidence: ToolMetadata {
    let sources: [Source]
    let evidenceLevel: String
    let confidenceScore: Double?
    let lastUpdated: Date
}
```

### MetadataTracker

A callback object registered with the Agent to accumulate tool metadata across a conversation turn:

```swift
self.agent.addCallbacks(metadataTracker)
```

The tracker collects sources and evidence during research operations for citation display.

---

## 5. Structured Output (JSONSchemaModel)

The SDK provides a `JSONSchemaModel` protocol and `@Field` property wrapper for type-safe LLM outputs:

```swift
struct MedicationInformation: JSONSchemaModel, Codable {
    @Field(description: "Product name")
    var name: String = ""

    @Field(description: "Price in dollars", validation: ["minimum": 0])
    var price: Double = 0.0

    init() {}
}
```

Used with `responseFormat: .jsonSchema(name:schemaBuilder:strict:)` on `ChatCompletionRequest`, and consumed via `provider.generateObject(request:)` which returns the decoded type directly.

**Where this is used in AIDoctor:**
- `MedicationAIService` — medication information lookup
- `MedicationExtractionService` — medication extraction from images
- `SuggestedQuestion` generation — follow-up question suggestions
- `DocumentAnalysisService` — document parsing and biomarker extraction

---

## 6. Streaming Pattern

The primary user-facing AI interaction is streaming chat. Here is the complete flow:

### 1. User sends a message

```swift
agent.setMessages(currentSession?.messages ?? [])

for try await message in agent.sendStream(chatMessage, requiredTool: requiredTool) {
    if Task.isCancelled { break }
    handleStreamedMessage(message)
}
```

### 2. Partial tokens arrive

The stream yields `ChatMessage` objects with `isPending = true` during streaming. The app updates a pending placeholder in the messages array:

```swift
private func handleStreamedMessage(_ message: ChatMessage) {
    switch message.message {
    case .assistant:
        if message.isPending {
            // Update existing pending message or add new one
            if let lastIndex = currentSession.messages.lastIndex(where: { $0.isPending }) {
                currentSession.messages[lastIndex] = message
            } else {
                currentSession.messages.append(message)
            }
            messages = currentSession.messages
        }
    case .tool:
        storeMessage(message)
    default:
        storeMessage(message)
    }
}
```

### 3. Stream completes

The pending message is finalized (`isPending = false`) and persisted to Firestore.

### 4. Watchdog timers

The app implements timeout protection:
- **First-token timeout**: 20 seconds — if no assistant content arrives, cancel
- **Stall timeout**: 30 seconds — if tokens stop arriving, cancel

On timeout, the stream is cancelled and partial content is preserved.

---

## 7. Configuration and API Key Management

API keys are managed through `ConfigManager`, a singleton that:

1. Fetches keys from **Firebase Remote Config** on app launch
2. Stores them securely in the **iOS Keychain** (via KeychainAccess)
3. Provides access via subscript: `ConfigManager.shared["OPENAI_API_KEY"]`

```swift
private let apiKeys = [
    "OPENAI_API_KEY",
    "OPENAI_ORGANIZATION_ID",
    "GROQ_API_KEY",
    "GROQ_BASE_PATH",
    "GEMINI_API_KEY",
    "SUPERWALL_API_KEY",
    "POSTHOG_API_KEY"
]
```

Every `OpenAIProvider` instance receives its API key at construction time from this manager.

---

## 8. Models Used

| Model | Provider | Purpose | Token Limits |
|---|---|---|---|
| `gpt-5.2` | OpenAI | Primary chat (AIChatManager) | 256K in / 16K out |
| `gpt-5-nano` | OpenAI | Titles, suggested questions, medication info | Lightweight |
| `gpt-5-mini` | OpenAI | Medication extraction (vision) | Mid-tier |
| `o4-mini` | OpenAI | Reasoning tasks | — |
| `claude-3-5-sonnet` | Anthropic | Available via `ClaudeProvider` (not actively used) | — |
| `gemini-2.5-flash` | Google | Journal video/image analysis (via Firebase AI, not AISDK) | — |

The `ClaudeProvider` is implemented in the SDK but not used in production. All production LLM calls go through `OpenAIProvider`.

---

## 9. Integration Map — All Files That Import AISDK

### Chat Core (8 files)
- `AIDoctor/AI/Chat/AIChatManager.swift` — primary chat orchestrator
- `AIDoctor/AI/Chat/AttachmentManager.swift` — file/image attachment handling
- `AIDoctor/AI/Chat/Models/ChatSession.swift` — Firestore-persisted session model
- `AIDoctor/AI/Chat/Models/SuggestedQuestion.swift` — JSONSchemaModel for suggestions
- `AIDoctor/AI/Chat/Models/MedicalRecordAttachment.swift` — health record attachment wrapper

### Chat Views (8 files)
- `AIDoctor/AI/Chat/Views/AIConversationView.swift` — main chat UI
- `AIDoctor/AI/Chat/Views/ChatCompanionView.swift` — chat session wrapper
- `AIDoctor/AI/Chat/Views/MessageBubble.swift` — individual message rendering
- `AIDoctor/AI/Chat/Views/AIInputView.swift` — user input bar
- `AIDoctor/AI/Chat/Views/MetadataView.swift` — source/evidence display
- `AIDoctor/AI/Chat/Views/AttachmentPreviewBar.swift` — attachment thumbnails
- `AIDoctor/AI/Chat/Views/AttachmentDetailView.swift` — full attachment view
- `AIDoctor/AI/Chat/Views/TypingIndicator.swift` — streaming indicator

### Tools (3 files)
- `AIDoctor/AI/Tools/HealthTools.swift` — 6 health tools + metadata types
- `AIDoctor/AI/Tools/DisplayMedicationTool.swift` — medication display tool

### Research Mode (13 files)
- `AIDoctor/AI/ResearchMode/ResearcherAgent.swift` — research orchestrator
- `AIDoctor/AI/ResearchMode/Tools/StartResearchTool.swift`
- `AIDoctor/AI/ResearchMode/Tools/SearchMedicalEvidenceTool.swift`
- `AIDoctor/AI/ResearchMode/Tools/ReadEvidenceTool.swift`
- `AIDoctor/AI/ResearchMode/Tools/ReasonEvidenceTool.swift`
- `AIDoctor/AI/ResearchMode/Tools/SearchHealthProfileTool.swift`
- `AIDoctor/AI/ResearchMode/Tools/CompleteResearchTool.swift`
- `AIDoctor/AI/ResearchMode/Tools/TestWearableBiomarkersTool.swift`
- `AIDoctor/AI/ResearchMode/Tools/TestLabResultsTool.swift`
- `AIDoctor/AI/ResearchMode/Tools/TestMedicalRecordsTool.swift`
- `AIDoctor/AI/ResearchMode/Tools/TestHealthJournalTool.swift`
- `AIDoctor/AI/ResearchMode/Tools/TestMedicalHistoryTool.swift`
- `AIDoctor/AI/ResearchMode/Tools/TestTreatmentHistoryTool.swift`

### Medication (4 files)
- `AIDoctor/Care/Medication/Services/MedicationAIService.swift` — structured medication lookup
- `AIDoctor/Care/Medication/Services/MedicationExtractionService.swift` — vision-based extraction
- `AIDoctor/Care/Medication/Models/MedicationModels.swift` — data models
- `AIDoctor/Care/Medication/Models/ExtractMedication.swift` — extraction schema model

### Document Processing (4 files)
- `AIDoctor/Storage/Aggregator/DocumentManager.swift` — document management
- `AIDoctor/Storage/Aggregator/DocumentAnalysisService.swift` — AI-powered analysis
- `AIDoctor/Storage/Aggregator/DocumentModels.swift` — document data models
- `AIDoctor/Storage/Aggregator/DocumentAnalysisModels.swift` — analysis result models

### Health Profile (2 files)
- `AIDoctor/HealthProfile/Services/HealthProfileSummaryService.swift` — AI summaries
- `AIDoctor/HealthProfile/Models/HealthProfileSummaryModels.swift` — summary types

### Other (3 files)
- `AIDoctor/Services/AIDoctorAPI.swift` — backend API client
- `AIDoctor/Journal/Journal.swift` — journal with AI image analysis
- `AIDoctor/HealthQuestionnaire/Questionary.swift` — questionnaire flow

**Total: ~45 files** import AISDK across the codebase.

---

## 10. Health Context Injection

Before each conversation, the app assembles the user's complete health profile into a structured markdown string and injects it as a system message:

```swift
// In createNewSession():
await healthProfile.ensureUnifiedDataAvailable()
let healthContext = healthProfile.asContext()
let healthProfileMsg = ChatMessage(message: .system(content: .text(healthContext)))
newSession.messages.append(healthProfileMsg)
```

The `asContext()` method generates structured content with XML-like section tags, covering:
- Personal information (name, DOB, height, weight, BMI)
- Questionnaire responses
- Assessment predictions
- Active health plans
- Recent journal entries
- Body vitals and biomarkers
- Medical history (diagnoses, surgeries, allergies)
- Current treatments and medications
- Lifestyle factors
- Uploaded documents (metadata only, not content)
- Data source provenance (UserSession, Firestore, HealthKit, FHIR) with timestamps

This context string can be large (thousands of tokens) and is critical for personalized AI responses.

---

## 11. Session Persistence

Chat sessions are stored in Firestore under `users/{userId}/chat_sessions/{sessionId}`:

```swift
struct ChatSession: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var createdAt: Date
    var lastModified: Date
    var title: String
    var messages: [ChatMessage]
}
```

Session lifecycle:
1. **Created in memory** — not saved until first user message (`unsavedSession` pattern)
2. **Auto-titled** — after first exchange, a title is generated using GPT-5-nano
3. **Persisted** — saved to Firestore on first user message, updated after each exchange
4. **Real-time synced** — Firestore snapshot listeners keep the session list current
5. **Cached** — last session ID stored in UserDefaults for fast cold-start resume

The app supports loading the last session by ID (fast path) or querying the most recent by timestamp (fallback).

---

## 12. Error Handling

### Error Flow

When a stream fails:
1. Partial assistant content is preserved (`isPending` set to false, content saved)
2. Token reservations are rolled back for paid users
3. Chat usage quotas are decremented for free users
4. `lastFailedAssistant` is set to show a `RetryErrorCard` in the UI
5. `AgentState` transitions to `.error(AIError)`
6. Error is reported to Sentry, Crashlytics, and PostHog

### Observability Stack

| Service | What it tracks |
|---|---|
| **Sentry** | AI chat transactions, error details, memory checkpoints, performance spans |
| **Crashlytics** | Feature usage logs, AI interaction success/failure, session metadata |
| **PostHog** | LLM analytics (model, latency, success/failure), feature engagement |
| **Custom** | `MetadataTracker` for tool execution, `TokenEstimator` for usage |

---

## 13. Performance and Memory Management

- **LRU Markdown Cache** (capacity: 50) — prevents re-rendering of already-processed markdown
- **Message Trimming** — max 100 messages kept in memory per session; older messages are trimmed on load, preserving system messages
- **Emergency Cleanup** — on memory warnings (`MemoryManager`), the cache is cleared and message arrays are trimmed
- **Lazy Session Creation** — sessions are not persisted until the first user message, preventing empty sessions
- **Listener Cleanup** — Firebase listeners are removed in `deinit` and before creating new ones to prevent leaks

---

## 14. Research Mode (Experimental)

The `ResearcherAgent` wraps `ExperimentalResearchAgent` from the SDK with a systematic medical research workflow:

```swift
class ResearcherAgent {
    private let agent: ExperimentalResearchAgent

    init() {
        let researchTools: [Tool.Type] = [
            StartResearchTool.self,
            SearchMedicalEvidenceToolR.self,
            ReadEvidenceTool.self,
            ReasonEvidenceTool.self,
            SearchHealthProfileTool.self,
            CompleteResearchTool.self,
            TestWearableBiomarkersTool.self,
            TestLabResultsTool.self,
            TestMedicalRecordsTool.self,
            TestHealthJournalTool.self,
            TestMedicalHistoryTool.self,
            TestTreatmentHistoryTool.self
        ]
        // ... initialization with research-specific system prompt
    }
}
```

The research workflow follows a structured process: start research -> gather evidence -> read/reason -> search health data -> complete with report. Each tool returns metadata that accumulates into a final report with citations.

---

## 15. Voice Mode

The app includes a voice interaction mode using `AISDKVoice`. It has its own view hierarchy (`AgentView`, `ChatView`, `ConnectionView`, `ActionBarView`) and session management (`ChatContext`). Voice mode uses the same underlying Agent but adds speech recognition and synthesis layers.

---

## 16. What AISDK v2 Must Preserve

### Critical Interfaces

These are the SDK surfaces that the app's 45+ files depend on. Breaking changes here require migration across the entire codebase:

1. **`Agent` class** — initialization with provider + tools + instructions, `sendStream()`, `setMessages()`, `onStateChange`, `addCallbacks()`
2. **`ChatMessage`** — Codable, role variants, `isPending`, `feedback`, `attachments`, `displayContent`, `id`
3. **`Tool` protocol** — `name`, `description`, `@Parameter`, `execute() -> (content, metadata?)`
4. **`OpenAIProvider`** — `sendChatCompletion()`, `sendChatCompletionStream()`, `generateObject()`
5. **`ChatCompletionRequest`** — model, messages, responseFormat, maxTokens, temperature, stream
6. **`LLMModelAdapter`** — capabilities, token limits, provider, tier
7. **`JSONSchemaModel` / `@Field`** — structured output generation
8. **`AgentState`** — observable enum for UI binding
9. **`ToolMetadata`** — protocol for typed tool result metadata
10. **`MetadataTracker`** — callback registration for tool execution tracking
11. **`Attachment`** — file/image attachment types on messages
12. **`UserContent.Part`** — multimodal message content (.text, .imageURL)

### Known Limitations and Workarounds in v1

- `GeneralSearchTool` returns simulated/placeholder data — needs real search integration
- `ManageHealthEventTool` and `ManageHealthReportTool` use simulated delays — tool results are mocked
- `SearchMedicalEvidenceTool` is commented out in the main chat agent tools list
- `ClaudeProvider` exists but is not actively used
- Research mode is experimental and not exposed to all users
- Voice mode connection details suggest LiveKit integration that may be incomplete
- Token tracking uses `TokenEstimator` which is an approximation, not exact counts from the provider
- The agent's `setMessages()` must be called before each `sendStream()` to keep context in sync — this is a manual step that could be error-prone

### Opportunities for v2

- Unified provider abstraction (currently OpenAI-specific in practice)
- Built-in token tracking from provider responses rather than client-side estimation
- First-class session management (currently the app handles persistence manually)
- Improved streaming lifecycle (automatic pending message management)
- Better error typing and recovery patterns
- Real tool implementations replacing simulated ones
- MCP (Model Context Protocol) support if applicable
- Multi-provider routing (select model per-task automatically)

---

## 17. Summary

The AISDK v1 is deeply integrated into AIDoctor across 45+ files spanning chat, tools, medication services, research, document processing, health profiles, and views. The core pattern is:

1. An `Agent` is initialized with an `OpenAIProvider`, a set of `Tool` types, and system instructions
2. The user's health profile is assembled into context and injected as a system message
3. User messages are streamed through `agent.sendStream()`, yielding partial `ChatMessage` objects
4. The agent may call tools during a response, which execute async operations and return results
5. Completed messages are persisted to Firestore in `ChatSession` documents
6. State changes are observed via `AgentState` to drive the UI
7. For non-chat use cases, `ChatCompletionRequest` + `generateObject()` provides structured outputs

The v2 SDK should preserve these core patterns while addressing the limitations noted above. The 45-file integration footprint means that API changes will have a wide blast radius — backward compatibility or clear migration paths are essential.
