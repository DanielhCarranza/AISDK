# fn-1.7 Task 1.4: AIObjectRequest/AIObjectResult

## Description
Create dedicated AIObjectRequest and AIObjectResult models for structured object generation, following the same patterns as AITextRequest/AITextResult with PHI protection, Sendable conformance, and transformation extensions.

## Acceptance
- [x] AIObjectRequest model with PHI protection (sensitivity, allowedProviders)
- [x] AIObjectRequest with transformation extensions (withSensitivity, withAllowedProviders, withBufferPolicy)
- [x] AIObjectResult model with metadata (requestId, model, provider, rawJSON)
- [x] AIObjectResult with helper properties and map transformation
- [x] Comprehensive tests for both models
- [x] Remove duplicate definitions from AILanguageModel.swift

## Done summary
Created AIObjectRequest and AIObjectResult as standalone models in Sources/AISDK/Core/Models/, mirroring the pattern from AITextRequest/AITextResult. Key features:
- AIObjectRequest: Generic request for structured object generation with PHI protection (sensitivity, allowedProviders), streaming buffer policy, and transformation methods
- AIObjectResult: Generic result with usage tracking, metadata (requestId, model, provider, rawJSON), helper properties, and a map() method for transforming the result object
- Removed duplicate definitions from AILanguageModel.swift and updated the default implementation to use the new model fields
- Added 15 comprehensive tests covering initialization, PHI protection, transformations, and helper properties

## Evidence
- Commits: (to be added after commit)
- Tests: AIObjectRequestTests.swift (8 tests), AIObjectResultTests.swift (7 tests) - all passing
- PRs:
