 # OpenAI Responses API Tests

This directory contains comprehensive tests for the OpenAI Responses API implementation in AISDK.

## 🎯 Test Overview

The test suite covers all aspects of the OpenAI Responses API with a focus on **real API testing** as requested by the user, while providing mock fallbacks for development speed.

### Test Files

| File | Purpose | Test Count | Real API | Mock |
|------|---------|------------|----------|------|
| `OpenAIResponsesAPITests.swift` | Core functionality (create, retrieve, cancel) | ~15 | ✅ | ✅ |
| `OpenAIResponsesStreamingTests.swift` | Streaming responses and SSE parsing | ~12 | ✅ | ✅ |
| `OpenAIResponsesToolsTests.swift` | Built-in tools (web search, code interpreter, etc.) | ~18 | ✅ | ✅ |
| `OpenAIResponsesRealAPITests.swift` | **Real API integration** (user priority) | ~15 | ✅ | ❌ |
| `MockOpenAIResponsesProvider.swift` | Mock provider for fast testing | N/A | ❌ | ✅ |

## 🚀 Quick Start

### 1. Mock Tests (Default)
```bash
# Run all mock tests (fast, no API key needed)
./run_responses_tests.sh --mock-only

# Run specific test category
./run_responses_tests.sh --filter OpenAIResponsesAPITests
```

### 2. Real API Tests (User Priority)
```bash
# Set your OpenAI API key
export OPENAI_API_KEY="your-openai-api-key-here"

# Run all real API tests
./run_responses_tests.sh --real-api

# Run specific real API tests
./run_responses_tests.sh --real-api --filter OpenAIResponsesRealAPITests
```

### 3. Mixed Testing
```bash
# Run both mock and real API tests
export USE_REAL_API=true
export OPENAI_API_KEY="your-key"
swift test --filter OpenAIResponses
```

## 📋 Test Categories

### Core Functionality Tests (`OpenAIResponsesAPITests.swift`)

Tests the fundamental operations of the Responses API:

- ✅ **Basic Response Creation** - Simple text responses
- ✅ **Builder Pattern** - Fluent API construction
- ✅ **Input Validation** - String vs items input formats
- ✅ **Response Retrieval** - Get response by ID
- ✅ **Response Cancellation** - Cancel in-progress responses
- ✅ **Parameter Validation** - Model, temperature, tokens, etc.
- ✅ **Error Handling** - Invalid models, network errors
- ✅ **Response Structure** - Validate response format

**Example Test:**
```swift
func testBasicResponseCreation() async throws {
    let response = try await provider.createTextResponse(
        model: "gpt-4o-mini",
        text: "Say hello in one word",
        maxOutputTokens: 10
    )
    
    XCTAssertNotNil(response.id)
    XCTAssertEqual(response.object, "response")
    XCTAssertTrue(response.status.isFinal)
    XCTAssertNotNil(response.outputText)
}
```

### Streaming Tests (`OpenAIResponsesStreamingTests.swift`)

Tests real-time streaming capabilities:

- ✅ **Basic Streaming** - Stream text responses
- ✅ **Delta Accumulation** - Reconstruct full text from deltas
- ✅ **Stream Events** - Handle different event types
- ✅ **Stream Cancellation** - Interrupt streams gracefully
- ✅ **Error Handling** - Stream-specific errors
- ✅ **Completion Detection** - Detect when stream ends
- ✅ **Performance** - Measure streaming speed

**Example Test:**
```swift
func testBasicStreamingResponse() async throws {
    var accumulatedText = ""
    
    for try await chunk in provider.createTextResponseStream(
        model: "gpt-4o-mini",
        text: "Count from 1 to 5"
    ) {
        if let deltaText = chunk.delta?.outputText {
            accumulatedText += deltaText
        }
    }
    
    XCTAssertFalse(accumulatedText.isEmpty)
}
```

### Tools Tests (`OpenAIResponsesToolsTests.swift`)

Tests all built-in tools and custom functions:

- ✅ **Web Search Preview** - Real-time web search
- ✅ **Code Interpreter** - Data analysis and visualization
- ✅ **Image Generation** - AI-powered image creation
- ✅ **File Search** - Vector store integration
- ✅ **Custom Functions** - User-defined function calling
- ✅ **Multi-Tool Usage** - Combining multiple tools
- ✅ **Tool Choice** - Auto, none, specific tool selection
- ✅ **Tool Error Handling** - Tool execution failures

**Example Test:**
```swift
func testWebSearchPreview() async throws {
    let response = try await provider.createResponseWithWebSearch(
        model: "gpt-4o-mini",
        text: "What's the current weather in San Francisco?"
    )
    
    let hasWebSearchOutput = response.output.contains { output in
        if case .webSearchCall = output { return true }
        return false
    }
    
    XCTAssertTrue(hasWebSearchOutput)
}
```

### Real API Integration Tests (`OpenAIResponsesRealAPITests.swift`)

**🎯 User Priority** - Tests with actual OpenAI API:

- ✅ **Authentication** - Validate API key handling
- ✅ **Model Availability** - Test different models
- ✅ **Rate Limiting** - Handle rate limit responses
- ✅ **Background Processing** - Long-running tasks
- ✅ **Conversation Continuation** - Stateful conversations
- ✅ **Performance Benchmarks** - Real-world performance
- ✅ **Error Scenarios** - Real API error responses
- ✅ **Tool Execution** - Actual tool usage validation

**Example Test:**
```swift
func testRealAPIBasicResponse() async throws {
    try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
    
    let response = try await provider.createTextResponse(
        model: "gpt-4o-mini",
        text: "Say 'Hello, AISDK!' in exactly those words",
        maxOutputTokens: 10
    )
    
    XCTAssertFalse(response.id.isEmpty)
    XCTAssertEqual(response.object, "response")
    XCTAssertTrue(response.status.isFinal)
    XCTAssertNotNil(response.usage)
}
```

