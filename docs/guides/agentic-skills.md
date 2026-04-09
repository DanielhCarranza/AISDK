# Agentic Skills Guide

Skills are markdown-defined capabilities that agents can discover and activate at runtime. They inject domain-specific instructions into the agent's system prompt without code changes.

## Skill File Format

Create a `SKILL.md` file in a named directory:

```
.aidoctor/skills/
  health-research-agent/
    SKILL.md
    references/
      clinical-guidelines.md
    scripts/
      validate-citations.sh
```

The `SKILL.md` has YAML frontmatter + markdown body:

```markdown
---
name: health-research-agent
description: Research health topics using verified medical sources.
tools:
  - web_search
---

You are a health research assistant. When activated...
```

Required frontmatter fields: `name`, `description`. Optional: `tools`, `scope`.

## Configure Discovery Paths

By default, AISDK searches `.aidoctor/skills/` (project-level) and `~/.aidoctor/skills/` (user-level). AIDoctor uses a custom path:

```swift
let config = SkillConfiguration(
    searchRoots: [
        URL(fileURLWithPath: ".aidoctor/skills/"),   // Project skills
        URL(fileURLWithPath: "~/.aidoctor/skills/")  // User skills
    ]
)

let agent = Agent(
    model: myModel,
    skillConfiguration: config
)
```

For a custom app directory:

```swift
let config = SkillConfiguration(
    searchRoots: [URL(fileURLWithPath: ".myapp/skills/")]
)
```

## Discover and Activate Skills

```swift
// Skills are auto-discovered on first agent run.
// To manually discover:
let skills = await agent.discoverSkills()
print("Found \(skills.count) skills")

// Activate a specific skill
try await agent.activateSkill(named: "health-research-agent")

// Deactivate when done
await agent.deactivateSkill(named: "health-research-agent")
```

## How Skills Affect Agent Behavior

When a skill is activated, its markdown body is injected into the agent's system prompt inside an `<available_skills>` XML block. The agent sees the skill's instructions alongside its base system prompt.

Inactive skills appear as metadata only (name + description) so the agent can suggest activating them when relevant.

## Skill Validation

Skills are validated on discovery:
- Name must be lowercase, using only `a-z`, `0-9`, and `-`
- Directory name must match the `name` field
- Max size: 32 KB / 500 lines (configurable)
- Strict frontmatter mode rejects unknown YAML keys

```swift
// Enable strict validation
let config = SkillConfiguration(strictFrontmatter: true)
```

## References and Scripts

Skills can include supporting files:

- `references/` — Context documents loaded when the skill is activated
- `scripts/` — Executable scripts the skill can reference
- `assets/` — Static assets (images, templates, etc.)

```swift
// Read a reference file from an activated skill
let content = try await skillRegistry.readResource(
    path: "references/guidelines.md",
    forSkill: "health-research-agent"
)
```

## Example: AIDoctor Health Research Skill

See `Examples/Skills/health-research-agent/SKILL.md` for a complete example that demonstrates:
- Tool declarations (`web_search`, `code_interpreter`)
- Research protocol instructions
- Response formatting guidelines
- Scope boundaries
