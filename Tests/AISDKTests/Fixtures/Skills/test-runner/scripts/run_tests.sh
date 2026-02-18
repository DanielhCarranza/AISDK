#!/bin/bash
# Run Swift tests with optional filter
if [ -n "$TEST_FILTER" ]; then
    swift test --filter "$TEST_FILTER" 2>&1
else
    swift test 2>&1
fi
