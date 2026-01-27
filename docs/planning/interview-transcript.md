# AISDK Modernization - Stakeholder Interview Transcript

**Date**: 2026-01-22
**Interviewer**: GEPETTO Planning System
**Stakeholder**: Joel Mushagasha (Project Owner)

---

## Interview Round 1: Core Architecture Decisions

### Q1: Provider Priority
**Question**: Research found OpenAI is most mature, Anthropic uses compatibility layer, Gemini has API inconsistencies. Which provider should be the PRIMARY fallback target?

**Answer**: GPT-5 models (5.x series) should be the default, but the system must be model-agnostic so providers can be changed. Default to GPT-5-mini. The architecture must support seamless provider switching.

### Q2: Streaming Event Model
**Question**: Vercel uses 10+ event types (text-delta, tool-call-start, step-finish, etc.). How granular should Swift streaming events be?

**Answer**: **Full parity (10+ events matching Vercel exactly)**

Required event types:
- `textDelta` - Incremental text chunks
- `textCompletion` - Full text complete
- `toolCallStart` - Tool invocation begins
- `toolCallDelta` - Streaming tool arguments
- `toolCallFinish` - Tool arguments complete
- `toolResult` - Tool execution result
- `stepFinish` - Agent step complete
- `finish` - Generation complete with usage
- `error` - Stream errors

### Q3: AITool Call Repair
**Question**: How should AISDK handle malformed tool calls?

**Answer**: **Hybrid approach** - Auto-repair once (LLM fixes its own mistakes), then fail with detailed error if second attempt also fails.

### Q4: Circuit Breaker Configuration
**Question**: For 99.9% uptime, what failure threshold should trigger provider failover?

**Answer**: Use **state-of-the-art adaptive approach** for 99.99% uptime:
- Error-type awareness (distinguish auth errors vs rate limits vs timeouts)
- Exponential backoff with jitter
- Health checks during half-open state
- Netflix Hystrix/Resilience4j-style patterns

---

## Interview Round 2: Implementation Details

### Q5: Generative UI Scope
**Question**: For SwiftUI dynamic rendering from LLM responses, what component types should be supported?

**Answer**: **Progressive approach** - Start with basic components, build foundation for medical-specific later.

Reference implementation: `vercel-labs/json-render` - Study this for the catalog/registry pattern.

### Q6: Testing Strategy
**Question**: How should we balance test reliability vs coverage?

**Answer**: **Hybrid approach**
- Mock providers for unit tests (deterministic, fast CI)
- Real API calls for integration tests (realistic validation)

### Q7: LiteLLM vs OpenRouter
**Question**: For model routing, which is preferred?

**Answer**: **OpenRouter primary** (managed, easier)
- LiteLLM remains supported as an option
- OpenRouter is the default for production use

### Q8: Breaking Changes
**Question**: Current Agent.swift is 656 lines. How much refactoring is acceptable?

**Answer**: **Full rewrite acceptable (clean slate)**
- No need to preserve backward compatibility
- Can redesign from ground up
- Migration guide required for existing users

---

## Interview Round 3: Technical Specifics

### Q9: Generative UI Components
**Question**: Which basic components should be in the initial Swift catalog?

**Answer**: **Core 8 components**:
1. `Text` - Basic text display
2. `Button` - Interactive buttons with actions
3. `Card` - Container with title/content
4. `Input` - Text input fields
5. `List` - Ordered/unordered lists
6. `Image` - Image display with URL
7. `Stack` - VStack/HStack layout
8. `Spacer` - Flexible spacing

### Q10: Agent Concurrency
**Question**: Should the new agent use Swift actors for thread safety?

**Answer**: **Yes - full actor-based isolation**
- Agent should be an actor for thread safety
- State mutations properly isolated
- Callbacks can still be used for hooks

### Q11: Metadata Tracking
**Question**: Current SDK has innovative RenderMetadata system. Should this be expanded?

**Answer**: **Keep UI rendering focus for now**
- Preserve current RenderMetadata approach
- Full telemetry (cost tracking, latency, tokens, error rates) as **optional add-on**
- Make telemetry the last part of implementation
- Keep it pluggable for future expansion

### Q12: Documentation Priority
**Question**: What docs are most critical for launch?

**Answer**: **Full docs with tutorials and examples**
- Complete API reference
- Migration guide from old API
- Tutorials for common use cases
- Working code examples

---

## Summary of Key Decisions

| Area | Decision |
|------|----------|
| **Default Provider** | GPT-5-mini (model-agnostic) |
| **Routing** | OpenRouter primary, LiteLLM supported |
| **Streaming Events** | Full Vercel parity (10+ events) |
| **Tool Repair** | Hybrid (auto-repair once, then fail) |
| **Circuit Breaker** | Adaptive/smart with error-type awareness |
| **Generative UI** | Progressive, Core 8 components |
| **UI Pattern** | json-render catalog/registry pattern |
| **Concurrency** | Full actor-based isolation |
| **Breaking Changes** | Full rewrite acceptable |
| **Testing** | Hybrid (mocks + real API) |
| **Metadata** | UI focus now, telemetry later |
| **Documentation** | Full with tutorials |

---

## Technical Constraints Confirmed

- **Platform**: iOS 17+, macOS 14+, watchOS 10+, tvOS 17+
- **Swift**: 5.9+ (for actors, async/await)
- **Reliability Target**: 99.99% uptime
- **Use Case**: AI doctor application (healthcare-critical)

---

## Next Steps

1. Synthesize findings into comprehensive specification
2. Generate detailed implementation plan
3. External review with Gemini and Codex
4. Integrate feedback
5. User approval before implementation
