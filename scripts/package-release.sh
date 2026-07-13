#!/usr/bin/env bash
set -euo pipefail

# Build Release .app and wrap it in DMG + ZIP named Ops-<version>.*
# Usage: ./scripts/package-release.sh [version]

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-${MARKETING_VERSION:-1.0.0}}"
BUILD_DIR="${BUILD_DIR:-$ROOT/.build/release}"
DERIVED="${DERIVED_DATA:-$BUILD_DIR/DerivedData}"
DMG_PATH="$BUILD_DIR/Ops-${VERSION}.dmg"
ZIP_PATH="$BUILD_DIR/Ops-${VERSION}.zip"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
ENTITLEMENTS="$ROOT/signing/Ops-adhoc.entitlements"

mkdir -p "$BUILD_DIR"

echo "==> Building Release ParevoOps ${VERSION} (${BUILD_NUMBER})"
xcodebuild \
  -project ParevoOps.xcodeproj \
  -scheme ParevoOps \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  OTHER_CODE_SIGN_FLAGS="--deep" \
  build

APP="$DERIVED/Build/Products/Release/ParevoOps.app"
if [[ ! -d "$APP" ]]; then
  echo "error: ParevoOps.app not found at $APP" >&2
  exit 1
fi

STAGE="$BUILD_DIR/dmg-root"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Ops.app"
STAGED="$STAGE/Ops.app"

echo "==> Ad-hoc re-signing bundle (unify Team ID + disable library validation)"
# Sparkle.framework arrives with Sparkle's Team ID; ad-hoc app has none → dyld abort.
# 1) Re-sign nested Sparkle code as ad-hoc (same empty Team ID as the app)
# 2) Sign the app with disable-library-validation as a safety net under Hardened Runtime

resign_path() {
  local path="$1"
  codesign --force --sign - --timestamp=none "$path"
}

if [[ -d "$STAGED/Contents/Frameworks/Sparkle.framework" ]]; then
  SPARKLE="$STAGED/Contents/Frameworks/Sparkle.framework"
  # XPC services + helper tools (inside-out)
  while IFS= read -r -d '' item; do
    resign_path "$item"
  done < <(find "$SPARKLE" \( -name "*.xpc" -o -name "*.dylib" \) -print0 2>/dev/null)

  while IFS= read -r -d '' item; do
    resign_path "$item"
  done < <(find "$SPARKLE" \( -name Autoupdate -o -name Updater -o -name sparkle \) -type f -print0 2>/dev/null)

  # Framework binary + bundle
  if [[ -f "$SPARKLE/Versions/B/Sparkle" ]]; then
    resign_path "$SPARKLE/Versions/B/Sparkle"
  fi
  resign_path "$SPARKLE"
fi

# Main executable + app bundle with entitlements
codesign --force --sign - --timestamp=none \
  --entitlements "$ENTITLEMENTS" \
  --options runtime \
  "$STAGED/Contents/MacOS/ParevoOps"

codesign --force --sign - --timestamp=none \
  --entitlements "$ENTITLEMENTS" \
  --options runtime \
  "$STAGED"

echo "==> codesign verify"
codesign --verify --verbose=2 "$STAGED" || true
codesign -dv --verbose=4 "$STAGED" 2>&1 | grep -E 'Signature|TeamIdentifier|Flags|Identifier' || true

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$STAGED" "$ZIP_PATH"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "Ops" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "==> Artifacts"
ls -lh "$ZIP_PATH" "$DMG_PATH"
echo "ZIP=$ZIP_PATH"
echo "DMG=$DMG_PATH"
