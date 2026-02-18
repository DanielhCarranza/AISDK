---
name: test-runner
description: Run Swift tests with optional filter pattern and summarize results. Use when user asks to run tests or verify code changes.
allowed-tools: bash
license: MIT
metadata:
  author: aisdk-team
  version: "1.0"
---

# Test Runner Skill

This skill helps run and analyze Swift test results.

## When to Use

Use this skill when the user:
- Asks to run tests
- Wants to verify code changes work
- Needs test failure analysis

## Available Commands

Run `scripts/run_tests.sh` with optional TEST_FILTER environment variable.

## Usage

1. Set TEST_FILTER env var if filtering by test name
2. Execute run_tests.sh
3. Parse output for failures
4. Summarize pass/fail counts

## Example

```bash
TEST_FILTER="SkillParser" ./scripts/run_tests.sh
```
