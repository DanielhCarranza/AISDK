# Video Modality Guide

AISDK supports video input for models that accept it (currently Gemini). Other providers throw `ProviderError.unsupportedModality` with an actionable message telling you which providers support video.

## Check Capability Before Sending

```swift
import AISDK

// Check if a model supports video before sending
let model = ModelRegistry.gemini25Flash
if model.hasCapability(.video) {
    // Safe to send video content
}
```

For proxy providers (OpenRouter, LiteLLM), use the client's capability query:

```swift
let client = OpenRouterClient(apiKey: "sk-or-...")
if let caps = await client.capabilities(for: "google/gemini-2.0-flash"),
   caps.contains(.video) {
    // This model supports video via OpenRouter
}
```

## Send Video to Gemini

```swift
// Recommended: use factory method
let gemini = ProviderLanguageModelAdapter.gemini(apiKey: geminiKey, modelId: "gemini-2.0-flash")

// From data
let videoData = try Data(contentsOf: videoFileURL)
let request = AITextRequest(
    messages: [
        .user([
            .text("Describe what happens in this video"),
            .video(videoData, format: .mp4)
        ])
    ]
)
let response = try await gemini.generateText(request: request)

// From URL
let request2 = AITextRequest(
    messages: [
        .user([
            .text("Summarize this clip"),
            .videoURL(remoteURL, format: .mov)
        ])
    ]
)
let response2 = try await gemini.generateText(request: request2)
```

## Route by Capability

When building a multi-provider app, route video requests to a capable model:

```swift
func analyzeContent(text: String, video: Data?) async throws -> String {
    if let video {
        // Route to Gemini for video
        let gemini = ProviderLanguageModelAdapter.gemini(apiKey: geminiKey, modelId: "gemini-2.0-flash")
        let request = AITextRequest(
            messages: [.user([.text(text), .video(video, format: .mp4)])]
        )
        let result = try await gemini.generateText(request: request)
        return result.text
    } else {
        // Any provider works for text-only
        let openai = ProviderLanguageModelAdapter.openAIResponses(apiKey: openAIKey, modelId: "gpt-4o")
        let request = AITextRequest(messages: [.user(text)])
        let result = try await openai.generateText(request: request)
        return result.text
    }
}
```

## Handle Unsupported Modality Errors

If you accidentally send video to a non-video provider, you get an actionable error:

```swift
do {
    let result = try await openAI.generateText(
        messages: [.user([.text("Describe this"), .video(data, format: .mp4)])]
    )
} catch let error as ProviderError {
    // error.localizedDescription:
    // "Unsupported modality: 'video' is not supported by OpenAI.
    //  Providers that support video: Gemini."
    print(error.localizedDescription)
}
```

## Capability-Aware Failover

Use `FailoverPolicy` with `requiredCapabilities` to ensure failover only targets video-capable providers:

```swift
let failover = FailoverPolicy(
    providers: [openAIProvider, geminiProvider],
    requiredCapabilities: [.video]
)
// Only Gemini will be selected for video requests
```

## Provider Support Matrix

| Provider | Video Support | Notes |
|----------|:---:|-------|
| Gemini | Yes | All 1.5/2.0/2.5 models. Inline data + URL. |
| OpenAI | No | Throws `unsupportedModality` |
| Anthropic | No | Throws `unsupportedModality` |
| OpenRouter | Depends | Reports `.video` for Gemini-backed models |
| LiteLLM | Depends | Reports `.video` for Gemini-backed models |
