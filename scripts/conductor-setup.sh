#!/bin/bash
# Conductor workspace setup for AISDK.
# Runs each time a workspace is created.

set -e

BASE_BRANCH="${CONDUCTOR_DEFAULT_BRANCH:-main}"
CURRENT_BRANCH=$(git branch --show-current)

echo "==================================="
echo "  AISDK Workspace Setup"
echo "==================================="
echo ""
echo "  Workspace: ${CONDUCTOR_WORKSPACE_NAME:-unknown}"
echo "  Branch:    $CURRENT_BRANCH"
echo "  Base:      $BASE_BRANCH"
echo ""

# 1. Fetch latest remote state
echo "[1/4] Fetching remote changes..."
git fetch origin --quiet

# 2. Rebase onto latest base branch
echo "[2/4] Syncing with origin/$BASE_BRANCH..."
if [ "$CURRENT_BRANCH" = "$BASE_BRANCH" ]; then
    git pull origin "$BASE_BRANCH" --rebase --quiet 2>/dev/null || \
        echo "  Already up to date."
else
    git rebase "origin/$BASE_BRANCH" --quiet 2>/dev/null || {
        echo "  Rebase had conflicts. Aborting and resetting to origin/$BASE_BRANCH..."
        git rebase --abort 2>/dev/null || true
        git reset --hard "origin/$BASE_BRANCH"
        echo "  Branch reset to origin/$BASE_BRANCH."
    }
fi

# 3. Copy .env from repo root if available (for live API testing)
echo "[3/4] Checking for .env..."
if [ -n "$CONDUCTOR_ROOT_PATH" ] && [ -f "$CONDUCTOR_ROOT_PATH/.env" ]; then
    cp "$CONDUCTOR_ROOT_PATH/.env" .env
    echo "  Copied .env from repo root."
elif [ -f .env ]; then
    echo "  Using existing .env."
else
    echo "  No .env found. Live API tests will be skipped."
    echo "  To enable: copy Tests/env.example to $CONDUCTOR_ROOT_PATH/.env and fill in keys."
fi

# 4. Resolve Swift package dependencies
echo "[4/4] Resolving Swift package dependencies..."
swift package resolve 2>/dev/null || {
    echo "  Warning: swift package resolve failed. Run manually if needed."
}

echo ""
echo "==================================="
echo "  Setup complete!"
echo "==================================="
echo ""
