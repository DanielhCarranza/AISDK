#!/bin/bash
# Phase 2.2: Swap AISDK dependency from remote to local path
# Run this from the AIDoctor repo root:
#   cd ~/conductor/workspaces/AIDoctoriOSApp/chengdu
#   bash ~/conductor/workspaces/aisdk/olympia-v1/.aidoctor/swap-to-local-aisdk.sh

set -euo pipefail

PBXPROJ="AIDoctor.xcodeproj/project.pbxproj"
AISDK_LOCAL_PATH="/Users/joelmushagasha/conductor/workspaces/aisdk/olympia-v1"

if [ ! -f "$PBXPROJ" ]; then
    echo "ERROR: Run this script from the AIDoctor repo root (where AIDoctor.xcodeproj exists)"
    exit 1
fi

# Backup
cp "$PBXPROJ" "${PBXPROJ}.bak"
echo "Backed up project.pbxproj to ${PBXPROJ}.bak"

# 1. Replace the XCRemoteSwiftPackageReference section for AISDK with XCLocalSwiftPackageReference
sed -i '' '/935BC9212E09F62600EF93A5.*XCRemoteSwiftPackageReference "AISDK"/,/};/{
s/XCRemoteSwiftPackageReference "AISDK"/XCLocalSwiftPackageReference "AISDK"/
s/isa = XCRemoteSwiftPackageReference;/isa = XCLocalSwiftPackageReference;/
s|repositoryURL = "https://github.com/DanielhCarranza/AISDK.git";|relativePath = "'"$AISDK_LOCAL_PATH"'";|
/requirement = {/,/};/d
}' "$PBXPROJ"

# 2. Update comment references from XCRemoteSwiftPackageReference to XCLocalSwiftPackageReference
sed -i '' 's|XCRemoteSwiftPackageReference "AISDK"|XCLocalSwiftPackageReference "AISDK"|g' "$PBXPROJ"

# 3. Move the section header if needed (XCRemoteSection → XCLocal)
# The entry may now be in the wrong section block, but Xcode tolerates this.

echo "Done! AISDK dependency swapped to local path: $AISDK_LOCAL_PATH"
echo ""
echo "Verify by opening in Xcode or running:"
echo "  xcodebuild -project AIDoctor.xcodeproj -scheme AIDoctor -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -50"
