---
title: "feat: SDK versioning and migration infrastructure"
type: feat
date: 2026-02-11
brainstorm: docs/brainstorms/2026-02-11-sdk-versioning-migration-strategy-brainstorm.md
existing_plan: .context/plans/aisdk-branch-restructuring-promote-v2-to-main.md
---

# SDK Versioning and Migration Infrastructure

## Overview

Implement a complete versioning, release, and migration infrastructure for AISDK so that:

1. The production AIDoctor app is protected from breaking changes via semver pinning
2. v2 development has proper CI/CD and beta testing workflows
3. The SDK is ready for open-source with release automation, licensing, and documentation

This plan has **three sequential phases** -- each must be verified before proceeding. A fourth phase (promoting v2 to main) is documented separately in `.context/plans/aisdk-branch-restructuring-promote-v2-to-main.md` and will execute when v2 is stable.

## Problem Statement

**Current state:** AISDK has zero git tags, zero GitHub Releases, no CI/CD, and no LICENSE file. The production app (AIDoctor) depends on AISDK via `.branch("main")` -- tracking a branch, not a version. There are 41+ Swift files in AIDoctor using AISDK APIs. Any breaking change pushed to `main` immediately breaks production builds.

**Why now:** v2 development is mid-stage on `aisdk-2.0-modernization` (118 commits ahead of main, 167K insertions). Before v2 can be promoted to main, v1 must be tagged and preserved, and AIDoctor must be re-pinned to a stable reference.

## Technical Approach

### Architecture

**Strategy: Release Branch + Main Takeover** (Approach A from brainstorm)

```
main ─ da572cf (tagged 1.0.0) ─────────────────── (v2 merged here, tagged 2.0.0) ──→
  │                                                         ↑
  ├── release/1.x ── 1.0.1 ── 1.0.2 ──→ (critical fixes)  │
  │                                                         │
  └── aisdk-2.0-modernization ── beta.1 ── beta.2 ─────────┘
```

**Key principle:** SPM uses git tags as its version resolution mechanism. `from: "1.0.0"` resolves to `>= 1.0.0, < 2.0.0`, so consumers on v1 are automatically protected from v2.

### Pre-Requisite: Verify Commit Identity

Before any tagging, verify which commit to tag.

**Finding:** `origin/main` HEAD is `da572cf` (Merge pull request #2), which is 2 commits ahead of `9ad6e1f` (the SHA in AIDoctor's `Package.resolved`). Since `.branch("main")` resolves to the branch HEAD on fresh clones, `da572cf` is what SPM would give any new consumer.

**Decision:** Tag `da572cf` as `1.0.0`. This is the true tip of `main` and what any new SPM resolution would return.

**Verification step for AIDoctor:**
```bash
# In the AIDoctor repo, check what SHA Package.resolved actually pins to:
grep -A2 '"aisdk"' AIDoctor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```
If the resolved SHA is `9ad6e1f`, AIDoctor's existing builds won't change (both commits are on `main`, and `from: "1.0.0"` on tag `da572cf` still resolves `da572cf` which is a descendant of `9ad6e1f`). The AIDoctor team should run a full build+test after re-pinning to confirm.

### Pre-Requisite: Protect PR #4

**Risk:** PR #4 (`aisdk-2.0-modernization` -> `main`) is open. If anyone merges it before AIDoctor is re-pinned, 118 v2 commits land on `main` immediately, breaking AIDoctor production builds.

**Action before Phase 1:**
```bash
# Add DO NOT MERGE label
gh pr edit 4 --add-label "DO NOT MERGE"

# Add a comment explaining why
gh pr comment 4 --body "DO NOT MERGE: v1.0.0 tagging and AIDoctor re-pinning must complete before this PR can be merged. See docs/plans/2026-02-11-feat-sdk-versioning-migration-infrastructure-plan.md"
```

**Optionally enable branch protection on main:**
```bash
gh api repos/{owner}/{repo}/branches/main/protection \
  -X PUT \
  -f 'required_pull_request_reviews[required_approving_review_count]=1' \
  -f 'enforce_admins=true'
```

### Implementation Phases

---

## Phase 1: Protect AIDoctor (Immediate Priority)

**Goal:** Tag v1.0.0, create maintenance branch, coordinate AIDoctor re-pinning.

### Phase 1.1: Tag v1.0.0 on main

**Files:** No file modifications -- git operations only.

```bash
# Ensure we have latest remote state
git fetch origin

# Create annotated tag at origin/main HEAD
git tag -a 1.0.0 da572cf4a79e9dbf2390dbd049bcb470dad28218 -m "Release 1.0.0 - Stable AISDK v1"

# Push the tag
git push origin 1.0.0
```

**Verify:**
```bash
git rev-parse 1.0.0  # Must equal da572cf...
```

**Rollback:**
```bash
git push origin --delete 1.0.0 && git tag -d 1.0.0
```

### Phase 1.2: Create release/1.x maintenance branch

```bash
git branch release/1.x origin/main
git push origin release/1.x
```

**Verify:**
```bash
git rev-parse origin/release/1.x  # Must equal da572cf...
```

**Rollback:**
```bash
git push origin --delete release/1.x
```

### Phase 1.3: Create GitHub Release for 1.0.0

```bash
gh release create 1.0.0 \
  --title "AISDK 1.0.0" \
  --notes "$(cat <<'EOF'
## AISDK 1.0.0 - Initial Stable Release

The first tagged release of AISDK, a comprehensive AI SDK for Swift.

### Features
- Multi-provider support (OpenAI, Anthropic, Gemini, OpenRouter)
- Agent system with tool calling
- Streaming chat completion
- Voice and vision capabilities
- SwiftUI integration

### Platform Requirements
- iOS 17+ / macOS 14+ / watchOS 10+ / tvOS 17+
- Swift 5.9+

### Installation (SPM)
```swift
.package(url: "https://github.com/DanielhCarranza/AISDK.git", from: "1.0.0")
```
EOF
)"
```

**Rollback:**
```bash
gh release delete 1.0.0 --yes
```

### Phase 1.4: Coordinate AIDoctor Re-Pinning

Provide the AIDoctor team with this exact change:

**In `AIDoctor.xcodeproj/project.pbxproj`, find and change:**
```
// BEFORE (branch tracking - HIGH RISK):
935BC9212E09F62600EF93A5 /* XCRemoteSwiftPackageReference "AISDK" */ = {
    isa = XCRemoteSwiftPackageReference;
    repositoryURL = "https://github.com/DanielhCarranza/AISDK.git";
    requirement = {
        branch = main;
        kind = branch;
    };
};

// AFTER (semver pinning - SAFE):
935BC9212E09F62600EF93A5 /* XCRemoteSwiftPackageReference "AISDK" */ = {
    isa = XCRemoteSwiftPackageReference;
    repositoryURL = "https://github.com/DanielhCarranza/AISDK.git";
    requirement = {
        kind = upToNextMajorVersion;
        minimumVersion = 1.0.0;
    };
};
```

**Why `upToNextMajorVersion`:** This is the SPM equivalent of `from: "1.0.0"` in Package.swift. It means:
- Resolves any version `>= 1.0.0` and `< 2.0.0`
- Automatically picks up hotfixes (1.0.1, 1.0.2) without manual intervention
- Will NOT pick up 2.0.0 when it's tagged (semver boundary protection)
- The team must explicitly opt in to v2 by changing `minimumVersion` to `2.0.0`

**AIDoctor team checklist:**
- [ ] Create branch `chore/pin-aisdk-v1`
- [ ] Update `project.pbxproj` as shown above
- [ ] Run `xcodebuild -resolvePackageDependencies` (clear SPM caches first if needed: `rm -rf ~/Library/Caches/org.swift.swiftpm/`)
- [ ] Run full build and test suite
- [ ] Verify `Package.resolved` now shows a version instead of a branch
- [ ] Create PR, wait for CI green, merge

### Phase 1.5: Verification Gate

All of the following must be true before proceeding to Phase 2:

| Check | Command | Expected |
|-------|---------|----------|
| Tag exists | `git rev-parse 1.0.0` | `da572cf...` |
| Branch exists | `git rev-parse origin/release/1.x` | `da572cf...` |
| GitHub Release exists | `gh release view 1.0.0` | Shows release |
| AIDoctor re-pinned | Check AIDoctor's merged PR | PR merged, CI green |
| PR #4 still open | `gh pr view 4 --json state` | `"state": "OPEN"` |

---

## Phase 2: Improve v2 Development Workflow

**Goal:** Add CI/CD, establish beta tagging, update development conventions.

### Phase 2.1: Create CI/CD Workflow for Pull Requests

**New file:** `.github/workflows/ci.yml`

```yaml
name: CI

on:
  pull_request:
    branches:
      - main
      - aisdk-2.0-modernization
      - 'release/**'
  push:
    branches:
      - main
      - aisdk-2.0-modernization
      - 'release/**'

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    name: Build & Test
    runs-on: macos-15
    strategy:
      matrix:
        include:
          - scheme: "AISDK"
            platform: "macOS"
            command: "swift build && swift test"
          - scheme: "AISDK"
            platform: "iOS Simulator"
            command: "xcodebuild build -scheme AISDK -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -skipPackagePluginValidation"
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.2.app

      - name: Resolve dependencies
        run: swift package resolve

      - name: ${{ matrix.platform }}
        run: ${{ matrix.command }}
        env:
          AISDK_PAT: ${{ secrets.AISDK_PAT }}
```

**Design decisions:**
- Tests on macOS (fast, catches logic errors) and build on iOS Simulator (catches platform availability issues)
- No watchOS/tvOS in CI (no known consumers, adds cost) -- can add later
- Concurrency group cancels stale runs when new commits push
- Triggers on PRs to all three key branches: `main`, `aisdk-2.0-modernization`, and `release/**`
- Uses `AISDK_PAT` secret for private dependency resolution (already used in AIDoctor CI)

### Phase 2.2: Create Release Automation Workflow

**New file:** `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags:
      - '[0-9]+.[0-9]+.[0-9]+'
      - '[0-9]+.[0-9]+.[0-9]+-*'

jobs:
  test:
    name: Verify
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.2.app
      - name: Build
        run: swift build
      - name: Test
        run: swift test

  release:
    name: Create GitHub Release
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Determine pre-release status
        id: prerelease
        run: |
          TAG="${GITHUB_REF#refs/tags/}"
          if [[ "$TAG" == *"-"* ]]; then
            echo "is_prerelease=true" >> "$GITHUB_OUTPUT"
          else
            echo "is_prerelease=false" >> "$GITHUB_OUTPUT"
          fi

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
          prerelease: ${{ steps.prerelease.outputs.is_prerelease }}
```

**Design decisions:**
- Triggers on any semver tag, including pre-release (e.g., `2.0.0-beta.1`)
- Runs build+test before creating the release (safety gate)
- Auto-detects pre-release tags (contains `-`) and marks GitHub Release accordingly
- Uses GitHub's auto-generated release notes (commit-based) -- can be enhanced later with CHANGELOG excerpts

### Phase 2.3: Establish Beta Tagging Process

Document the beta workflow for v2 pre-releases:

```bash
# When a v2 milestone is ready for AIDoctor testing:
git checkout aisdk-2.0-modernization
git pull origin aisdk-2.0-modernization

# Tag the beta
git tag -a 2.0.0-beta.1 -m "AISDK 2.0.0 Beta 1 - [brief description of what's included]"
git push origin 2.0.0-beta.1

# The release workflow auto-creates a GitHub Release marked as pre-release
```

**AIDoctor beta testing:**
```swift
// In AIDoctor's project.pbxproj, temporarily change to:
requirement = {
    kind = exactVersion;
    version = "2.0.0-beta.1";
};

// To revert to stable v1:
requirement = {
    kind = upToNextMajorVersion;
    minimumVersion = 1.0.0;
};
```

**Important SPM behavior:** Pre-release tags are NOT resolved by range-based requirements (`from:`, `upToNextMajor`). Consumers MUST use `.exact("2.0.0-beta.1")` to test betas. This is by design -- it prevents accidental adoption of pre-release code.

### Phase 2.4: Update Development Conventions

**Modify:** `CLAUDE.md` -- add release conventions section

Add after the existing PR Workflow section:

```markdown
## Versioning and Releases

- Tags use bare semver format: `1.0.0`, `2.0.0-beta.1` (NO `v` prefix -- SPM requires this)
- `release/1.x` branch: v1 maintenance (critical bug fixes only, tagged as `1.0.1`, `1.0.2`, etc.)
- Beta tags on `aisdk-2.0-modernization`: `2.0.0-beta.N` for AIDoctor testing
- GitHub Releases are auto-created when tags are pushed (via `.github/workflows/release.yml`)
```

**Modify:** `AGENTS.md` -- add versioning section

Add after the existing Commits section:

```markdown
## Versioning

- Follow Semantic Versioning (semver.org)
- Tag format: `X.Y.Z` or `X.Y.Z-prerelease` (no `v` prefix)
- CHANGELOG follows Keep a Changelog format (keepachangelog.com)
```

### Phase 2.5: v1 Hotfix Flow

Document how critical bugs in v1 are handled:

1. Create a branch from `release/1.x`:
   ```bash
   git checkout -b fix/description release/1.x
   ```
2. Apply the fix, build, test
3. Create PR targeting `release/1.x`
4. After merge, tag the new version:
   ```bash
   git checkout release/1.x
   git pull origin release/1.x
   git tag -a 1.0.1 -m "Release 1.0.1 - [fix description]"
   git push origin 1.0.1
   ```
5. The release workflow auto-creates a GitHub Release
6. AIDoctor on `upToNextMajorVersion: 1.0.0` auto-picks up the fix on next resolve

### Phase 2 Verification Gate

| Check | Command | Expected |
|-------|---------|----------|
| CI runs on PR | Open a test PR to `aisdk-2.0-modernization` | CI passes |
| CI runs on release/1.x | Open a test PR to `release/1.x` | CI passes |
| Release workflow works | Push a test tag (e.g., on release/1.x as 1.0.1-test, then delete) | GitHub Release created |
| CLAUDE.md updated | Read CLAUDE.md | Contains versioning section |
| AGENTS.md updated | Read AGENTS.md | Contains versioning section |

---

## Phase 3: Release Infrastructure (Before Open-Source)

**Goal:** Add LICENSE, README, version constant, finalize CHANGELOG, update existing migration plan.

### Phase 3.1: Add LICENSE File

**New file:** `LICENSE`

License choice is an open question from the brainstorm. MIT is the most common for Swift open-source SDKs (used by Alamofire, Kingfisher, SnapKit, etc.).

**Decision needed from team:** MIT vs Apache 2.0 vs other

### Phase 3.2: Add Root README.md

**New file:** `README.md`

Should include:
- Project name and brief description
- Badges (CI status, Swift version, platforms, SPM compatible, license)
- Installation instructions (SPM)
- Quick start code example
- Link to full documentation (`docs/`)
- Link to migration guide (`docs/MIGRATION-GUIDE.md`)
- Link to CHANGELOG
- License

### Phase 3.3: Add Version Constant to Source

**Modify:** `Sources/AISDK/AISDK.swift` (currently 3 lines -- a placeholder)

```swift
// The Swift Programming Language
// https://docs.swift.org/swift-book

/// The AISDK namespace.
public enum AISDK {
    /// The current version of the AISDK library.
    public static let version = "2.0.0"
}
```

**Note:** This constant is manually maintained. For automated version syncing, a future improvement could use a build plugin or script that reads the latest git tag. For now, manual is acceptable -- the release checklist will include verifying this matches the tag.

### Phase 3.4: Finalize CHANGELOG.md

**Modify:** `CHANGELOG.md`

Issues to fix:
1. **Missing `[Unreleased]` section** at top (Keep a Changelog convention)
2. **`[1.1.0]` entry describes v2 features** (universal message system, @Observable migration) that don't exist on `main`. This should be renamed to `[2.0.0]` or incorporated into the 2.0.0 entry.
3. **Date inconsistency**: 1.0.0 is dated 2025-06-28 but 1.1.0 is dated 2025-01-28 (earlier than 1.0.0)
4. **Missing footer links** for version comparison URLs

**Proposed structure:**
```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - YYYY-MM-DD
[Comprehensive entry covering all v2 changes -- to be finalized at release]
See docs/WHATS_NEW_AISDK_2.md for the full feature list.
See docs/MIGRATION-GUIDE.md for the v1 to v2 migration guide.

### Breaking Changes
- `Agent` class replaced by `AIAgentActor` actor
- `LLM` protocol replaced by `AILanguageModel` protocol
- Message types changed to `AIInputMessage` system
- `@ObservableObject`/`@Published` replaced by `@Observable`

### Added
- Actor-based agent system with Swift Concurrency
- Generative UI with JSON-render pattern
- OpenRouter and LiteLLM provider support
- Circuit breaker and adaptive failover reliability framework
- MCP (Model Context Protocol) integration
- Comprehensive AIError taxonomy
- Skills system
- Telemetry framework

## [1.0.0] - 2025-06-28
[Existing 1.0.0 entry preserved as-is]

[Unreleased]: https://github.com/DanielhCarranza/AISDK/compare/2.0.0...HEAD
[2.0.0]: https://github.com/DanielhCarranza/AISDK/compare/1.0.0...2.0.0
[1.0.0]: https://github.com/DanielhCarranza/AISDK/releases/tag/1.0.0
```

### Phase 3.5: Update Package.swift Version Comment

**Modify:** `Package.swift` line 8

```swift
// BEFORE:
// Version: 1.0.0 - Comprehensive AI SDK for Swift

// AFTER:
// Version: 2.0.0 - Comprehensive AI SDK for Swift
```

This is done on `aisdk-2.0-modernization` as part of the metadata preparation before promoting to main.

### Phase 3.6: Update Existing Migration Plan

**Modify:** `.context/plans/aisdk-branch-restructuring-promote-v2-to-main.md`

Fix the following issues identified by spec-flow analysis:

| Line | Issue | Fix |
|------|-------|-----|
| 42 | `git branch v1.x origin/main` | Change to `release/1.x` (or note that release/1.x already exists from our Phase 1) |
| 44 | `git tag v1.0.0 da572cf...` | Note that `1.0.0` tag already exists from our Phase 1 |
| 66 | `branch = "v1.x"` | Change to `upToNextMajorVersion; minimumVersion = 1.0.0;` (or note already done) |
| 179 | `git tag v2.0.0 origin/main` | Change to `git tag -a 2.0.0 origin/main -m "Release 2.0.0"` (remove `v` prefix!) |
| 180 | `git push origin v2.0.0` | Change to `git push origin 2.0.0` |

**Critical bug:** The `v` prefix on tags (`v1.0.0`, `v2.0.0`) throughout the existing plan will cause SPM to not resolve those tags as semantic versions. SPM requires bare `X.Y.Z` format. All tag references in the plan must be corrected.

### Phase 3.7: Cleanup Commented-Out Products

**Decision needed:** The 4 commented-out products in Package.swift (`AISDKChat`, `AISDKVoice`, `AISDKVision`, `AISDKResearch`) and their corresponding targets should be:

- **Option A:** Removed entirely if they are not part of v2's public API
- **Option B:** Uncommented and properly implemented if they are part of v2
- **Option C:** Left as-is if they are planned for future minor versions (2.1.0, 2.2.0)

This affects what ships in the v2.0.0 tag.

### Phase 3 Verification Gate

| Check | Command | Expected |
|-------|---------|----------|
| LICENSE exists | `cat LICENSE` | License text |
| README exists | `cat README.md` | Installation instructions |
| Version constant | `grep "version" Sources/AISDK/AISDK.swift` | `"2.0.0"` |
| CHANGELOG has [Unreleased] | `head -10 CHANGELOG.md` | `## [Unreleased]` section |
| CHANGELOG has 2.0.0 | `grep "2.0.0" CHANGELOG.md` | Entry exists |
| Existing plan updated | `grep "v2.0.0" .context/plans/*.md` | No `v` prefix on tags |
| Package.swift version | `head -10 Package.swift` | `Version: 2.0.0` |
| Build succeeds | `swift build` | Success |
| Tests pass | `swift test` | All pass |

---

## Phase 4: Promote v2 to Main (Endgame)

**Documented at:** `.context/plans/aisdk-branch-restructuring-promote-v2-to-main.md`

This phase executes when v2 is stable and ready for release. It has its own 5-phase plan with rollback procedures and verification checklists. Key corrections needed (from Phase 3.6 above) must be applied before execution.

**Summary of the endgame:**
1. Pre-flight notification (30-min window)
2. Verify `release/1.x` branch and `1.0.0` tag exist (already done in our Phase 1)
3. Verify AIDoctor is pinned to semver, not branch (already done in our Phase 1)
4. Prepare metadata commit on `aisdk-2.0-modernization` (Package.swift, CLAUDE.md, conductor-setup.sh, CHANGELOG)
5. Fast-forward `main` to `aisdk-2.0-modernization` (merge PR #4 or manual `--ff-only`)
6. Tag `2.0.0` on new main HEAD
7. Delete `aisdk-2.0-modernization` branch
8. Notify collaborators

---

## Alternative Approaches Considered

**Approach B: Permanent Version Branches** -- Rejected because `main` would become stale and confusing; non-standard for Swift SDKs.

**Approach C: Gradual Deprecation Bridge (TCA model)** -- Rejected because v2 is too large a rewrite (167K insertions, 8 new subsystems) for incremental deprecation to be practical. However, the existing migration adapters in `Core/Adapters/Legacy/` serve a similar purpose within v2 itself.

## Acceptance Criteria

### Functional Requirements

- [ ] `1.0.0` tag exists on `main` and is resolvable by SPM consumers using `from: "1.0.0"`
- [ ] `release/1.x` branch exists and can receive hotfix PRs
- [ ] AIDoctor is pinned to `upToNextMajorVersion: 1.0.0` and builds successfully
- [ ] CI runs on PRs to `aisdk-2.0-modernization`, `main`, and `release/**`
- [ ] Pushing a semver tag auto-creates a GitHub Release
- [ ] Beta tags (e.g., `2.0.0-beta.1`) create pre-release GitHub Releases
- [ ] Hotfixes to `release/1.x` tagged as `1.0.x` are auto-picked up by AIDoctor
- [ ] CHANGELOG follows Keep a Changelog format with accurate version history
- [ ] LICENSE file exists at repo root
- [ ] README.md exists at repo root with installation instructions
- [ ] Version constant in source matches the tagged version

### Non-Functional Requirements

- [ ] Zero downtime for AIDoctor during the entire migration
- [ ] Rollback from any phase takes < 5 minutes
- [ ] No force-pushes to `main` during any phase
- [ ] PR #4 is protected from accidental merge until endgame

### Quality Gates

- [ ] `swift build` passes after each phase
- [ ] `swift test` passes after each phase
- [ ] Each phase's verification gate passes before proceeding

## Dependencies & Prerequisites

| Dependency | Status | Required By |
|------------|--------|-------------|
| Access to push tags to origin | Assumed available | Phase 1 |
| `gh` CLI installed and authenticated | Assumed available | Phase 1 |
| AIDoctor team availability for re-pinning | Coordination needed | Phase 1.4 |
| `AISDK_PAT` GitHub Actions secret | Exists in AIDoctor CI, needs adding to AISDK repo | Phase 2.1 |
| License decision (MIT vs Apache 2.0) | Open question | Phase 3.1 |
| Commented-out products decision | Open question | Phase 3.7 |

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| PR #4 accidentally merged before AIDoctor re-pins | Low | **Critical** -- breaks production | Add "DO NOT MERGE" label + branch protection |
| Wrong commit tagged as 1.0.0 | Low | High -- mismatch with production | Verify `origin/main` HEAD before tagging |
| AIDoctor SPM cache returns stale result after re-pin | Medium | Medium -- build uses old code | Clear SPM caches before resolving |
| CI fails on first run due to missing secrets | High | Low -- delays Phase 2, no production impact | Test with a draft PR first |
| Tag pushed with `v` prefix (SPM won't resolve) | Medium | High -- invisible to consumers | Document "no v prefix" rule, verify in release workflow |
| Concurrent push to main during tagging | Low | Medium -- fast-forward assumption breaks | Pre-flight notification, short window |
| CHANGELOG confuses consumers (1.1.0 describing v2 features) | Medium | Low -- cosmetic | Clean up in Phase 3.4 |

## Open Questions

1. **License choice:** MIT or Apache 2.0? (Blocks Phase 3.1)
2. **Commented-out products:** Remove, implement, or defer? (Blocks Phase 3.7)
3. **v1 EOL timeline:** How long after v2.0.0 release should `release/1.x` receive maintenance?
4. **AISDK_PAT secret:** Does this need to be added to the AISDK repo's GitHub Actions secrets for CI? (Currently only in AIDoctor's CI)
5. **Xcode version for CI:** Pin to 16.2, or use latest?

## References & Research

### Internal References

- Brainstorm: `docs/brainstorms/2026-02-11-sdk-versioning-migration-strategy-brainstorm.md`
- Existing endgame plan: `.context/plans/aisdk-branch-restructuring-promote-v2-to-main.md`
- Migration guide: `docs/MIGRATION-GUIDE.md` (608 lines)
- v2 feature summary: `docs/WHATS_NEW_AISDK_2.md` (369 lines)
- Architecture: `docs/AISDK-ARCHITECTURE.md`
- Package manifest: `Package.swift` (211 lines)
- Conductor setup: `scripts/conductor-setup.sh` (75 lines)

### External References

- [SPM Releasing and Publishing Guide](https://github.com/swiftlang/swift-package-manager/blob/main/Sources/PackageManagerDocs/Documentation.docc/ReleasingPublishingAPackage.md)
- [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
- [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
- [Alamofire 5.0 Migration Guide](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Alamofire%205.0%20Migration%20Guide.md)
- [TCA 1.0 Migration](https://www.pointfree.co/blog/posts/112-composable-architecture-1-0)
- [Automating Swift Package Releases](https://www.polpiella.dev/automating-swift-package-releases-with-github-actions/)

### Related Work

- PR #4: `aisdk-2.0-modernization` -> `main` (DO NOT MERGE until endgame)
- AIDoctor dependency: `AIDoctor.xcodeproj/project.pbxproj` lines ~989-996

## Implementation Summary

```
Phase 1 (immediate):     Tag 1.0.0 → release/1.x branch → GitHub Release → AIDoctor re-pin
Phase 2 (next):          CI/CD workflows → beta tagging process → convention updates
Phase 3 (before open-source): LICENSE → README → version constant → CHANGELOG → fix existing plan
Phase 4 (when v2 ready): Execute endgame plan → merge to main → tag 2.0.0 → cleanup
```

Each phase has explicit verification gates. No phase proceeds until the prior phase's gate passes.
