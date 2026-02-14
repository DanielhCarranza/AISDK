# Layer 3 SDK Explorer Demo Runbook

## Goal

Demonstrate, in under 10 minutes, that AISDK 2.0 works as a production-capable, agent-native runtime in a real iOS app on both simulator and physical device.

This runbook is optimized for stakeholder demos, release readiness checks, and repeatable validation sessions.

---

## Prerequisites

- `Examples/SDKExplorer.xcworkspace` builds in Xcode.
- `.env` (or equivalent config) includes valid provider keys for OpenAI, Anthropic, and Gemini.
- A physical iOS device is available for the final verification pass.
- Network access is stable.

---

## Demo Scope

The runbook validates four outcomes:

1. **Technical robustness**: streaming, tools, sessions, provider switching, compaction.
2. **Agent-native behavior**: unified agent runtime, parity, composability, emergent capability.
3. **Operational reliability**: diagnostics checks pass with actionable failures.
4. **Evidence generation**: exportable artifacts exist for reproducible review.

---

## 10-Minute Demo Script

### Step 1: Launch and sanity check (1 minute)

1. Open `Examples/SDKExplorer.xcworkspace`.
2. Run on iOS simulator.
3. Confirm three tabs render: **Chat**, **Sessions**, **Diagnostics**.

**Pass criteria**
- App launches without crashes.
- Provider selector is visible in Chat.

### Step 2: Streaming and tool loop (2 minutes)

1. In Chat, select OpenAI.
2. Send: `What's 5 + 3, then multiply by 4 and explain your steps briefly.`
3. Observe token streaming and inline tool activity.

**Pass criteria**
- Tokens stream incrementally.
- Agent performs tool calls and returns coherent final output.

### Step 3: Cross-provider continuation mission (1 minute)

1. Run `CrossProviderContinuation` mission card (or perform equivalent manual flow).
2. Start on OpenAI, switch to Anthropic mid-thread, continue conversation.

**Pass criteria**
- Context remains coherent after switching provider.
- No app-level format adapter workaround is needed in UI flow.

### Step 4: Generative UI and long-context compaction (2 minutes)

1. Run `GenerativeUICard` mission and confirm inline UITree card rendering.
2. Run `LongContextCompaction` mission:
   - Build up long conversation.
   - Compact session.
   - Ask a follow-up question about earlier context.

**Pass criteria**
- UITree card renders inline in chat.
- Token count decreases post-compaction.
- Follow-up response remains contextually correct.

### Step 5: Persistence and cold-start continuity (1 minute)

1. Move to Sessions tab and confirm active session is listed.
2. Terminate app, relaunch.
3. Restore previous session in Chat.

**Pass criteria**
- Session persists across app restart for persistent stores.
- Conversation continues without data loss.

### Step 6: Diagnostics + evidence export (2 minutes)

1. Open Diagnostics tab and run all checks.
2. Export evidence bundle.

**Pass criteria**
- Diagnostics show pass state (or explicit actionable failures).
- Export generates both JSON and markdown artifacts with timestamp.

### Step 7: Physical device confirmation (1 minute)

1. Build and run same flow on physical device.
2. Repeat at least one mission plus diagnostics export.

**Pass criteria**
- Core mission succeeds on device.
- Device evidence bundle is generated.

---

## Agent-native Proof Checklist

- [ ] **Parity**: Every user-visible Layer 3 action has an agent/runtime capability path.
- [ ] **Composability**: At least one mission behavior changed via prompt-only edit (no code change).
- [ ] **Emergent capability**: One open-ended request succeeds (or logs a concrete parity gap).
- [ ] **Completion signaling**: Multi-step missions show explicit completion state.

---

## Evidence Bundle Requirements

Each exported bundle should include:

- Timestamp, app version, device info, OS version.
- Mission-level outcomes: pass/fail, provider(s), latency, retries, token usage if available.
- Diagnostics outcomes: provider health, store parity, UITree parsing, stream ordering.
- Notes field for any observed caveats.

Suggested artifact names:

- `sdk-explorer-evidence-<timestamp>.json`
- `sdk-explorer-evidence-<timestamp>.md`

---

## Failure Handling Guide

If a step fails during demo:

1. Capture failure in evidence markdown with:
   - Mission/test name
   - Provider
   - Error message
   - Recovery outcome
2. Retry once with same provider.
3. Retry with alternate provider.
4. If still failing, mark as blocker and map to Layer 2/Layer 4 follow-up:
   - Contract shape issue -> Layer 4
   - Streaming/order issue -> Layer 2 correctness
   - App UX/state issue -> Layer 3 implementation

---

## Sign-off Criteria

Layer 3 demo sign-off is complete when:

- All core mission cards pass on simulator and at least one physical device.
- Diagnostics pass (or failures are actionable and logged).
- Evidence bundle exists for simulator and device runs.
- Agent-native proof checklist is complete.
