# fn-1.30 Task 3.6: CapabilityAwareFailover

## Description
Failover policy with capability and cost awareness. Ensures failover targets are compatible with request requirements including token limits, cost constraints, and capability matching.

## Acceptance
- [x] TokenEstimator for estimating token counts
- [x] FailoverPolicy with configurable constraints
- [x] Max cost multiplier constraint
- [x] Capability match requirement option
- [x] Minimum context window constraint
- [x] Provider allowlist (PHI protection) checking
- [x] Preset policies: default, strict, lenient, costConscious
- [x] FailoverCompatibilityResult with detailed incompatibility reasons
- [x] IncompatibilityReason enum for failure explanations
- [x] Comprehensive test coverage (32 tests)

## Done summary
Implemented CapabilityAwareFailover for Phase 3 reliability layer.

Key features:
- TokenEstimator with configurable chars-per-token (default: 4)
- Estimates for text, images (200 tokens), audio, and files
- FailoverPolicy with configurable maxCostMultiplier (default: 5.0), requireCapabilityMatch, minimumContextWindow, allowLowerTier, requiredCapabilities
- Preset policies: default, strict (2x cost, no lower tier), lenient (10x cost), costConscious (1.5x cost)
- isCompatible async method for full capability checking
- isProviderAllowed sync method for allowlist checking
- FailoverCompatibilityResult with IncompatibilityReason for detailed failure info
- 32 comprehensive tests across 8 test classes

## Evidence
- Commits: (pending commit)
- Tests: swift test --filter CapabilityAwareFailover (32 tests pass)
- PRs:
