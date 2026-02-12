# AISDK Versioning and Migration Strategy

**Date:** 2026-02-11
**Status:** Approved
**Participants:** Joel, Claude

---

## What We're Building

A versioning, release, and migration infrastructure for AISDK that:

1. **Protects the production AIDoctor app** by tagging v1.0.0 and moving it off branch-tracking to semver pinning
2. **Enables safe v2 development** with proper branching, beta tags, and the ability to downgrade
3. **Sets up release infrastructure** (tags, CHANGELOG, CI/CD, GitHub Releases) for open-source readiness

## Why This Approach

**Chosen: Approach A - Release Branch + Main Takeover**

This is the industry standard used by Alamofire, Firebase iOS SDK, and most mature Swift packages. It was chosen over:

- **Permanent version branches** (Approach B): Non-standard, confusing for contributors, `main` becomes stale
- **Gradual deprecation bridge** (Approach C): v2 is too large a rewrite (167K insertions, 8 new subsystems) for incremental deprecation to be practical

Approach A gives us:
- `main` always represents the latest stable major version (familiar to every developer)
- `release/1.x` as a maintenance branch for the production safety net
- Clean semver boundaries that SPM enforces automatically (`from: "1.0.0"` never picks up `2.0.0`)
- Beta tags for pre-release testing of v2 in AIDoctor before committing

## Key Decisions

### 1. v1 Tagging and Protection (Priority 1 - Do First)

| Decision | Choice |
|----------|--------|
| Which commit to tag as 1.0.0 | `9ad6e1f` (current tip of `main`, what AIDoctor is pinned to) |
| Tag format | `1.0.0` (no `v` prefix - SPM standard) |
| Maintenance branch name | `release/1.x` (industry standard) |
| AIDoctor update | Coordinate with team - provide exact Package.swift change |

**Sequence:**
1. Tag `9ad6e1f` as `1.0.0` on `main`
2. Create `release/1.x` branch from `main`
3. Create GitHub Release for 1.0.0
4. Coordinate AIDoctor update: `.branch("main")` -> `.package(from: "1.0.0")`

**AIDoctor Package.swift Change Required:**
```swift
// BEFORE (current - tracks main branch, HIGH RISK):
.package(url: "https://github.com/DanielhCarranza/AISDK.git", branch: "main")

// AFTER (pinned to semver, SAFE):
.package(url: "https://github.com/DanielhCarranza/AISDK.git", from: "1.0.0")
```

This single change means:
- AIDoctor will resolve any version `>= 1.0.0` and `< 2.0.0`
- When `2.0.0` is tagged, AIDoctor will NOT automatically pick it up
- The team must explicitly change to `from: "2.0.0"` when ready to migrate
- Package.resolved will pin to the exact resolved version for reproducible builds

### 2. Branch Strategy

```
main ─── (frozen, tagged 1.0.0) ──────────────────── (v2 merged here, tagged 2.0.0) ──→
  │                                                          ↑
  ├── release/1.x ── 1.0.1 ── 1.0.2 ──→ (critical fixes)   │
  │                                                          │
  └── aisdk-2.0-modernization ── beta.1 ── beta.2 ──────────┘
```

| Branch | Purpose | Who Commits | Lifetime |
|--------|---------|-------------|----------|
| `main` | Latest stable major version | Merge only | Permanent |
| `release/1.x` | v1 maintenance (bug fixes, security patches) | Direct commits + PRs | Until v1 EOL |
| `aisdk-2.0-modernization` | v2 development | Direct commits + PRs | Until merged to main |

### 3. Version Numbering

```
1.0.0           ← Retroactive tag on main (current stable)
1.0.1, 1.0.2   ← Bug fixes on release/1.x (as needed)
2.0.0-beta.1    ← First v2 beta for AIDoctor testing
2.0.0-beta.N    ← Subsequent betas as needed
2.0.0           ← v2 stable release (merged to main)
2.0.1, 2.1.0   ← Post-release patches and features
```

**Beta tag usage:** SPM does not resolve pre-release tags through standard `from:` requirements. AIDoctor will test betas using exact pinning:
```swift
.package(url: "https://github.com/DanielhCarranza/AISDK.git", exact: "2.0.0-beta.1")
```

