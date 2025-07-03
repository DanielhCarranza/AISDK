# FEAT-MultiProviderModelsIntegration

## Task ID
FEAT-MultiProviderModelsIntegration

## Problem Statement
The AISDK has an architectural mismatch that prevents clean, simple usage:

**Current Issues**:
- Agent accepts legacy `LLMModel` structs instead of LLM providers
- All providers (OpenAIProvider, AnthropicService, GeminiService) take string model names instead of enum/static model identifiers
- No provider defaults or simple model selection (`.o3`, `.gpt4o`, `.sonnet37`, `.gemini25Pro`)
- Rich model metadata (OpenAIModels, AnthropicModels, GeminiModels) is disconnected from actual usage
- Inconsistent patterns across providers

**Target Usage** (what we want):
```swift
// Simple LLM usage - all providers follow same pattern
let openai = OpenAIProvider(model: .o3)
let openai = OpenAIProvider() // uses smart default (e.g., .gpt4o)

let anthropic = AnthropicService(model: .sonnet37) 
let anthropic = AnthropicService() // uses smart default (e.g., .sonnet37)

let gemini = GeminiService(model: .gemini25Pro)
let gemini = GeminiService() // uses smart default (e.g., .gemini25Flash)

// Agent with provider (provider-centric) - future integration
let agent = Agent(llm: OpenAIProvider())
let agent = Agent(llm: OpenAIProvider(), model: .gpt4oMini)

// All providers work the same way
let agent = Agent(llm: AnthropicService(), model: .sonnet4)
let agent = Agent(llm: GeminiService(), model: .gemini20Flash)
```

**Goal**: Create a provider-centric architecture where LLM providers are the main abstraction with simple model identifiers and smart defaults. Focus on OpenAI, Anthropic, and Gemini providers first. Agent integration comes later.

## Proposed Implementation

### Phase 1: Provider-Centric Foundation (All Providers)
1. **Create Simple Model Enums for All Providers**
   - Add `OpenAIModel` enum with cases: `.o3`, `.gpt4o`, `.gpt4oMini`, etc.
   - Add `AnthropicModel` enum with cases: `.sonnet4`, `.sonnet37`, `.haiku35`, etc.
   - Add `GeminiModel` enum with cases: `.gemini25Pro`, `.gemini25Flash`, `.gemini20Flash`, etc.
   - Keep rich metadata system internal for optimization

2. **Enhance All Providers with Model Awareness**
   - **OpenAIProvider**: Add `init(model: OpenAIModel? = nil)` with smart default
   - **AnthropicService**: Add `init(model: AnthropicModel? = nil)` with smart default  
   - **GeminiService**: Add `init(model: GeminiModel? = nil)` with smart default
   - Update all methods to use internal model metadata for optimization
   - Maintain string model name compatibility

### Phase 2: Agent Provider Integration
1. **Update Agent to Accept LLM Providers**
   - Add new initializer: `Agent(llm: LLM, model: OpenAIModel? = nil)`
   - Provider supplies the default model, optional override
   - Remove dependency on legacy `LLMModel` struct

2. **Provider-Aware Features** 
   - Agent automatically uses provider's capabilities
   - Model override uses provider's model enum types
   - Token limits and optimization from provider's model metadata

### Phase 3: Multi-Provider Foundation
1. **Establish Provider Pattern**
   - Create provider protocol with default model concept
   - Each provider has its own model enum
   - Agent works consistently across all providers

2. **Migration and Documentation**
   - Update all examples to use provider-centric approach
   - Clear migration path from legacy system
   - Future-ready for Anthropic, Gemini, etc.

## Components Involved
- `Sources/AISDK/LLMs/OpenAI/OpenAIProvider.swift`
- `Sources/AISDK/LLMs/OpenAI/OpenAIModels.swift`
- `Sources/AISDK/LLMs/Anthropic/AnthropicService.swift`
- `Sources/AISDK/LLMs/Anthropic/AnthropicModels.swift`
- `Sources/AISDK/LLMs/Gemini/GeminiService.swift` (protocol + future implementation)
- `Sources/AISDK/LLMs/Gemini/GeminiModels.swift`
- `Sources/AISDK/Agents/Agent.swift` (future integration)
- `Sources/AISDK/LLMs/AgenticModels.swift` (deprecation path)
- `Sources/AISDK/LLMs/LLMModelProtocol.swift`
- Documentation files
- Example files and tests

