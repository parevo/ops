#!/usr/bin/env bash
set -euo pipefail

# Build Release .app and wrap it in DMG + ZIP named Ops-<version>.*
# DMG is a classic drag-and-drop installer: Ops.app + Applications shortcut.
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

resign_path() {
  local path="$1"
  codesign --force --sign - --timestamp=none "$path"
}

if [[ -d "$STAGED/Contents/Frameworks/Sparkle.framework" ]]; then
  SPARKLE="$STAGED/Contents/Frameworks/Sparkle.framework"
  while IFS= read -r -d '' item; do
    resign_path "$item"
  done < <(find "$SPARKLE" \( -name "*.xpc" -o -name "*.dylib" \) -print0 2>/dev/null)

  while IFS= read -r -d '' item; do
    resign_path "$item"
  done < <(find "$SPARKLE" \( -name Autoupdate -o -name Updater -o -name sparkle \) -type f -print0 2>/dev/null)

  if [[ -f "$SPARKLE/Versions/B/Sparkle" ]]; then
    resign_path "$SPARKLE/Versions/B/Sparkle"
  fi
  resign_path "$SPARKLE"
fi

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

# --- Drag-and-drop DMG -------------------------------------------------------
echo "==> Creating drag-and-drop DMG"

# Applications alias for the classic "drag Ops → Applications" window
ln -sf /Applications "$STAGE/Applications"

# Optional background (brand-tinted); Finder shows it when .background is used
BG_DIR="$STAGE/.background"
mkdir -p "$BG_DIR"
python3 - <<'PY' "$BG_DIR/dmg-bg.png"
import struct, zlib, sys
from pathlib import Path

path = Path(sys.argv[1])
w, h = 640, 400

def px(x, y):
    # dark moss + soft lime wash (brand)
    t = x / max(w - 1, 1)
    u = y / max(h - 1, 1)
    r = int(12 + 18 * t + 8 * (1 - u))
    g = int(16 + 28 * t + 10 * u)
    b = int(10 + 8 * t)
    # faint grid
    if x % 64 == 0 or y % 64 == 0:
        r, g, b = min(255, r + 12), min(255, g + 18), min(255, b + 8)
    return r, g, b, 255

raw = bytearray()
for y in range(h):
    raw.append(0)  # filter none
    for x in range(w):
        raw.extend(px(x, y))

def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
png += chunk(b"IEND", b"")
path.write_bytes(png)
print(f"wrote {path} ({path.stat().st_size} bytes)")
PY

VOLNAME="Ops"
RW_DMG="$BUILD_DIR/Ops-${VERSION}.rw.dmg"
FINAL_DMG="$DMG_PATH"
rm -f "$RW_DMG" "$FINAL_DMG"

# RW image large enough for Finder metadata
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -size 200m \
  "$RW_DMG"

MOUNT_DIR=$(mktemp -d)
# Attach without mounting into /Volumes if possible — use -mountroot
ATTACH_OUT=$(hdiutil attach -readwrite -noverify -noautoopen -mountroot "$MOUNT_DIR" "$RW_DMG")
echo "$ATTACH_OUT"
DEVICE=$(echo "$ATTACH_OUT" | awk 'NR==1{print $1}')
VOLUME="$MOUNT_DIR/$VOLNAME"
if [[ ! -d "$VOLUME" ]]; then
  # Fallback: default /Volumes mount
  hdiutil detach "$DEVICE" >/dev/null 2>&1 || true
  ATTACH_OUT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")
  DEVICE=$(echo "$ATTACH_OUT" | awk 'NR==1{print $1}')
  VOLUME="/Volumes/$VOLNAME"
fi

echo "==> Mounted at $VOLUME"

# Bless Finder window layout (drag Ops.app onto Applications)
# shellcheck disable=SC2088
osascript <<EOF || true
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {280, 160, 920, 560}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    try
      set background picture of theViewOptions to file ".background:dmg-bg.png"
    end try
    delay 0.4
    set position of item "Ops.app" of container window to {160, 220}
    set position of item "Applications" of container window to {460, 220}
    update without registering applications
    delay 0.8
    close
    open
    delay 0.4
    close
  end tell
end tell
EOF

sync
# Detach (retry a few times — Finder may hold the volume briefly)
for _ in 1 2 3 4 5; do
  if hdiutil detach "$DEVICE" -quiet 2>/dev/null; then
    break
  fi
  sleep 1
  hdiutil detach "$VOLUME" -force -quiet 2>/dev/null || true
  sleep 1
done
rmdir "$MOUNT_DIR" 2>/dev/null || true

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"
rm -f "$RW_DMG"

echo "==> Artifacts"
ls -lh "$ZIP_PATH" "$FINAL_DMG"
echo "ZIP=$ZIP_PATH"
echo "DMG=$FINAL_DMG"
