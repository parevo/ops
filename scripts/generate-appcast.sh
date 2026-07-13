#!/usr/bin/env bash
set -euo pipefail

# Build / update docs/appcast.xml for Sparkle.
# Usage:
#   ./scripts/generate-appcast.sh <version> <zip-path> [download-url]
#
# If SPARKLE_PRIVATE_KEY env (PEM contents) or signing/ed25519-privkey.pem exists,
# the enclosure is signed.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?version required}"
ZIP="${2:?zip path required}"
URL="${3:-https://github.com/parevo/ops/releases/download/v${VERSION}/Ops-${VERSION}.zip}"
OUT="${ROOT}/docs/appcast.xml"
PUBDATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"
LENGTH="$(wc -c < "$ZIP" | tr -d ' ')"

SIGN_ARGS=()
KEY_FILE=""
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  KEY_FILE="$(mktemp)"
  printf '%s\n' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
  trap 'rm -f "$KEY_FILE"' EXIT
elif [[ -f "$ROOT/signing/ed25519-privkey.txt" ]]; then
  KEY_FILE="$ROOT/signing/ed25519-privkey.txt"
elif [[ -f "$ROOT/signing/ed25519-privkey.pem" ]]; then
  KEY_FILE="$ROOT/signing/ed25519-privkey.pem"
fi

ED_SIG=""
if [[ -n "$KEY_FILE" ]]; then
  TOOLS="$ROOT/.build/sparkle-tools"
  SIGN_UPDATE="$(find "$TOOLS" -type f -name sign_update 2>/dev/null | head -1 || true)"
  if [[ -z "$SIGN_UPDATE" ]]; then
    mkdir -p "$TOOLS"
    curl -fsSL -o "$TOOLS/Sparkle.tar.xz" \
      "https://github.com/sparkle-project/Sparkle/releases/download/2.7.1/Sparkle-2.7.1.tar.xz"
    tar -xf "$TOOLS/Sparkle.tar.xz" -C "$TOOLS"
    SIGN_UPDATE="$(find "$TOOLS" -type f -name sign_update | head -1)"
  fi
  if [[ -n "$SIGN_UPDATE" ]]; then
    # Modern CLI: sign_update --ed-key-file <file> <archive>
    # Output: sparkle:edSignature="..." length="..."
    ED_SIG="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$ZIP" | tr -d '\n')"
  fi
fi

SIGNATURE_ATTR=""
if [[ -n "$ED_SIG" ]]; then
  # sign_update output already includes sparkle:edSignature="..." length="..."
  # Prefer its length if present.
  SIGNATURE_ATTR=" ${ED_SIG}"
else
  SIGNATURE_ATTR=" length=\"${LENGTH}\" type=\"application/octet-stream\""
fi

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Ops</title>
    <link>https://parevo.github.io/ops/</link>
    <description>Ops — native macOS DevOps workspace by Parevo Co.</description>
    <language>en</language>
    <item>
      <title>Ops ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${GITHUB_RUN_NUMBER:-1}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>Ops ${VERSION}</h2>
        <p>Native macOS DevOps workspace — SSH, Docker, metrics, terminals, and more.</p>
      ]]></description>
      <enclosure
        url="${URL}"
        ${SIGNATURE_ATTR}
        />
    </item>
  </channel>
</rss>
EOF

# Fix enclosure formatting if sign_update provided full attrs
if [[ -n "$ED_SIG" ]]; then
  cat > "$OUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Ops</title>
    <link>https://parevo.github.io/ops/</link>
    <description>Ops — native macOS DevOps workspace by Parevo Co.</description>
    <language>en</language>
    <item>
      <title>Ops ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${GITHUB_RUN_NUMBER:-1}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>Ops ${VERSION}</h2>
        <p>Native macOS DevOps workspace — SSH, Docker, metrics, terminals, and more.</p>
      ]]></description>
      <enclosure url="${URL}" ${ED_SIG} type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF
fi

echo "==> Wrote $OUT"
