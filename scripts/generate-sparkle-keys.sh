#!/usr/bin/env bash
set -euo pipefail

# Generate Sparkle EdDSA keypair for auto-updates.
# Public key → signing/sparkle_public_ed_key.txt (+ Xcode OPS_SPARKLE_PUBLIC_ED_KEY)
# Private key → signing/ed25519-privkey.txt → GitHub secret SPARKLE_PRIVATE_KEY
#
# Sparkle stores the private key in macOS Keychain; this script exports a copy for CI.
# Usage: ./scripts/generate-sparkle-keys.sh
#
# Optional: OPS_SPARKLE_ACCOUNT=parevo-ops  (Keychain account name)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGN="$ROOT/signing"
mkdir -p "$SIGN"

TOOLS="$ROOT/.build/sparkle-tools"
mkdir -p "$TOOLS"

SPARKLE_VER="2.7.1"
ARCHIVE="$TOOLS/Sparkle-${SPARKLE_VER}.tar.xz"
ACCOUNT="${OPS_SPARKLE_ACCOUNT:-parevo-ops}"

if [[ ! -x "$TOOLS/bin/generate_keys" ]]; then
  echo "==> Downloading Sparkle ${SPARKLE_VER} tools"
  curl -fsSL -o "$ARCHIVE" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VER}/Sparkle-${SPARKLE_VER}.tar.xz"
  tar -xf "$ARCHIVE" -C "$TOOLS"
fi

GEN="$TOOLS/bin/generate_keys"
if [[ ! -x "$GEN" ]]; then
  echo "error: generate_keys not found at $GEN" >&2
  exit 1
fi

PRIV="$SIGN/ed25519-privkey.txt"
PUB_OUT="$SIGN/sparkle_public_ed_key.txt"
LOG="$SIGN/generate_keys.log"

if [[ -f "$PRIV" && -f "$PUB_OUT" ]]; then
  echo "Keys already exist:"
  echo "  public:  $PUB_OUT"
  echo "  private: $PRIV"
  echo "Refusing to overwrite. Delete them first if you need new keys."
  exit 0
fi

echo "==> Generating / looking up EdDSA keys in Keychain (account: $ACCOUNT)"
echo "    macOS may ask to allow Keychain access — choose Allow / Always Allow."
# No path args: creates key in Keychain if missing, prints public key usage.
"$GEN" --account "$ACCOUNT" | tee "$LOG"

echo "==> Exporting private key for CI"
# -x exports the private key seed (base64) to a file
"$GEN" --account "$ACCOUNT" -x "$PRIV"

# Prefer -p for a clean public-key-only print
PUBLIC="$("$GEN" --account "$ACCOUNT" -p 2>/dev/null | tr -d '[:space:]' || true)"
if [[ -z "$PUBLIC" ]]; then
  PUBLIC="$(grep -Eo '[A-Za-z0-9+/=]{40,}' "$LOG" | head -1 || true)"
fi

if [[ -z "$PUBLIC" ]]; then
  echo "error: could not parse public key — see $LOG" >&2
  exit 1
fi

printf '%s\n' "$PUBLIC" > "$PUB_OUT"
chmod 600 "$PRIV"

# Wire public key into Xcode project build setting
PBX="$ROOT/ParevoOps.xcodeproj/project.pbxproj"
if [[ -f "$PBX" ]]; then
  if grep -q 'OPS_SPARKLE_PUBLIC_ED_KEY = ' "$PBX"; then
    # Escape for sed: only replace the empty/default assignment value
    python3 - "$PBX" "$PUBLIC" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
public = sys.argv[2]
text = path.read_text()
# Replace OPS_SPARKLE_PUBLIC_ED_KEY = "..."; keeping quotes
import re
new, n = re.subn(
    r'OPS_SPARKLE_PUBLIC_ED_KEY = "[^"]*";',
    f'OPS_SPARKLE_PUBLIC_ED_KEY = "{public}";',
    text,
)
if n == 0:
    new, n = re.subn(
        r'OPS_SPARKLE_PUBLIC_ED_KEY = ;',
        f'OPS_SPARKLE_PUBLIC_ED_KEY = "{public}";',
        text,
    )
if n == 0:
    new, n = re.subn(
        r'OPS_SPARKLE_PUBLIC_ED_KEY = "";',
        f'OPS_SPARKLE_PUBLIC_ED_KEY = "{public}";',
        text,
    )
path.write_text(new)
print(f"Updated OPS_SPARKLE_PUBLIC_ED_KEY in project.pbxproj ({n} occurrence(s))")
PY
  fi
fi

echo
echo "==> Done"
echo "Public key:  $PUB_OUT"
echo "             $PUBLIC"
echo "Private key: $PRIV  (never commit)"
echo
echo "Next:"
echo "  1. GitHub → Settings → Secrets → Actions → New secret"
echo "     Name:  SPARKLE_PRIVATE_KEY"
echo "     Value: contents of $PRIV"
echo "  2. Commit the public key change in project.pbxproj (and $PUB_OUT)"
echo "  3. Tag a release: git tag v1.0.0 && git push origin v1.0.0"
