#!/bin/zsh
# Conductor workspace setup for AISDK v2 development.
# Ensures all new workspaces are based on aisdk-2.0-modernization, not main.

set -e

V2_BRANCH="aisdk-2.0-modernization"
CURRENT_BRANCH=$(git branch --show-current)

echo "==================================="
echo "  AISDK v2 Workspace Setup"
echo "==================================="
echo ""
echo "  Workspace: ${CONDUCTOR_WORKSPACE_NAME:-unknown}"
echo "  Branch:    $CURRENT_BRANCH"
echo "  Target:    $V2_BRANCH"
echo ""

# 1. Fetch latest remote state
echo "[1/4] Fetching remote changes..."
git fetch origin --quiet

# 2. Rebase onto aisdk-2.0-modernization
echo "[2/4] Ensuring branch is based on $V2_BRANCH..."

if [ -z "$CURRENT_BRANCH" ]; then
    echo "  Detached HEAD state. Creating branch from $V2_BRANCH..."
    git checkout -b "${CONDUCTOR_WORKSPACE_NAME:-workspace}-$(date +%s)" "origin/$V2_BRANCH"

elif [ "$CURRENT_BRANCH" = "$V2_BRANCH" ]; then
    # Workspace was created from the Branches tab directly on v2 branch.
    echo "  Already on $V2_BRANCH. Pulling latest..."
    git pull origin "$V2_BRANCH" --rebase --quiet 2>/dev/null || \
        echo "  Already up to date."

else
    # Workspace was created from main (Conductor default). Rebase onto v2.
    MERGE_BASE=$(git merge-base HEAD "origin/$V2_BRANCH" 2>/dev/null || echo "")
    V2_HEAD=$(git rev-parse "origin/$V2_BRANCH" 2>/dev/null || echo "")

    if [ "$MERGE_BASE" = "$V2_HEAD" ]; then
        echo "  Already based on latest $V2_BRANCH. No rebase needed."
    else
        echo "  Rebasing $CURRENT_BRANCH onto origin/$V2_BRANCH..."
        if ! git rebase "origin/$V2_BRANCH" --quiet 2>/dev/null; then
            echo ""
            echo "  Rebase conflict detected. Resetting to origin/$V2_BRANCH..."
            git rebase --abort 2>/dev/null || true
            git reset --hard "origin/$V2_BRANCH"
            echo "  Branch reset to origin/$V2_BRANCH. Ready for new work."
        else
            echo "  Rebased onto $V2_BRANCH."
        fi
    fi
fi

# 3. Set upstream tracking to target v2 branch for PRs
echo "[3/4] Configuring git upstream..."
CURRENT_BRANCH=$(git branch --show-current)
git config branch."$CURRENT_BRANCH".merge "refs/heads/$V2_BRANCH" 2>/dev/null || true
git config branch."$CURRENT_BRANCH".remote origin 2>/dev/null || true

# 4. Resolve Swift package dependencies
echo "[4/4] Resolving Swift package dependencies..."
swift package resolve 2>/dev/null || {
    echo "  Warning: swift package resolve failed. Run manually if needed."
}

echo ""
echo "==================================="
echo "  Setup complete!"
echo "==================================="
echo "  PRs should target: $V2_BRANCH"
echo ""
