//
//  StreamEventFixtures.swift
//  AISDKTests
//
//  JSON fixtures for OpenAI Responses API streaming events
//

import Foundation

public enum StreamEventFixtures {

    // MARK: - Lifecycle Events

    public static let responseCreated = """
    {"type": "response.created", "sequence_number": 1, "response": {"id": "resp_123", "object": "response", "created_at": 1704067200, "model": "gpt-4o-mini", "status": "in_progress", "output": [], "parallel_tool_calls": true, "store": false, "temperature": 1.0, "top_p": 1.0}}
    """

    public static let responseInProgress = """
    {"type": "response.in_progress", "sequence_number": 2, "response": {"id": "resp_123", "object": "response", "created_at": 1704067200, "model": "gpt-4o-mini", "status": "in_progress", "output": []}}
    """

    public static let responseCompleted = """
    {"type": "response.completed", "sequence_number": 100, "response": {"id": "resp_123", "object": "response", "created_at": 1704067200, "model": "gpt-4o-mini", "status": "completed", "output": [], "usage": {"input_tokens": 5, "output_tokens": 3, "total_tokens": 8}}}
    """

    public static let responseFailed = """
    {"type": "response.failed", "sequence_number": 50, "response": {"id": "resp_123", "object": "response", "created_at": 1704067200, "model": "gpt-4o-mini", "status": "failed", "output": [], "error": {"code": "server_error", "message": "Internal server error"}}}
    """

    public static let responseIncomplete = """
    {"type": "response.incomplete", "sequence_number": 80, "response": {"id": "resp_123", "object": "response", "created_at": 1704067200, "model": "gpt-4o-mini", "status": "incomplete", "output": [], "incomplete_details": {"reason": "max_output_tokens"}}}
    """

    public static let responseQueued = """
    {"type": "response.queued", "sequence_number": 0, "response": {"id": "resp_123", "object": "response", "created_at": 1704067200, "model": "gpt-4o-mini", "status": "queued", "output": []}}
    """

    // MARK: - Output Item Events

    public static let outputItemAdded = """
    {"type": "response.output_item.added", "sequence_number": 5, "output_index": 0, "item": {"type": "message", "id": "msg_123", "status": "in_progress", "role": "assistant", "content": []}}
    """

    public static let outputItemDone = """
    {"type": "response.output_item.done", "sequence_number": 30, "output_index": 0, "item": {"type": "message", "id": "msg_123", "status": "completed", "role": "assistant", "content": [{"type": "output_text", "text": "Hello!"}]}}
    """

    // MARK: - Content Part Events

    public static let contentPartAdded = """
    {"type": "response.content_part.added", "sequence_number": 6, "item_id": "msg_123", "output_index": 0, "content_index": 0, "part": {"type": "output_text", "text": ""}}
    """

    public static let contentPartDone = """
    {"type": "response.content_part.done", "sequence_number": 25, "item_id": "msg_123", "output_index": 0, "content_index": 0, "part": {"type": "output_text", "text": "Hello!"}}
    """

    // MARK: - Text Events

    public static let outputTextDelta = """
    {"type": "response.output_text.delta", "sequence_number": 10, "item_id": "msg_123", "output_index": 0, "content_index": 0, "delta": "Hello"}
    """

    public static let outputTextDone = """
    {"type": "response.output_text.done", "sequence_number": 20, "item_id": "msg_123", "output_index": 0, "content_index": 0, "text": "Hello world!"}
    """

    public static let refusalDelta = """
    {"type": "response.refusal.delta", "sequence_number": 10, "item_id": "msg_123", "output_index": 0, "content_index": 0, "delta": "I cannot"}
    """

    public static let refusalDone = """
    {"type": "response.refusal.done", "sequence_number": 20, "item_id": "msg_123", "output_index": 0, "content_index": 0, "text": "I cannot help with that request."}
    """

    // MARK: - Function Call Events

    public static let functionCallArgumentsDelta = """
    {"type": "response.function_call_arguments.delta", "sequence_number": 15, "item_id": "fc_123", "output_index": 0, "delta": "{\\\"location\\\":"}
    """

    public static let functionCallArgumentsDone = """
    {"type": "response.function_call_arguments.done", "sequence_number": 25, "item_id": "fc_123", "output_index": 0, "text": "{\\\"location\\\":\\\"Tokyo\\\"}"}
    """

    // MARK: - File Search Events

    public static let fileSearchInProgress = """
    {"type": "response.file_search_call.in_progress", "sequence_number": 10, "item_id": "fs_123", "output_index": 0}
    """

    public static let fileSearchSearching = """
    {"type": "response.file_search_call.searching", "sequence_number": 12, "item_id": "fs_123", "output_index": 0}
    """

    public static let fileSearchCompleted = """
    {"type": "response.file_search_call.completed", "sequence_number": 20, "item_id": "fs_123", "output_index": 0}
    """

    // MARK: - Web Search Events

    public static let webSearchInProgress = """
    {"type": "response.web_search_call.in_progress", "sequence_number": 10, "item_id": "ws_123", "output_index": 0}
    """

    public static let webSearchSearching = """
    {"type": "response.web_search_call.searching", "sequence_number": 12, "item_id": "ws_123", "output_index": 0}
    """

    public static let webSearchCompleted = """
    {"type": "response.web_search_call.completed", "sequence_number": 20, "item_id": "ws_123", "output_index": 0}
    """

    // MARK: - Reasoning Events

    public static let reasoningDelta = """
    {"type": "response.reasoning.delta", "sequence_number": 8, "item_id": "rs_123", "output_index": 0, "delta": "Thinking..."}
    """

    public static let reasoningDone = """
    {"type": "response.reasoning.done", "sequence_number": 18, "item_id": "rs_123", "output_index": 0, "text": "Thinking complete."}
    """

    public static let reasoningSummaryDelta = """
    {"type": "response.reasoning_summary.delta", "sequence_number": 20, "item_id": "rs_123", "output_index": 0, "delta": "Summary: "}
    """

    public static let reasoningSummaryDone = """
    {"type": "response.reasoning_summary.done", "sequence_number": 25, "item_id": "rs_123", "output_index": 0, "text": "Summary: I analyzed the options."}
    """

    // MARK: - Error Event

    public static let errorEvent = """
    {"type": "error", "sequence_number": 99, "code": "server_error", "message": "Internal server error", "param": null}
    """

    // MARK: - Unknown/Future Event

    public static let unknownEvent = """
    {"type": "response.some_future_event", "sequence_number": 50, "item_id": "future_123", "data": {"key": "value"}}
    """

    // MARK: - Edge Cases

    public static let emptyDelta = """
    {"type": "response.output_text.delta", "sequence_number": 10, "item_id": "msg_123", "output_index": 0, "content_index": 0, "delta": ""}
    """

    public static let unicodeDelta = """
    {"type": "response.output_text.delta", "sequence_number": 10, "item_id": "msg_123", "output_index": 0, "content_index": 0, "delta": "Hello 123"}
    """

    public static let escapedJsonDelta = """
    {"type": "response.function_call_arguments.delta", "sequence_number": 10, "item_id": "fc_123", "output_index": 0, "delta": "{\\\"key\\\":\\\"value with \\\\\\\"quotes\\\\\\\"\\\"}" }
    """
}
