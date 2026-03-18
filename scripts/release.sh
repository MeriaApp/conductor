#!/bin/bash
set -e

# Conductor Release Script
# Usage: ./scripts/release.sh 1.0.1 "Fixed a bug"
# This builds, signs, zips, and creates a GitHub release in one command.

VERSION="${1:?Usage: ./scripts/release.sh VERSION \"Release notes\"}"
NOTES="${2:-Conductor v$VERSION}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="Conductor"
TEAM_ID="36D97ZTP6J"
SIGN_IDENTITY="Developer ID Application: JESSE ROBERT MERIA ($TEAM_ID)"

echo "=== Conductor Release v$VERSION ==="
echo ""

# 1. Update version in project.yml + auto-increment build number
echo "[1/6] Updating version to $VERSION..."
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" "$PROJECT_DIR/project.yml"
CURRENT_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_DIR/project.yml" | sed 's/[^0-9]//g')
NEXT_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: $CURRENT_BUILD/CURRENT_PROJECT_VERSION: $NEXT_BUILD/" "$PROJECT_DIR/project.yml"
echo "  Version: $VERSION ($NEXT_BUILD)"

# 2. Regenerate Xcode project
echo "[2/6] Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate 2>&1 | tail -1

# 3. Build with Developer ID signing
echo "[3/6] Building (signed with Developer ID)..."
xcodebuild -project Conductor.xcodeproj -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    -configuration Release \
    build \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--options=runtime" \
    2>&1 | tail -3

# Verify build succeeded
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "ERROR: Build failed!"
    exit 1
fi

# 4. Find and zip the built app
echo "[4/6] Packaging..."
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Conductor.app" -path "*/Conductor-*/Build/Products/Release/*" -maxdepth 6 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "ERROR: Built app not found!"
    exit 1
fi

ZIP_NAME="Conductor-v${VERSION}.zip"
ZIP_PATH="$PROJECT_DIR/releases/$ZIP_NAME"
mkdir -p "$PROJECT_DIR/releases"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "  Zipped: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

# 5. Commit and push
echo "[5/6] Committing and pushing..."
cd "$PROJECT_DIR"
git add -A
git commit -m "Release v$VERSION

$NOTES

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>" 2>&1 | tail -1
git push origin main 2>&1 | tail -1

# 6. Create GitHub release
echo "[6/6] Creating GitHub release..."
gh release create "v$VERSION" "$ZIP_PATH" \
    --title "Conductor v$VERSION" \
    --notes "$NOTES" \
    2>&1

echo ""
echo "=== Done! ==="
echo "Release: https://github.com/MeriaApp/conductor/releases/tag/v$VERSION"
echo "Your friend can download: $ZIP_NAME from the release page"