## Dependencies
- Understanding of current API usage patterns across the codebase
- ConfigManager for API key management
- Existing LLMProvider protocol structure
- Agent callback and state management system

## Implementation Checklist

### Phase 1: Provider-Centric Foundation (All Providers) ✅ COMPLETE

**What was accomplished:**
- All three providers now accept `LLMModelProtocol` models with smart defaults
- Leveraged existing `OpenAIModels`, `AnthropicModels`, `GeminiModels` static properties (no reinventing the wheel!)
- Clean, consistent API across all providers
- Backward compatibility maintained 
- No breaking changes to existing code

**Usage now available:**
```swift
// All providers follow the same clean pattern
let openai = OpenAIProvider(model: OpenAIModels.o3)
let openai = OpenAIProvider() // defaults to .gpt4o

let anthropic = AnthropicService(model: AnthropicModels.sonnet4)
let anthropic = AnthropicService() // defaults to .sonnet37

let gemini = GeminiProvider(model: GeminiModels.gemini25Pro)  
let gemini = GeminiProvider() // defaults to .gemini25Flash
```
**OpenAI Provider:** ✅
- [x] ~~Create `OpenAIModel` enum~~ **Used existing OpenAIModels static properties**
- [x] Add model-to-metadata mapping using existing OpenAIModels system  
- [x] Add `OpenAIProvider.init(model: LLMModelProtocol? = nil)` with smart default (.gpt4o)
- [x] Add legacy initializer for backward compatibility
- [x] Add API key resolution: parameter → environment → empty
- [x] Maintain backward compatibility with existing API

**Anthropic Provider:** ✅  
- [x] ~~Create `AnthropicModel` enum~~ **Used existing AnthropicModels static properties**
- [x] Add model-to-metadata mapping using existing AnthropicModels system
- [x] Add `AnthropicService.init(model: LLMModelProtocol? = nil)` with smart default (.sonnet37)
- [x] Add legacy initializer for backward compatibility  
- [x] Add API key resolution: parameter → environment → empty
- [x] Maintain backward compatibility with existing API

**Gemini Provider:** ✅
- [x] ~~Create `GeminiModel` enum~~ **Used existing GeminiModels static properties**
- [x] Add model-to-metadata mapping using existing GeminiModels system
- [x] Add concrete GeminiProvider class implementing GeminiService protocol
- [x] Add `GeminiProvider.init(model: LLMModelProtocol? = nil)` with smart default (.gemini25Flash)
- [x] Add legacy initializer for backward compatibility
- [x] Implement all GeminiService protocol methods with model metadata support

### Phase 2: Agent Provider Integration
- [ ] Add new Agent initializer: `Agent(llm: LLM, model: OpenAIModel? = nil)`
- [ ] Add generic Agent initializer: `Agent<T: LLMProvider>(llm: T, model: T.Model? = nil)` for future
- [ ] Update Agent to use provider's model capabilities automatically
- [ ] Remove Agent dependency on legacy `LLMModel` struct
- [ ] Add backward compatibility bridge for existing Agent init
- [ ] Update token limit handling using provider's model metadata

### Phase 3: Multi-Provider Foundation
- [ ] Create `LLMProvider` protocol with associated `Model` type
- [ ] Update `LLM` protocol to include default model concept
- [ ] Establish pattern for provider-specific model enums
- [ ] Update Agent to work generically with any provider
- [ ] Create migration guide from legacy system
- [ ] Update all example code to use provider-centric approach

### Phase 4: Testing & Polish
- [ ] Add integration tests for new provider-centric API
- [ ] Test backward compatibility with legacy patterns
- [ ] Test model override functionality
- [ ] Performance testing with model metadata optimization
- [ ] Update documentation and examples
- [ ] Add deprecation warnings for legacy patterns

## Verification Steps

### Automated Tests
1. **Integration Tests**: Verify all new API patterns work with real models
   ```bash
   swift test --filter "OpenAIModelsIntegrationTests"
   ```

2. **Backward Compatibility Tests**: Ensure legacy patterns still work
   ```bash
   swift test --filter "BackwardCompatibilityTests"
   ```

3. **Model Validation Tests**: Test model discovery and validation
   ```bash
   swift test --filter "ModelValidationTests"
   ```

