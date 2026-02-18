---
title: "feat: AIAgent Skills Protocol Support (.aidoctor)"
type: feat
date: 2026-01-28
---

# AIAgent Skills Protocol Support (.aidoctor)

## Context
- Modern agent stacks (Claude Code Agents SDK, OpenAI Codex/Responses, Cursor) expose the open Agent Skills protocol to load task-specific capabilities at runtime.
- We need equivalent support in `AIAgent`, but with a repo-specific convention: skills live under `.aidoctor/skills/` (project scope) and `~/.aidoctor/skills/` (user scope), not `.claude` or `.codex`.
- Skills are discrete, discoverable capability bundles described by `SKILL.md` with YAML frontmatter + Markdown body, optional `scripts/`, `references/`, and `assets/`. Agents do progressive disclosure: list metadata up front, fetch full content when a skill is activated, fetch referenced files only when required.

## Goals
- Discover and register Skills Protocol skills from `.aidoctor/skills/` (project) and `~/.aidoctor/skills/` (user), surfacing their metadata to the LLM as available tools/capabilities.
- Allow `AIAgent` to activate and consume skills during a conversation, including reading `SKILL.md` and executing bundled scripts via existing tool executors.
- Validate skills on load (schema + constraints) and block malformed skills with actionable errors.
- Provide unit and live tests with real example skills to ensure end-to-end activation and execution.

## Non-Goals
- No custom deviation from the Skills Protocol file format beyond the directory naming change.
- No new transport/tooling beyond reusing existing tool execution surface (shell/file read).
- No bundling of third-party skills by default; shipping only examples for tests and docs.

## Skills Protocol Requirements (short form)
- `SKILL.md` must contain YAML frontmatter with at least `name` and `description` (<= 280 chars, ASCII recommended), optional `license`, `compatibility`, `metadata`, `allowed-tools`.
- Optional subfolders: `scripts/` (executable helpers), `references/` (text/data), `assets/` (media). Paths are relative to the skill root.
- Agents should list skills by metadata only, then lazily read bodies and files when invoked.
- Recommended tooling: `skills-ref validate <path>` and `skills-ref to-prompt <path>` for prompt-ready XML metadata.

## Conventions for AIAgent
- Skill roots (ordered search):
  1) `.aidoctor/skills/` at workspace root
  2) `~/.aidoctor/skills/` for user/global
- `SKILL.md` size guardrail: hard cap 500 lines / 32 KB to avoid prompt bloat; warn and skip if exceeded.
- Namespacing: expose skills as `skill::<name>` in prompt metadata; retain original `name` in logs/telemetry.
- Allowed tools: honor `allowed-tools` list; if present, constrain which executors the skill may request (e.g., `bash`, `read_file`, `network_fetch`).
- Progressive disclosure: inject only metadata block at startup; on activation, read `SKILL.md` (body) and optionally load referenced files/scripts on demand.

## Architecture Outline
1) **Discovery**: recursive scan for `SKILL.md` under configured roots; cache `SkillDescriptor` with path, frontmatter, and mtime.
2) **Validation**: run schema checks (frontmatter fields, length limits, allowed keys) and optional `skills-ref validate` if binary is available; log actionable errors and exclude invalid skills.
3) **Prompt surfacing**: build `<available_skills>` block (or equivalent JSON) with name, description, location, and allowed-tools; injected into system prompt alongside tool list.
4) **Activation flow**:
   - When the model references `skill::<name>`, load full `SKILL.md`, expose body as context.
   - Provide resolver utilities for `references/` and `assets/`; enforce path sandboxing to the skill root.
   - For `scripts/`, route through existing Bash tool with cwd set to the skill root; require explicit tool call from the model.
5) **Caching & invalidation**: mtime-based cache; bust on file change or manual reload hook.
6) **Telemetry**: emit counters for discovered/validated/activated skills and per-skill execution results (success/failure).

