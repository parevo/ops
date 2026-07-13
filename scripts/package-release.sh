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

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Ops.app" "$ZIP_PATH"

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
