# AISDK Model Testing Guide

This guide shows how to test different OpenAI models with the AISDK test suite using the configurable test runner script.

## Quick Start

The test script automatically detects whether you're passing a model name or test category as the first parameter:

```bash
# Test with o4-mini thinking model
./test_demo.sh o4-mini

# Test thinking capabilities specifically
./test_demo.sh thinking-multimodal

# Test with gpt-4o for multimodal
./test_demo.sh gpt-4o multimodal

# Test all features with gpt-4o-mini
./test_demo.sh gpt-4o-mini all
```

## Test Categories

### LLM Tests (`llm`)
Tests basic language model functionality with configurable models:
- `BasicChatTests.testOpenAIIntegration()` - Tests chat completion with reasoning task
- `StreamingChatTests.testOpenAIIntegration()` - Tests streaming responses

```bash
# Test LLM functionality with different models
./test_demo.sh o4-mini llm
./test_demo.sh gpt-4o llm
./test_demo.sh gpt-4o-mini llm
```

### Multimodal Tests (`multimodal`)
Tests image analysis capabilities:
- `MultimodalTests.testOpenAIImageURL()` - Tests image URL analysis
- `MultimodalTests.testOpenAIImageBase64()` - Tests base64 image analysis using `Tests/Assets/baltolo.webp`
- `MultimodalTests.testOpenAIMultipleImages()` - Tests multi-image comparison

```bash
# Test multimodal capabilities
./test_demo.sh gpt-4o multimodal
./test_demo.sh o4-mini multimodal
```

### Agent Tests (`agent`)
Tests AI agent functionality using the configurable model approach:
- All existing Agent integration tests now use `TEST_MODEL` environment variable

```bash
# Test agent capabilities
./test_demo.sh gpt-4o agent
./test_demo.sh o4-mini agent
```

### Thinking Model Tests (`thinking`)
Automatically sets `TEST_MODEL=o4-mini` and runs LLM tests to specifically test reasoning capabilities:

```bash
# Automatically uses o4-mini for thinking tests
./test_demo.sh thinking
```

### Thinking + Multimodal Tests (`thinking-multimodal`)
Automatically sets `TEST_MODEL=o4-mini` and runs multimodal tests to test reasoning with vision:

```bash
# Test o4-mini with image analysis
./test_demo.sh thinking-multimodal
```

### All Tests (`all`)
Runs the complete test suite with the specified or default model:

```bash
# Run all tests with default model (gpt-4o)
./test_demo.sh

# Run all tests with specific model
./test_demo.sh o4-mini all
```

## Model Capabilities Matrix

| Model | Basic Chat | Streaming | Multimodal | Thinking | Agent |
|-------|------------|-----------|------------|----------|-------|
| `o4-mini` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gpt-4o` | ✅ | ✅ | ✅ | ❌ | ✅ |
| `gpt-4o-mini` | ✅ | ✅ | ✅ | ❌ | ✅ |

## Environment Variables

The tests use these environment variables:

- `OPENAI_API_KEY` - Your OpenAI API key (required)
- `TEST_MODEL` - Model to use for tests (set automatically by script categories)

## OpenRouter Integration Tests

OpenRouter tests run against real OpenRouter models using `OpenRouterClient`.

### Required
- `OPENROUTER_API_KEY` - OpenRouter API key

### Optional
- `OPENROUTER_TEST_MODELS` - Comma-separated model IDs to test
- `OPENROUTER_DEFAULT_MODEL` - Default model for streaming/JSON/reasoning tests
- `OPENROUTER_STREAM_MODEL` - Model ID for streaming test
- `OPENROUTER_TOOL_MODEL` - Model ID for tool-calling test (default: `arcee-ai/trinity-mini:free`)

### OpenRouter Free Tier Model Capabilities

| Model | Chat | Stream | JSON | Reasoning | Tool Calling |
|-------|------|--------|------|-----------|--------------|
| `tngtech/deepseek-r1t2-chimera:free` | ✅ | ✅ | ✅ | ✅ | ❌ No providers |
| `nvidia/nemotron-3-nano-30b-a3b:free` | ✅ | ✅ | ✅ | ✅ | ✅ (`tool_choice: auto` only) |
| `arcee-ai/trinity-mini:free` | ✅ | ✅ | ✅ | ✅ | ✅ Full support |

**Tool Calling Notes:**
- **Trinity Mini** has full tool calling support including specific tool forcing
- **Nemotron** supports tools with `tool_choice: "auto"` but NOT with specific tool forcing
- **DeepSeek R1T2 Chimera** free tier providers don't support tool calling
- The SDK uses `tool_choice: .auto` by default for maximum compatibility

### Examples

```bash
# Run OpenRouter integration tests with default free models
OPENROUTER_API_KEY=your_key_here swift test --filter OpenRouterIntegrationTests