## API & Config Changes (proposed)
- Add `SkillConfig` to agent init:
  - `searchRoots: [URL]` default `[.aidoctor/skills, ~/.aidoctor/skills]`
  - `enableValidation: Bool` (default true)
  - `maxSkillSizeBytes: Int` (default 32 * 1024)
- Extend `AIAgentActor` (and any shared base) with:
  - `skillRegistry: SkillRegistry` responsible for discovery + validation
  - `skillMetadataForPrompt() -> String` to inject into system prompt
  - `activateSkill(named:)` to load body + manage resource sandboxing

## Runtime Flow (happy path)
1. Agent startup → discover skills across roots → validate → cache descriptors.
2. Inject metadata block into system prompt (`<available_skills>` or JSON).
3. During dialogue, the model selects a skill by name.
4. Agent loads `SKILL.md` body, attaches to context, and allows script/reference fetches scoped to the skill folder.
5. Tool calls from the skill execute through existing tool adapters (e.g., Bash) with cwd set to skill root and allowed-tools filter enforced.
6. Results streamed back; telemetry recorded.

## Validation Strategy
- Internal validator: YAML parse + required keys + length/charset checks + disallow unknown keys unless whitelisted.
- Optional external: if `skills-ref` is available in PATH, run `skills-ref validate <skillRoot>`; surface warnings, block on failures.
- CI hook: add a `swift test --filter SkillValidationTests` gate that loads fixture skills and asserts validation outcomes; optionally add a script job `skills-ref validate docs/planning/.../examples/*`.

## Example Skills (to ship in `Tests/Fixtures/Skills/` and `.aidoctor/skills/` for live test)
- **project-indexer**
  - Purpose: list repo files and summarize structure.
  - allowed-tools: `bash`, `read_file`.
  - scripts: `scripts/list_files.sh` uses `rg --files`.
- **test-runner**
  - Purpose: run `swift test --filter <pattern>` and summarize failures.
  - allowed-tools: `bash`.
  - scripts: `scripts/run_tests.sh`.
- **api-diff-explainer**
  - Purpose: compare two git revisions for `Sources/AISDK` and summarize public API changes.
  - allowed-tools: `bash`, `read_file`.
  - references: template prompt for diff explanation.

## Testing Plan
- **Unit**
  - `SkillParserTests`: frontmatter parsing, required fields, length validation, unknown key rejection.
  - `SkillDiscoveryTests`: search priority (project over user), dedupe by name with path precedence, cache invalidation on mtime change.
  - `SkillPromptRenderTests`: ensure metadata block includes path, allowed-tools, and respects size caps.
  - `SkillSandboxTests`: path traversal guard (attempt to escape skill root fails).
- **Integration / Live**
  - Harness test that seeds real skills in a temp `.aidoctor/skills/` and runs `AIAgentActor` in a scripted session:
    1) Model asks “list available skills” → assert metadata listed.
    2) Model selects `project-indexer` → agent loads body; runs `scripts/list_files.sh`; assert output contains a known file.
    3) Model selects `test-runner` with pattern “SkillParserTests” → script runs; assert exit status captured and summary returned.
    4) Model selects `api-diff-explainer` → reads reference prompt; runs diff command; assert summary present.
  - Command to run: `swift test --filter AgentSkillIntegrationTests`.
  - Optional smoke: `swift run BasicChatDemo --skills .aidoctor/skills` to ensure demos honor new roots.

## Documentation Deliverables
- Update `docs/tutorials` with a “Create your first skill” guide referencing `.aidoctor/skills/`.
- Add a template skill folder under `docs/tutorials/examples/skills-template/`.
- Mention CI validation hook and size limits in `docs/AISDK-ARCHITECTURE.md` under the AIAgent section.

## Rollout Plan
- Phase 1: land parser/registry + unit tests.
- Phase 2: integrate prompt injection + activation path behind a feature flag `enableSkills` (default off).
- Phase 3: enable by default after live tests pass; add migration note to `WHATS_NEW_AISDK_2.md`.
- Phase 4: monitor telemetry; iterate on UX (better error messaging, skill search).
