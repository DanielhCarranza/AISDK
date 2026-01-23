# fn-1.15 Task 1.12: MockAILanguageModel

## Description
Implement MockAILanguageModel - a comprehensive mock implementation of the AILanguageModel protocol for testing. The mock supports configurable responses, tool calls, streaming, error injection, and sequential responses for multi-call test scenarios.

## Acceptance
- [x] Implements AILanguageModel protocol (generateText, streamText, generateObject, streamObject)
- [x] Provides factory methods for common test scenarios (withResponse, withToolCall, failing, withSlowResponse)
- [x] Supports request tracking (requestCount, lastTextRequest, lastObjectRequestType)
- [x] Thread-safe state management for concurrent tests
- [x] Memory-safe streaming using SafeAsyncStream
- [x] Includes SequentialMockAILanguageModel for multi-response test scenarios
- [x] All tests pass

## Done summary
# fn-1.15 Summary

Created MockAILanguageModel at Tests/AISDKTests/Mocks/MockAILanguageModel.swift implementing the AILanguageModel protocol for testing.

## Features
- Factory methods: withResponse, withToolCall, withToolCalls, withSlowResponse, failing, withStreamEvents, withObject, withProvider, withSequence
- Configurable: responseText, toolCalls, streamEvents, usage, finishReason, delay, errorToThrow
- Tracking: requestCount, lastTextRequest, lastObjectRequestType
- Thread-safe using NSLock with sync-only lock scope
- SafeAsyncStream for memory-safe streaming
- SequentialMockAILanguageModel for different responses per call

## Tests
15 tests pass in MockAILanguageModelTests validating all functionality.
## Evidence
- Commits: 3023cd9
- Tests: command, passed, failed
- PRs: