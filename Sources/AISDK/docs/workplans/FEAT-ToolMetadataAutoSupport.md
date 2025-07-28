# Workplan: FEAT-ToolMetadataAutoSupport

## Task ID
FEAT-ToolMetadataAutoSupport

## Problem Statement
`AnyToolMetadata` is hard-coded to encode/decode only a fixed set of metadata types (e.g. `RenderMetadata`). When client applications declare new structs that conform to `ToolMetadata`, they must also modify `AnyToolMetadata` or perform manual registration. This breaks library extensibility and forces boilerplate changes in the SDK whenever a new metadata type is introduced.

## Proposed Implementation
1. **Dynamic Type Identification**  
   • Encode the *fully-qualified* type name using `String(reflecting: Swift.type(of: …))` to include the module (e.g. `MyApp.Source`).  
   • During decoding, use Swift’s private runtime function `_typeByName(_:)` to look up the type at runtime.  
   • Attempt to cast the resulting metatype to `(any ToolMetadata & Decodable).Type`; if successful, decode the payload via that type’s `init(from:)`.

2. **Fallback Logic & Backward Compatibility**  
   • Keep the existing switch for known SDK types (`RenderMetadata`) so payloads written by previous SDK versions still decode.  
   • If `_typeByName` fails, throw a descriptive decoding error (current behaviour).

3. **Encoding Existential `ToolMetadata`**  
   • Introduce a small `AnyEncodable` helper to wrap an `Encodable` existential so we can call `encode(to:)` on `metadata` without a massive switch.

4. **Zero-Config Client Usage**  
   • No registration or extra code is required in client projects—declaring `struct MyType: ToolMetadata { … }` is sufficient.

5. **Unit Tests**  
   • Add tests that round-trip arbitrary metadata types (e.g. `Source`, `MedicalEvidence`) through `AnyToolMetadata` encode/decode.  
   • Add regression test for legacy `RenderMetadata` payload.

## Components Involved
• `Sources/AISDK/Tools/Tool.swift` (contains `AnyToolMetadata`)  
• Unit tests under `Tests/AISDKTests/`

## Dependencies
None external. Uses `_typeByName` from Swift stdlib (available in current Swift 5.9 runtime).

## Implementation Checklist
- [ ] Add `AnyEncodable` helper struct inside `Tool.swift` (private).  
- [ ] Update `AnyToolMetadata.encode` to:  
  - Compute `type = String(reflecting: Swift.type(of: metadata))`  
  - Encode via `AnyEncodable(metadata)`
- [ ] Update `AnyToolMetadata.init(from:)` to:  
  - Attempt `_typeByName(typeString)` dynamic lookup.  
  - If found and conforms to required protocols, decode.  
  - Else fall back to legacy switch for `RenderMetadata`.  
  - Else throw decoding error.
- [ ] Add unit tests covering:  
  - Round-trip `Source`.  
  - Round-trip `MedicalEvidence` with nested `Source`.  
  - Legacy `RenderMetadata` decoding.
- [ ] Update documentation (Usage guide section on ToolMetadata) with example—no extra registration needed.

## Verification Steps (Machine-Executable)
1. `swift test` passes with the new tests.  
2. Existing test suite (`./Tests`) passes to ensure no regressions.  
3. (Optional) Run `swift package benchmark` if available to check negligible performance impact (<5 %).

## Decision Authority
• Design choices inside the SDK (dynamic lookup, helper structs) may be made independently.  
• If `_typeByName` proves unstable on a future Swift version, escalate for discussion.

## Questions / Uncertainties
### Blocking
None.

### Non-blocking
* Are we comfortable relying on the underscored `_typeByName`? (Documented as acceptable until Swift offers an official alternative.)

## Acceptable Trade-offs
• Uses private stdlib symbol (`_typeByName`)—acceptable for SDK internal logic; revisit if it breaks on a future toolchain.  
• Will throw decoding error for unknown types with minimal diagnostics; alternative (storing raw JSON) deferred for simplicity.

## Status
Not Started

## Notes
N/A 