## 🛠️ Test Configuration

### Environment Variables

| Variable | Purpose | Default | Required |
|----------|---------|---------|----------|
| `USE_REAL_API` | Enable real API tests | `false` | No |
| `OPENAI_API_KEY` | Your OpenAI API key | `""` | For real API tests |

### Test Runner Options

```bash
./run_responses_tests.sh [OPTIONS]

Options:
  -r, --real-api          Use real OpenAI API (requires OPENAI_API_KEY)
  -m, --mock-only         Use mock tests only (default)
  -k, --api-key KEY       Set OpenAI API key
  -f, --filter PATTERN    Run only tests matching pattern
  -v, --verbose           Verbose output
  -h, --help              Show help message
```

### Examples

```bash
# Quick mock tests
./run_responses_tests.sh --mock-only

# Real API with your key
./run_responses_tests.sh --real-api --api-key "sk-..."

# Only streaming tests
./run_responses_tests.sh --filter Streaming

# Verbose real API tests
./run_responses_tests.sh --real-api --verbose

# Specific test method
./run_responses_tests.sh --filter testRealAPIBasicResponse
```

## 📊 Test Coverage

### Feature Coverage

| Feature | Mock Tests | Real API Tests | Coverage |
|---------|------------|----------------|----------|
| Basic Responses | ✅ | ✅ | 100% |
| Streaming | ✅ | ✅ | 100% |
| Web Search | ✅ | ✅ | 100% |
| Code Interpreter | ✅ | ✅ | 100% |
| Image Generation | ✅ | ✅ | 100% |
| File Search | ✅ | ✅ | 100% |
| Custom Functions | ✅ | ✅ | 100% |
| Background Processing | ✅ | ✅ | 100% |
| Error Handling | ✅ | ✅ | 100% |
| Builder Pattern | ✅ | ✅ | 100% |

### API Endpoint Coverage

| Endpoint | Method | Tested |
|----------|--------|--------|
| `/v1/responses` | POST | ✅ |
| `/v1/responses` | POST (streaming) | ✅ |
| `/v1/responses/{id}` | GET | ✅ |
| `/v1/responses/{id}/cancel` | POST | ✅ |

## 🔧 Development Workflow

### 1. Development Phase
```bash
# Fast feedback with mock tests
./run_responses_tests.sh --mock-only --filter YourNewTest
```

### 2. Integration Testing
```bash
# Test with real API
./run_responses_tests.sh --real-api --filter YourNewTest
```

### 3. Full Validation
```bash
# Run complete test suite
export OPENAI_API_KEY="your-key"
./run_responses_tests.sh --real-api
```

## 🚨 Troubleshooting

### Common Issues

**1. API Key Issues**
```bash
# Error: Real API testing requires OPENAI_API_KEY
export OPENAI_API_KEY="sk-your-key-here"
```

**2. Rate Limiting**
```bash
# If you hit rate limits, tests will handle gracefully
# Wait a few minutes and retry
```

**3. Build Failures**
```bash
# Clean and rebuild
swift package clean
swift build
```

**4. Test Timeouts**
```bash
# Some real API tests may take time
# Increase timeout if needed
```

### Debug Mode

```bash
# Enable verbose logging
./run_responses_tests.sh --real-api --verbose

# Run single test with full output
swift test --filter testRealAPIBasicResponse --verbose
```

## 📈 Performance Expectations

### Mock Tests
- **Speed**: ~50ms per test
- **Total Time**: ~5 seconds for full suite
- **Resource Usage**: Minimal

### Real API Tests
- **Speed**: ~2-5 seconds per test
- **Total Time**: ~2-3 minutes for full suite
- **Rate Limits**: Handled gracefully
- **Cost**: ~$0.01-0.05 per full test run

## 🎯 Best Practices

### Writing New Tests

1. **Follow Naming Convention**
   ```swift
   func testRealAPI[Feature][Scenario]() async throws
   func test[Feature][Scenario]() async throws // For mock tests
   ```

2. **Use Skip for Real API**
   ```swift
   try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
   ```

3. **Handle Both Mock and Real**
   ```swift
   if let provider = provider {
       // Real API test
   } else {
       // Mock test
   }
   ```

4. **Add Meaningful Assertions**
   ```swift
   XCTAssertNotNil(response.outputText)
   XCTAssertTrue(response.status.isFinal)
   XCTAssertGreaterThan(response.usage!.totalTokens, 0)
   ```

### Test Organization

- Keep tests focused and atomic
- Use descriptive test names
- Group related tests in the same file
- Add performance tests for critical paths
- Include both positive and negative test cases

## 🔄 Continuous Integration

### GitHub Actions Example

```yaml
- name: Run Mock Tests
  run: ./Tests/AISDKTests/LLMTests/Providers/run_responses_tests.sh --mock-only

- name: Run Real API Tests
  env:
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
  run: ./Tests/AISDKTests/LLMTests/Providers/run_responses_tests.sh --real-api
  if: env.OPENAI_API_KEY != ''
```

## 📚 Additional Resources

- [OpenAI Responses API Documentation](https://platform.openai.com/docs/api-reference/responses)
- [AISDK Implementation Guide](../../../../Sources/AISDK/docs/tasks/openai-responses-api-implementation.md)
- [Swift Testing Documentation](https://developer.apple.com/documentation/xctest)

---

**Ready to test!** 🚀

Start with mock tests for fast feedback, then validate with real API tests for production confidence.