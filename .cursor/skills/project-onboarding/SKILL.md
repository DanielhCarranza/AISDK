---
name: project-onboarding
description: Quickly onboard to a project by understanding its purpose, features, tech stack, current state, and roadmap. Use when first joining a conversation, starting work on an unfamiliar project, or when the user asks to onboard or get an overview.
---

# Project Onboarding

## Instructions

When onboarding to a project, gather a high-level understanding across these dimensions:

### 1. Product Purpose
- What problem does this project solve?
- Who are the primary users?
- Read: README.md, project description, main docs

### 2. Key Features
- What are the core capabilities?
- What modules or components exist?
- Scan: CHANGELOG.md, feature docs, main source directories

### 3. Tech Stack
- What languages, frameworks, and tools are used?
- Check: Package.swift, Package.json, requirements.txt, Dockerfile
- Review: Build configuration, dependencies

### 4. Current State
- What's working? What's in progress?
- Check: Git status, open issues, TODO files
- Review: Recent commits, active branches

### 5. Future Direction
- What's planned next?
- Where is the project headed?
- Check: ROADMAP.md, TODO.md, planning docs in docs/ or .flow/

## Execution Strategy

1. **Start with entry points**: README.md, CHANGELOG.md, architectural docs
2. **Scan structure**: Browse source directories to understand organization
3. **Check config**: Review dependency and build files for tech context
4. **Review status**: Git branch, recent changes, untracked files
5. **Find roadmap**: Look for planning docs that outline future work

## Output Format

Provide a **brief summary** covering:

```markdown
**Product**: [One sentence describing what it does and who it's for]

**Core Features**: [3-5 bullet points of main capabilities]

**Tech Stack**: [Languages, frameworks, key libraries]

**Current State**: [What's live, what's in progress, what branch you're on]

**Roadmap**: [Key upcoming features or goals]
```

## Notes

- Keep it high-level - don't deep-dive into implementation details
- Focus on orientation, not mastery
- If information is missing, note it and move on
- This is a quick scan, not exhaustive analysis
