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
Created AIObjectRequest and AIObjectResult as standalone models with PHI protection. Added transformation methods, helper properties, and 15 comprehensive tests. Removed duplicate definitions from AILanguageModel.swift.
## Evidence
- Commits: f0e0ac5
- Tests: swift test --filter AIObjectRequestTests|AIObjectResultTests
- PRs: