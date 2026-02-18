//
//  ResponsesAPIFixtures.swift
//  AISDKTests
//
//  Golden test fixtures for OpenAI Responses API testing
//

import Foundation
@testable import AISDK

/// Golden test fixtures for Responses API
public enum ResponsesAPIFixtures {

    // MARK: - Response Factory Methods

    /// Create a basic response fixture
    public static func makeResponse(
        id: String = "resp_123",
        status: ResponseStatus = .completed,
        text: String = "Hello!",
        model: String = "gpt-4o-mini"
    ) -> ResponseObject {
        ResponseObject(
            id: id,
            object: "response",
            createdAt: 1704067200, // Fixed timestamp for testing
            model: model,
            status: status,
            output: [
                .message(ResponseOutputMessage(
                    id: "msg_\(id)",
                    role: "assistant",
                    content: [.outputText(ResponseOutputText(text: text))]
                ))
            ],
            usage: ResponseUsage(
                inputTokens: 10,
                outputTokens: 20,
                totalTokens: 30,
                inputTokensDetails: nil,
                outputTokensDetails: nil
            ),
            previousResponseId: nil,
            metadata: nil,
            incompleteDetails: nil,
            error: nil,
            instructions: nil,
            temperature: 1.0,
            topP: 1.0,
            maxOutputTokens: nil,
            toolChoice: nil,
            tools: nil,
            parallelToolCalls: true,
            reasoning: nil,
            truncation: nil,
            text: ResponseTextConfig(format: ResponseTextFormat(type: "text")),
            user: nil,
            store: false,
            serviceTier: nil
        )
    }

    /// Create a response with function call output
    public static func makeToolCallResponse(
        id: String = "resp_456",
        toolCallId: String = "call_abc",
        functionName: String = "get_weather",
        arguments: String = "{\"location\":\"Tokyo\"}"
    ) -> ResponseObject {
        ResponseObject(
            id: id,
            object: "response",
            createdAt: 1704067200,
            model: "gpt-4o-mini",
            status: .completed,
            output: [
                .functionCall(ResponseOutputFunctionCall(
                    id: "fc_123",
                    name: functionName,
                    arguments: arguments,
                    callId: toolCallId,
                    status: "completed"
                ))
            ],
            usage: ResponseUsage(
                inputTokens: 15,
                outputTokens: 25,
                totalTokens: 40,
                inputTokensDetails: nil,
                outputTokensDetails: nil
            ),
            previousResponseId: nil,
            metadata: nil,
            incompleteDetails: nil,
            error: nil,
            instructions: nil,
            temperature: 1.0,
            topP: 1.0,
            maxOutputTokens: nil,
            toolChoice: nil,
            tools: nil,
            parallelToolCalls: true,
            reasoning: nil,
            truncation: nil,
            text: nil,
            user: nil,
            store: false,
            serviceTier: nil
        )
    }

    /// Create a response with web search call output
    public static func makeWebSearchResponse(
        id: String = "resp_websearch",
        query: String = "Latest AI news",
        result: String = "Recent developments in AI include..."
    ) -> ResponseObject {
        ResponseObject(
            id: id,
            object: "response",
            createdAt: 1704067200,
            model: "gpt-4o-mini",
            status: .completed,
            output: [
                .message(ResponseOutputMessage(
                    id: "msg_ws_123",
                    role: "assistant",
                    content: [.outputText(ResponseOutputText(text: "Based on my web search: \(result)"))]
                )),
                .webSearchCall(ResponseOutputWebSearchCall(
                    id: "ws_123",
                    query: query,
                    result: result,
                    status: "completed"
                ))
            ],
            usage: ResponseUsage(
                inputTokens: 10,
                outputTokens: 50,
                totalTokens: 60,
                inputTokensDetails: nil,
                outputTokensDetails: nil
            ),
            previousResponseId: nil,
            metadata: nil,
            incompleteDetails: nil,
            error: nil,
            instructions: nil,
            temperature: 1.0,
            topP: 1.0,
            maxOutputTokens: nil,
            toolChoice: nil,
            tools: [.webSearchPreview],
            parallelToolCalls: true,
            reasoning: nil,
            truncation: nil,
            text: nil,
            user: nil,
            store: false,
            serviceTier: nil
        )
    }

