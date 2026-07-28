#!/usr/bin/env bash
# Build a Sparkle update zip + signed appcast.xml from a notarized universal .app.
#
# Usage:
#   scripts/macos/publish-sparkle-appcast.sh /path/to/AgentCanvas.app
#
# Required env:
#   REF                 — version tag, e.g. v0.2.7
#   SPARKLE_PRIVATE_ED_KEY — EdDSA private key (base64, one line)
#
# Optional env:
#   OUTPUT_DIR          — default: <repo>/dist/macos-release
#   SOURCE_REPO         — default: veloxdevworks/agent-canvas
#   SPARKLE_TOOLS_DIR   — directory containing generate_appcast (auto-download if unset)
#   SPARKLE_VERSION     — Sparkle tools tarball version (default: 2.7.1)
#
# Writes:
#   $OUTPUT_DIR/AgentCanvas-$REF.zip
#   $OUTPUT_DIR/appcast.xml
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: $0 /path/to/AgentCanvas.app" >&2
  exit 1
fi

APP="$1"
if [[ ! -d "$APP" ]]; then
  echo "error: app bundle not found: $APP" >&2
  exit 1
fi

REF="${REF:-}"
if [[ -z "$REF" ]]; then
  echo "error: set REF to a version tag like v0.2.7" >&2
  exit 1
fi

KEY="${SPARKLE_PRIVATE_ED_KEY:-}"
if [[ -z "$KEY" ]]; then
  echo "error: set SPARKLE_PRIVATE_ED_KEY" >&2
  exit 1
fi

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist/macos-release}"
SOURCE_REPO="${SOURCE_REPO:-veloxdevworks/agent-canvas}"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.7.1}"
DOWNLOAD_PREFIX="https://github.com/${SOURCE_REPO}/releases/download/${REF}/"

mkdir -p "$OUTPUT_DIR"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/agent-canvas-sparkle.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Resolve generate_appcast
GEN="${SPARKLE_TOOLS_DIR:+$SPARKLE_TOOLS_DIR/generate_appcast}"
if [[ -z "${SPARKLE_TOOLS_DIR:-}" || ! -x "${GEN:-}" ]]; then
  echo "==> Downloading Sparkle ${SPARKLE_VERSION} tools"
  curl -fsSL \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    -o "$WORK/sparkle.tar.xz"
  mkdir -p "$WORK/sparkle"
  tar -xf "$WORK/sparkle.tar.xz" -C "$WORK/sparkle"
  GEN="$(find "$WORK/sparkle" -type f -name generate_appcast | head -1)"
fi
if [[ -z "$GEN" || ! -x "$GEN" ]]; then
  echo "error: generate_appcast not found" >&2
  exit 1
fi

ZIP_NAME="AgentCanvas-${REF}.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
ARCHIVES="$WORK/archives"
mkdir -p "$ARCHIVES"

echo "==> Zipping app for Sparkle → $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP" "$ZIP_PATH"
ditto "$ZIP_PATH" "$ARCHIVES/$ZIP_NAME"

echo "==> Generating signed appcast"
# Private key via stdin (--ed-key-file -)
printf '%s\n' "$KEY" | "$GEN" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --maximum-deltas 0 \
  --link "https://github.com/${SOURCE_REPO}/releases/tag/${REF}" \
  -o "$ARCHIVES/appcast.xml" \
  "$ARCHIVES"

cp "$ARCHIVES/appcast.xml" "$OUTPUT_DIR/appcast.xml"

# Refresh checksums to include zip + appcast
(
  cd "$OUTPUT_DIR"
  {
    if [[ -f SHA256SUMS.txt ]]; then
      # Drop prior zip/appcast lines if re-running.
      grep -vE " (AgentCanvas-${REF}\\.zip|appcast\\.xml)\$" SHA256SUMS.txt || true
    fi
    shasum -a 256 "$ZIP_NAME" appcast.xml
  } > SHA256SUMS.txt.tmp
  mv SHA256SUMS.txt.tmp SHA256SUMS.txt
)

echo ""
echo "Done:"
echo "  Zip: $ZIP_PATH"
echo "  Appcast: $OUTPUT_DIR/appcast.xml"
echo "  Download prefix: $DOWNLOAD_PREFIX"
ls -lh "$ZIP_PATH" "$OUTPUT_DIR/appcast.xml"
