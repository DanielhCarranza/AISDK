---
name: project-indexer
description: List repository files and summarize project structure. Use when the user asks about codebase organization or wants to understand the project layout.
allowed-tools: bash read_file
license: MIT
metadata:
  author: aisdk-team
  version: "1.0"
---

# Project Indexer Skill

This skill helps analyze repository structure and understand codebase organization.

## When to Use

Use this skill when the user:
- Asks about the project structure
- Wants to know what files exist in the codebase
- Needs an overview of directories and their purposes

## Available Commands

Run `scripts/list_files.sh` to get a recursive listing of source files.

## Usage

1. Execute the list_files script to get file listing
2. Analyze the output to understand project organization
3. Summarize key directories and their purposes

## Example Output

The script will output something like:
```
./Sources/AISDK/Agents/AIAgentActor.swift
./Sources/AISDK/Tools/AITool.swift
...
```

Use this to explain the codebase structure to the user.