    /// Create a response with code interpreter call
    public static func makeCodeInterpreterResponse(
        id: String = "resp_code",
        code: String = "print('Hello, World!')",
        result: String = "Hello, World!"
    ) -> ResponseObject {
        ResponseObject(
            id: id,
            object: "response",
            createdAt: 1704067200,
            model: "gpt-4o-mini",
            status: .completed,
            output: [
                .message(ResponseOutputMessage(
                    id: "msg_ci_123",
                    role: "assistant",
                    content: [.outputText(ResponseOutputText(text: "I've executed the code: \(result)"))]
                )),
                .codeInterpreterCall(ResponseOutputCodeInterpreterCall(
                    id: "ci_123",
                    code: code,
                    result: result,
                    status: "completed"
                ))
            ],
            usage: ResponseUsage(
                inputTokens: 15,
                outputTokens: 40,
                totalTokens: 55,
                inputTokensDetails: nil,
                outputTokensDetails: nil
            ),
            previousResponseId: nil,
            metadata: nil,
            incompleteDetails: nil,
            error: nil,
            instructions: nil,
            temperature: 1.0,
            topP: 1.0,
            maxOutputTokens: nil,
            toolChoice: nil,
            tools: [.codeInterpreter],
            parallelToolCalls: true,
            reasoning: nil,
            truncation: nil,
            text: nil,
            user: nil,
            store: false,
            serviceTier: nil
        )
    }

    /// Create a response with conversation continuation
    public static func makeConversationResponse(
        id: String = "resp_conv",
        previousResponseId: String = "resp_prev",
        text: String = "Continuing our conversation..."
    ) -> ResponseObject {
        ResponseObject(
            id: id,
            object: "response",
            createdAt: 1704067200,
            model: "gpt-4o-mini",
            status: .completed,
            output: [
                .message(ResponseOutputMessage(
                    id: "msg_conv_123",
                    role: "assistant",
                    content: [.outputText(ResponseOutputText(text: text))]
                ))
            ],
            usage: ResponseUsage(
                inputTokens: 50,
                outputTokens: 30,
                totalTokens: 80,
                inputTokensDetails: ResponseInputTokensDetails(cachedTokens: 40),
                outputTokensDetails: nil
            ),
            previousResponseId: previousResponseId,
            metadata: nil,
            incompleteDetails: nil,
            error: nil,
            instructions: nil,
            temperature: 1.0,
            topP: 1.0,
            maxOutputTokens: nil,
            toolChoice: nil,
            tools: nil,
            parallelToolCalls: true,
            reasoning: nil,
            truncation: nil,
            text: nil,
            user: nil,
            store: true,
            serviceTier: nil
        )
    }

    /// Create a failed response
    public static func makeFailedResponse(
        id: String = "resp_failed",
        errorCode: String = "server_error",
        errorMessage: String = "Internal server error"
    ) -> ResponseObject {
        ResponseObject(
            id: id,
            object: "response",
            createdAt: 1704067200,
            model: "gpt-4o-mini",
            status: .failed,
            output: [],
            usage: nil,
            previousResponseId: nil,
            metadata: nil,
            incompleteDetails: nil,
            error: ResponseError(code: errorCode, message: errorMessage, type: "api_error"),
            instructions: nil,
            temperature: nil,
            topP: nil,
            maxOutputTokens: nil,
            toolChoice: nil,
            tools: nil,
            parallelToolCalls: nil,
            reasoning: nil,
            truncation: nil,
            text: nil,
            user: nil,
            store: nil,
            serviceTier: nil
        )
    }