### Manual Verification
1. **Usage Pattern Tests**: 
   - Simple provider usage: `OpenAIProvider(model: .o3)`
   - Agent with provider: `Agent(llm: OpenAIProvider())`
   - Agent with model override: `Agent(llm: OpenAIProvider(), model: .gpt4oMini)`
   - Legacy compatibility: `Agent(model: AgenticModels.gpt4)` with deprecation warning

2. **Documentation Examples**: All code examples in docs should compile and run

3. **Real-world Integration**: Test with existing demo applications and ChatManager

## Decision Authority
- **Independent Decisions**: API design choices, implementation details, method naming
- **User Input Required**: Breaking changes to public API, deprecation timeline
- **Blocking Decisions**: Changes to core Agent behavior, removal of backward compatibility

## Questions/Uncertainties

### Blocking
- **API Key Management**: Should we prioritize model metadata, environment variables, or constructor parameters for API keys?
- **Provider Selection**: Should Agent automatically select provider based on model, or require explicit provider specification?
- **Breaking Changes**: What level of breaking changes are acceptable for the migration?

### Non-blocking  
- **Performance**: Should we cache model metadata or compute it dynamically?
- **Validation**: How strict should model availability validation be?
- **Deprecation Timeline**: When should legacy patterns be fully removed?

**Working Assumptions**:
- **Provider Defaults**: OpenAI (.gpt4o), Anthropic (.sonnet37), Gemini (.gemini25Flash)
- **API Key Resolution**: constructor parameter → environment → ConfigManager (all providers)
- **Future Agent Integration**: Agents will accept providers as primary abstraction, not models directly  
- **Model Enums**: Provider-specific enum types for clean autocomplete (.o3, .sonnet4, .gemini25Pro)
- **Rich Metadata**: Remains internal for optimization, exposed through simple enums
- **Backward Compatibility**: Maintain string model name support during transition
- **GeminiService**: Create concrete GeminiProvider class implementing the protocol
- **Migration Timeline**: 2-3 version deprecation timeline for legacy patterns

## Acceptable Tradeoffs
- **Complexity vs. Power**: Accept slightly more complex model system for significantly better capabilities
- **Migration Effort vs. Long-term Benefits**: Require some migration work for much cleaner long-term API
- **Bundle Size vs. Metadata**: Include comprehensive model metadata despite small size increase
- **Performance vs. Features**: Small initialization overhead for much better model awareness

## Status
Not Started

## Notes
**Design Principles**:
1. **Progressive Enhancement**: New features shouldn't break existing code
2. **Smart Defaults**: Most common use cases should be simple
3. **Power User Support**: Advanced users can access full model metadata
4. **Clear Migration Path**: Legacy → new system should be obvious and documented

**Example Target API**:
```swift
// Simple LLM provider usage - consistent across all providers
let openai = OpenAIProvider(model: .o3)
let openai = OpenAIProvider(model: .gpt4o)  
let openai = OpenAIProvider() // uses smart default (.gpt4o)

let anthropic = AnthropicService(model: .sonnet4)
let anthropic = AnthropicService(model: .sonnet37)
let anthropic = AnthropicService() // uses smart default (.sonnet37)

let gemini = GeminiProvider(model: .gemini25Pro)
let gemini = GeminiProvider(model: .gemini25Flash)
let gemini = GeminiProvider() // uses smart default (.gemini25Flash)

// Direct provider usage - same API across providers
let provider = OpenAIProvider(model: .gpt4o)
let response = try await provider.sendChatCompletion(request: request)

let anthropicProvider = AnthropicService(model: .sonnet37)
let anthropicResponse = try await anthropicProvider.messageRequest(body: request)

let geminiProvider = GeminiProvider(model: .gemini25Flash)
let geminiResponse = try await geminiProvider.generateContentRequest(body: request, model: "gemini-2.5-flash")

// Future: Agent integration (same pattern for all)
// let agent = try Agent(llm: OpenAIProvider())
// let agent = try Agent(llm: AnthropicService(), model: .sonnet4)
// let agent = try Agent(llm: GeminiProvider(), model: .gemini20Flash)

// Legacy compatibility (with deprecation warning)
// let agent = try Agent(model: AgenticModels.gpt4) // ⚠️ Deprecated
``` 