# Override models under test
OPENROUTER_API_KEY=your_key_here \
OPENROUTER_TEST_MODELS="tngtech/deepseek-r1t2-chimera:free,nvidia/nemotron-3-nano-30b-a3b:free" \
swift test --filter OpenRouterIntegrationTests

# Tool calling test (uses Trinity Mini by default)
OPENROUTER_API_KEY=your_key_here \
swift test --filter OpenRouterIntegrationTests.test_tool_calling_with_configured_model

# Override tool model
OPENROUTER_API_KEY=your_key_here \
OPENROUTER_TOOL_MODEL="nvidia/nemotron-3-nano-30b-a3b:free" \
swift test --filter OpenRouterIntegrationTests.test_tool_calling_with_configured_model
```

### CLI Demo

```bash
# Run all demo modes (uses smart model selection)
swift run OpenRouterDemo --mode all

# Run specific modes
swift run OpenRouterDemo --mode chat
swift run OpenRouterDemo --mode tools  # Auto-selects Trinity Mini
swift run OpenRouterDemo --mode tools --model nvidia/nemotron-3-nano-30b-a3b:free

# Show help with model compatibility info
swift run OpenRouterDemo --help
```

## Usage Examples

### Testing o4-mini Thinking Capabilities

```bash
# Method 1: Use thinking category (automatically sets o4-mini)
./test_demo.sh thinking

# Method 2: Manually specify o4-mini
./test_demo.sh o4-mini llm

# Method 3: Test thinking with images
./test_demo.sh thinking-multimodal
```

### Testing Different Models

```bash
# Test gpt-4o with multimodal
./test_demo.sh gpt-4o multimodal

# Test gpt-4o-mini with agents
./test_demo.sh gpt-4o-mini agent

# Test all capabilities with o4-mini
./test_demo.sh o4-mini all
```

### Manual Testing with Environment Variables

You can also manually set the model and run specific tests:

```bash
# Set custom model
export TEST_MODEL=o4-mini

# Run specific test classes
swift test --filter BasicChatTests.testOpenAIIntegration
swift test --filter MultimodalTests.testOpenAI
swift test --filter AgentIntegrationTests
```

## Test Implementation Notes

1. **Configurable Tests**: All integration tests use the `TEST_MODEL` environment variable for flexibility
2. **Model Assertion Handling**: Tests don't assert exact model name matches since OpenAI returns versioned names (e.g., `gpt-4o-2024-08-06`)
3. **Image Loading**: Multimodal tests load images from `Tests/Assets/baltolo.webp` instead of creating them programmatically
4. **Simplified Design**: One test function per category that adapts to any compatible model

## Troubleshooting

### API Key Issues
```bash
export OPENAI_API_KEY=your_key_here
./test_demo.sh o4-mini
```

### Model Not Found (404)
- Verify the model name is correct: `o4-mini`, `gpt-4o`, `gpt-4o-mini`
- Check that your API key has access to the model

### Image Loading Issues
- Ensure `Tests/Assets/baltolo.webp` exists in your test directory
- The tests will skip gracefully if the image can't be loaded

This simplified approach makes it easy to test any OpenAI model across all AISDK capabilities with minimal configuration. 