    /// Create an incomplete response
    public static func makeIncompleteResponse(
        id: String = "resp_incomplete",
        reason: String = "max_output_tokens"
    ) -> ResponseObject {
        ResponseObject(
            id: id,
            object: "response",
            createdAt: 1704067200,
            model: "gpt-4o-mini",
            status: .incomplete,
            output: [
                .message(ResponseOutputMessage(
                    id: "msg_incomplete_123",
                    role: "assistant",
                    content: [.outputText(ResponseOutputText(text: "This is a partial response that was cut off due to..."))]
                ))
            ],
            usage: ResponseUsage(
                inputTokens: 10,
                outputTokens: 100,
                totalTokens: 110,
                inputTokensDetails: nil,
                outputTokensDetails: nil
            ),
            previousResponseId: nil,
            metadata: nil,
            incompleteDetails: ResponseIncompleteDetails(reason: reason, type: nil),
            error: nil,
            instructions: nil,
            temperature: 1.0,
            topP: 1.0,
            maxOutputTokens: 100,
            toolChoice: nil,
            tools: nil,
            parallelToolCalls: true,
            reasoning: nil,
            truncation: nil,
            text: nil,
            user: nil,
            store: false,
            serviceTier: nil
        )
    }

    // MARK: - Compaction Fixtures

    /// Create a compact response fixture
    public static func makeCompactResponse(
        id: String = "compact_123",
        status: CompactStatus = .completed
    ) -> CompactResponse {
        CompactResponse(
            id: id,
            object: "response.compact",
            createdAt: 1704067200,
            output: [
                CompactedOutputItem(
                    id: "compact_item_1",
                    encryptedContent: "encrypted_payload",
                    summary: "Summary of compacted messages",
                    compactedItemCount: 5,
                    originalTokenCount: 200,
                    compactedTokenCount: 80
                )
            ],
            usage: ResponseUsage(
                inputTokens: 200,
                outputTokens: 80,
                totalTokens: 280,
                inputTokensDetails: nil,
                outputTokensDetails: nil
            ),
            status: status
        )
    }

    // MARK: - Stream Chunk Fixtures

    /// Create basic stream chunks for testing
    public static func makeStreamChunks(text: String = "Hello world!") -> [ResponseChunk] {
        let words = text.split(separator: " ").map(String.init)
        var chunks: [ResponseChunk] = []

        for (index, word) in words.enumerated() {
            let isLast = index == words.count - 1
            let deltaText = isLast ? word : word + " "

            chunks.append(ResponseChunk(
                id: "chunk-\(index)",
                object: "response.chunk",
                createdAt: 1704067200,
                model: "gpt-4o-mini",
                status: isLast ? .completed : .inProgress,
                delta: ResponseDelta(
                    output: nil,
                    outputText: deltaText,
                    reasoning: nil,
                    text: deltaText
                ),
                usage: isLast ? ResponseUsage(
                    inputTokens: 5,
                    outputTokens: words.count,
                    totalTokens: 5 + words.count,
                    inputTokensDetails: nil,
                    outputTokensDetails: nil
                ) : nil,
                error: nil
            ))
        }

        return chunks
    }

    // MARK: - JSON Fixtures

    /// Simple request JSON
    public static let requestJSON = """
    {
        "model": "gpt-4o-mini",
        "input": "Hello",
        "instructions": "Be helpful",
        "temperature": 0.7
    }
    """

    /// Simple response JSON
    public static let responseJSON = """
    {
        "id": "resp_123",
        "object": "response",
        "created_at": 1704067200,
        "status": "completed",
        "model": "gpt-4o-mini",
        "output": [
            {
                "type": "message",
                "id": "msg_123",
                "role": "assistant",
                "content": [
                    {"type": "output_text", "text": "Hello!"}
                ]
            }
        ],
        "parallel_tool_calls": true,
        "store": false,
        "temperature": 1.0,
        "top_p": 1.0,
        "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}
    }
    """