### 4. v1/v2 Coexistence and Downgrade Safety

The ability to downgrade from v2 back to v1 is guaranteed by design:

- **AIDoctor on v1:** Uses `from: "1.0.0"` - completely isolated from v2
- **AIDoctor testing v2 beta:** Uses `exact: "2.0.0-beta.1"` - can revert by changing back to `from: "1.0.0"`
- **AIDoctor on v2 stable:** Uses `from: "2.0.0"` - can downgrade by changing back to `from: "1.0.0"`
- **v1 bug fixes:** Shipped as `1.0.1` etc. on `release/1.x` - available to anyone on `from: "1.0.0"`

The downgrade path is always: change one line in Package.swift and re-resolve.

### 5. Release Infrastructure (Priority 3)

| Artifact | Status | Action Needed |
|----------|--------|---------------|
| Git tags | None exist | Tag 1.0.0, then ongoing |
| CHANGELOG.md | Exists (1.0.0, 1.1.0 entries) | Update with 2.0.0 entry when ready |
| GitHub Releases | None exist | Create for 1.0.0, automate for future |
| CI/CD (GitHub Actions) | None exist | Add build/test on PR + release workflow |
| LICENSE | Missing | Add before open-sourcing |
| Root README.md | Missing | Add before open-sourcing |
| Migration Guide | Exists at docs/MIGRATION-GUIDE.md | Review and finalize for v2 release |

### 6. Execution Order

Work is strictly sequential - each step must be verified before proceeding.

**Step 1: Protect AIDoctor (immediate)**
- [ ] Tag `9ad6e1f` as `1.0.0`
- [ ] Push tag to origin
- [ ] Create `release/1.x` branch from main
- [ ] Create GitHub Release for 1.0.0
- [ ] Provide AIDoctor team with exact Package.swift change
- [ ] Verify AIDoctor builds and tests pass with the version-pinned dependency

**Step 2: Improve v2 Development Workflow (next)**
- [ ] Add CI/CD: GitHub Actions for build + test on PRs to `aisdk-2.0-modernization`
- [ ] Add CI/CD: GitHub Actions for build + test on PRs to `release/1.x`
- [ ] Establish beta tagging process for v2 pre-releases
- [ ] Update CLAUDE.md and AGENTS.md with new branch/release conventions

**Step 3: Release Infrastructure (before open-source)**
- [ ] Add LICENSE file (choose license)
- [ ] Add root README.md
- [ ] Add automated release workflow (tag push triggers GitHub Release)
- [ ] Finalize CHANGELOG.md with 2.0.0 entry
- [ ] Review and polish docs/MIGRATION-GUIDE.md
- [ ] Consider adding a VERSION file or version constant in source

## Open Questions

1. **License choice:** What open-source license will AISDK use? (MIT, Apache 2.0, etc.)
2. **v1 EOL timeline:** How long after v2 stable release should v1 receive maintenance? (3 months? 6 months?)
3. **CI secrets:** The AIDoctor CI uses `AISDK_PAT` - will this need updating when the repo goes public?
4. **Package products:** Several products are commented out in Package.swift (AISDKChat, AISDKVoice, AISDKVision, AISDKResearch). Should these be cleaned up before v2 release?

## Research References

Patterns studied from real-world Swift SDKs:
- **Alamofire** (v4->v5): Release branches, migration guides per major version, extended beta period
- **Firebase iOS SDK**: Single main branch, unified versioning across components, sophisticated CI/CD
- **TCA / Composable Architecture** (0.x->1.0): Gradual deprecation across minor versions, in-source migration guides
- **Realm Swift**: Detailed CHANGELOG with Breaking Changes sections, automatic data migration with backup

SPM versioning behavior:
- Tags must be `X.Y.Z` format (no `v` prefix)
- `from: "1.0.0"` resolves to `>= 1.0.0, < 2.0.0` (major version boundary protection)
- Pre-release tags (e.g., `2.0.0-beta.1`) require `exact:` pinning by consumers
- `Package.resolved` lockfile provides reproducible builds between tag updates
