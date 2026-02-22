# Lessons

Patterns, corrections, and hard-won insights. Updated after every mistake.

---

## Documentation Rule

After any new feature is added or an existing feature is changed — once tests pass and it's been manually verified — you **must** document the feature before considering the task complete. This includes:
- Updating `docs/api-reference/` with API signatures, usage examples, and when-to-use guidance
- Updating `CLAUDE.md` providers table if a new provider/adapter was added
- Updating tutorials if the feature changes the getting-started experience
- If a feature was modified, update existing docs to stay current

Documentation is not optional. A feature without docs is not done.

---

## OpenAI Responses API: maxOutputTokens Minimum

The OpenAI Responses API requires `max_output_tokens >= 16`. If a lower value is passed, the API returns an `invalidRequest` error. The `OpenAIResponsesClientAdapter` clamps this automatically: `request.maxTokens.map { max($0, 16) }`. Chat Completions has no such minimum.

---