    /// Response with tool call JSON
    public static let toolCallResponseJSON = """
    {
        "id": "resp_456",
        "object": "response",
        "created_at": 1704067200,
        "status": "completed",
        "model": "gpt-4o-mini",
        "output": [
            {
                "type": "function_call",
                "id": "fc_123",
                "name": "get_weather",
                "arguments": "{\\"location\\":\\"Tokyo\\"}",
                "call_id": "call_abc",
                "status": "completed"
            }
        ],
        "parallel_tool_calls": true,
        "store": false,
        "temperature": 1.0,
        "top_p": 1.0,
        "usage": {"input_tokens": 15, "output_tokens": 25, "total_tokens": 40}
    }
    """

    /// Response with all status types JSON templates
    public static func responseJSONWithStatus(_ status: String) -> String {
        """
        {
            "id": "resp_\(status)",
            "object": "response",
            "created_at": 1704067200,
            "status": "\(status)",
            "model": "gpt-4o-mini",
            "output": [],
            "parallel_tool_calls": true,
            "store": false,
            "temperature": 1.0,
            "top_p": 1.0
        }
        """
    }

    /// Request with items input JSON
    public static let requestWithItemsJSON = """
    {
        "model": "gpt-4o-mini",
        "input": [
            {
                "type": "message",
                "role": "user",
                "content": [
                    {"type": "input_text", "text": "Hello, world!"}
                ]
            }
        ],
        "temperature": 0.7
    }
    """

    /// Request with tools JSON
    public static let requestWithToolsJSON = """
    {
        "model": "gpt-4o-mini",
        "input": "Search for the latest news",
        "tools": [
            {"type": "web_search_preview"},
            {"type": "code_interpreter"}
        ]
    }
    """

    /// Web search response JSON
    public static let webSearchResponseJSON = """
    {
        "id": "resp_ws",
        "object": "response",
        "created_at": 1704067200,
        "status": "completed",
        "model": "gpt-4o-mini",
        "output": [
            {
                "type": "message",
                "id": "msg_ws",
                "role": "assistant",
                "content": [
                    {"type": "output_text", "text": "Based on my search..."}
                ]
            },
            {
                "type": "web_search_call",
                "id": "ws_123",
                "query": "latest news",
                "result": "News results...",
                "status": "completed"
            }
        ],
        "tools": [{"type": "web_search_preview"}],
        "parallel_tool_calls": true,
        "store": false,
        "temperature": 1.0,
        "top_p": 1.0,
        "usage": {"input_tokens": 10, "output_tokens": 30, "total_tokens": 40}
    }
    """

    /// Response with usage details JSON
    public static let responseWithUsageDetailsJSON = """
    {
        "id": "resp_usage",
        "object": "response",
        "created_at": 1704067200,
        "status": "completed",
        "model": "gpt-4o-mini",
        "output": [
            {
                "type": "message",
                "id": "msg_usage",
                "role": "assistant",
                "content": [
                    {"type": "output_text", "text": "Response with detailed usage"}
                ]
            }
        ],
        "parallel_tool_calls": true,
        "store": false,
        "temperature": 1.0,
        "top_p": 1.0,
        "usage": {
            "input_tokens": 100,
            "output_tokens": 50,
            "total_tokens": 150,
            "input_tokens_details": {
                "cached_tokens": 80
            },
            "output_tokens_details": {
                "reasoning_tokens": 20
            }
        }
    }
    """

    /// Compact request JSON
    public static let compactRequestJSON = """
    {
        "model": "gpt-4o-mini",
        "previous_response_id": "resp_prev",
        "instructions": "Summarize the conversation",
        "metadata": {"topic": "summary"}
    }
    """

    /// Compact response JSON
    public static let compactResponseJSON = """
    {
        "id": "compact_123",
        "object": "response.compact",
        "created_at": 1704067200,
        "status": "completed",
        "output": [
            {
                "type": "compaction",
                "id": "compact_item_1",
                "encrypted_content": "encrypted_payload",
                "summary": "Summary of compacted messages",
                "compacted_item_count": 5,
                "original_token_count": 200,
                "compacted_token_count": 80
            }
        ],
        "usage": {"input_tokens": 200, "output_tokens": 80, "total_tokens": 280}
    }
    """
}
