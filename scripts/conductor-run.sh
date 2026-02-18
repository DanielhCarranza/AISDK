#!/bin/zsh
# Conductor run script for AISDK.
# Triggered by the "Run" button in Conductor.

set -e

echo "==================================="
echo "  AISDK Run"
echo "==================================="
echo ""

# Source .env if available (exports API keys for live tests)
if [ -f .env ]; then
    set -a
    source .env
    set +a
    echo "  Loaded .env"
fi

START=$(date +%s)

# 1. Smoke test
echo ""
echo "[1/2] Running SmokeTestApp..."
if swift run SmokeTestApp 2>&1; then
    echo "  Smoke test passed."
else
    echo "  Smoke test FAILED."
    exit 1
fi

# 2. Live API tests (only if API keys are set)
if [ -n "$OPENAI_API_KEY" ] || [ -n "$ANTHROPIC_API_KEY" ]; then
    echo ""
    echo "[2/2] Running live API tests..."
    if RUN_LIVE_TESTS=1 swift test --filter "Live" 2>&1; then
        echo "  Live tests passed."
    else
        echo "  Live tests FAILED."
        exit 1
    fi
else
    echo ""
    echo "[2/2] Skipping live API tests (no API keys in .env)."
fi

END=$(date +%s)
DURATION=$((END - START))

echo ""
echo "==================================="
echo "  Done in ${DURATION}s"
echo "==================================="
