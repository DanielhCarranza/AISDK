#!/bin/bash
# List source files in the repository
find . -type f \( -name "*.swift" -o -name "*.md" \) | grep -v ".build" | sort | head -100
