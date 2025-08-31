## Task ID

BUG-ToolMetadataDecoding

## Problem Statement

Decoding `ChatSession` fails when a `ChatMessage` contains app-defined `ToolMetadata`. Error observed:

```
Unknown ToolMetadata type: ConyAIDoctor.Sources
```

This occurs during decoding of `AnyToolMetadata` inside AISDK, where the metadata `type` string persisted as the fully-qualified app type (e.g., `ConyAIDoctor.Sources`) cannot be resolved at runtime on a fresh process, causing a decoding failure and breaking session loading.

## Root Cause Analysis

- AISDK wraps tool metadata in `AnyToolMetadata` which stores `{ type: String(reflecting: Swift.type(of: metadata)), metadata: ... }`.
- On decode, AISDK attempts:
  1) Use an in-memory registry (populated only when `AnyToolMetadata` is constructed in the same process) to find a decoder closure.
  2) Fallback to `_typeByName(typeString)` to dynamically resolve the type, then decode via `Decodable`.
  3) Special-case fallback for `RenderMetadata`.
- Persisted sessions are decoded in a fresh process, so the in-memory registry is empty. `_typeByName` may fail to locate app-defined types (e.g., due to module/type name mismatches, symbol visibility, or Swift runtime limitations), producing: "Unknown ToolMetadata type: ConyAIDoctor.Sources".
- Tests pass because they encode and decode within the same process, so the registry path succeeds; they do not simulate cross-process decoding of app-defined types.

## Proposed Implementation

Introduce a robust, explicit registration and a safe fallback to prevent crashes:

1) Public Metadata Registration API
- Add a public API to pre-register metadata types at app startup:
  - `ToolMetadataDecoderRegistry.register(Sources.self)` (and batch variant).
  - Internally registers a decoding closure keyed by `String(reflecting: T.self)` to satisfy path (1) deterministically.

2) Graceful Fallback for Unknown Types (Optional but recommended)
- Add `RawToolMetadata: ToolMetadata` that stores the original `type` string and raw payload (e.g., `Data` or `[String: Any]`).
- In `AnyToolMetadata.init(from:)`, if registry and `_typeByName` both fail, decode into `RawToolMetadata` instead of throwing. This preserves data and avoids breaking `ChatSession` loads. UI can feature-detect and ignore or log unknown metadata types.

3) Documentation & Examples
- Update `docs/Usage.md` with a "Register your ToolMetadata types" section showing where to call registration (e.g., `AppDelegate` or early bootstrap).
- Note the optional fallback behavior and how to handle `RawToolMetadata` if present.

4) Tests
- Add tests that simulate a fresh process by clearing the internal registry and verifying:
  - Decoding fails without registration and succeeds with `register(...)`.
  - With fallback enabled, decoding yields `RawToolMetadata` instead of throwing.

## Components Involved

- AISDK `Tools/Tool.swift`: `AnyToolMetadata`, `ToolMetadataRegistry`.
- AISDK `Models/ChatMessage.swift`: metadata encode/decode via `AnyToolMetadata`.
- AISDK `docs/Usage.md`: add registration guidance.
- Tests under `Tests/AISDKTests/`.

## Dependencies

- Swift runtime reflection (`_typeByName`).
- Build settings (symbol visibility may influence reflection success).

## Implementation Checklist

- [ ] Add public `ToolMetadataDecoderRegistry` with `register<T: ToolMetadata & Decodable>(_:)` and `registerAll(_:)`.
- [ ] Wire registry to internal decoder map keyed by `String(reflecting: T.self)`.
- [ ] (Optional) Add `RawToolMetadata` and change unknown-type branch to decode into it, not throw.
- [ ] Update `docs/Usage.md` with registration examples and guidance.
- [ ] Add unit tests for cross-process-like decode (registry empty) with and without fallback.
- [ ] Validate no regressions to existing metadata encoding/decoding and streaming flows.

## Verification Steps

Automated:
- Create sample `ToolMetadata` types in test target (simulating app types) and persist an `AnyToolMetadata` JSON blob.
- Clear internal registry, then:
  - Attempt decode without registration → expect failure (current behavior).
  - Call `ToolMetadataDecoderRegistry.register(...)` → expect success and typed instance.
  - If fallback enabled, attempt decode without registration → expect `RawToolMetadata` and no throw.

Manual:
- In a sample app, register `Source`, `Sources`, `MedicalEvidence` at launch. Save and reload a chat session after cold restart. Confirm decoding succeeds.

## Decision Authority

- Library API surface (new public registry) and fallback behavior: may proceed without user approval.
- App integration specifics (where to register, whether to enable fallback): confirm with user.

## Questions / Uncertainties

Blocking:
- None.

Non-blocking (assumptions unless directed otherwise):
- Prefer explicit registration API as the primary fix; fallback is an additional safeguard.
- Using `String(reflecting:)` for keys remains acceptable; no change to on-wire `type` format.

## Acceptable Tradeoffs

- Introducing a public registration API slightly increases integration steps but provides deterministic behavior across process boundaries.
- Fallback to `RawToolMetadata` trades type safety for robustness; acceptable as a last-resort to avoid data loss/crashes.

## Status

Not Started

## Notes

- Relevant decode path (for reference) throws when both registry and `_typeByName` fail:

```98:134:Sources/AISDK/Tools/Tool.swift
        if let anyType = _typeByName(self.type),
           let decodableMetaType = anyType as? Decodable.Type,
           let _ = anyType as? ToolMetadata.Type {
            let nested = try container.superDecoder(forKey: .metadata)
            let anyObject = try decodableMetaType.init(from: nested)
            if let toolMeta = anyObject as? ToolMetadata {
                self.metadata = toolMeta
                return
            }
        }

        // 3) Legacy hard-coded RenderMetadata fallback
        if self.type == String(describing: RenderMetadata.self) {
            self.metadata = try container.decode(RenderMetadata.self, forKey: .metadata)
            return
        }

        throw DecodingError.dataCorruptedError(forKey: .type,
                                               in: container,
                                               debugDescription: "Unknown ToolMetadata type: \(self.type)")
```


