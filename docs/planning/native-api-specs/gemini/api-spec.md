# Google Gemini API: Native multimodal and video processing

Gemini's **unique video and audio processing capabilities** make it essential for healthcare applications involving medical imaging, telehealth recordings, or patient education videos. The **1M+ token context window** across all models enables processing entire patient histories in single requests.

### Endpoint inventory

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/v1beta/models/{model}:generateContent` | Generate content |
| POST | `/v1beta/models/{model}:streamGenerateContent` | Streaming generation |
| GET | `/v1beta/models` | List models |
| POST | `/upload/v1beta/files` | Upload file (resumable) |
| GET | `/v1beta/files/{name}` | Get file status |
| DELETE | `/v1beta/files/{name}` | Delete file |
| POST | `/v1beta/cachedContents` | Create cached content |

### Request schema

```swift
struct GenerateContentRequest: Codable {
    let contents: [Content]                     // Required: conversation history
    var tools: [Tool]?                          // Function calling, code execution
    var toolConfig: ToolConfig?                 // Function calling mode
    var safetySettings: [SafetySetting]?
    var systemInstruction: Content?             // System prompt (text only)
    var generationConfig: GenerationConfig?
    var cachedContent: String?                  // "cachedContents/{id}"
}

struct GenerationConfig: Codable {
    var temperature: Double?                    // 0.0 to model max
    var topP: Double?
    var topK: Int?
    var maxOutputTokens: Int?
    var stopSequences: [String]?
    var responseMimeType: String?              // "text/plain" | "application/json"
    var responseSchema: JSONSchema?            // Structured output
    var candidateCount: Int?                   // Usually 1
}
```

### Content part types

Gemini uses a `Part` union with distinct types for different media:

```swift
// Text
Part.text("Hello")

// Inline binary data (< 20MB total request)
Part.inlineData(mimeType: "image/jpeg", data: base64String)

// Uploaded file reference
Part.fileData(mimeType: "video/mp4", fileUri: "https://generativelanguage.googleapis.com/v1beta/files/abc-123")

// Function call (in model response)
Part.functionCall(name: "get_weather", args: ["location": "Chicago"])

// Function response (user sends back)
Part.functionResponse(name: "get_weather", response: weatherData)
```

### Files API with video support

Gemini's Files API is the **only provider supporting video upload** for inference:

**Supported MIME types**:
- **Video**: `video/mp4`, `video/mpeg`, `video/mov`, `video/avi`, `video/webm`, `video/wmv`, `video/3gpp`
- **Audio**: `audio/wav`, `audio/mp3`, `audio/aac`, `audio/ogg`, `audio/flac`
- **Images**: `image/jpeg`, `image/png`, `image/webp`, `image/gif`, `image/heic`
- **Documents**: `application/pdf`, `text/plain`, `text/html`, `application/json`

**Upload process** (resumable protocol):
1. Initiate: `POST /upload/v1beta/files` with `X-Goog-Upload-Protocol: resumable`
2. Upload bytes to returned `x-goog-upload-url`
3. Poll `GET /v1beta/files/{name}` until `state: "ACTIVE"`

**File states**: `PROCESSING` → `ACTIVE` | `FAILED`
**Expiration**: **48 hours** automatic deletion
**Video processing time**: Varies by duration—poll for `ACTIVE` state before use

### Video token economics

Understanding token costs is critical for healthcare video processing:

| Resolution | Visual Tokens | Audio Tokens | Total/Second |
|------------|---------------|--------------|--------------|
| Default | ~258/frame (1 fps) | 32/sec | ~290/sec |
| Low | ~66/frame (1 fps) | 32/sec | ~98/sec |

**Practical limits** with 1M context:
- Default resolution: ~57 minutes of video
- Low resolution: ~170 minutes of video
- Maximum supported: 1 hour at default, 3 hours at low resolution

Set via `generationConfig.mediaResolution`: `"high"` | `"low"`

### Streaming format

Gemini uses SSE with `alt=sse` query parameter:

```
POST /v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse&key={API_KEY}
```

Response chunks are complete `GenerateContentResponse` objects:
```json
data: {"candidates":[{"content":{"parts":[{"text":"Hello"}],"role":"model"}}],"usageMetadata":{...}}
```

Concatenate `candidates[0].content.parts[0].text` across chunks. Check `finishReason` for completion.

### Context caching for longitudinal patient data

Gemini's caching reduces costs when reusing large context (minimum **2,048-4,096 tokens** depending on model):

```swift
struct CachedContent: Codable {
    let model: String
    var displayName: String?
    var systemInstruction: Content?
    let contents: [Content]           // Content to cache
    var tools: [Tool]?
    var expiration: Expiration?       // ttl: "3600s" or expireTime
}
```

**Implicit caching** (Gemini 2.5+): Automatic cost savings when cache hits occur—no explicit cache creation needed.

### Current model capabilities

| Model | Input Limit | Output Limit | Video | Audio | PDF |
|-------|-------------|--------------|-------|-------|-----|
| gemini-3-pro-preview | 1,048,576 | 65,536 | ✓ | ✓ | ✓ |
| gemini-3-flash-preview | 1,048,576 | 65,536 | ✓ | ✓ | ✓ |
| gemini-2.5-pro | 1,048,576 | 65,536 | ✓ | ✓ | ✓ |
| gemini-2.5-flash | 1,048,576 | 65,536 | ✓ | ✓ | ✓ |
| gemini-2.5-flash-lite | 1,048,576 | 65,536 | ✓ | ✓ | ✓ |
