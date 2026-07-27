#!/usr/bin/env bash
# Developer ID sign → notarize → staple → DMG → sign/notarize/staple DMG.
#
# Usage:
#   scripts/macos/package-notarized-dmg.sh /path/to/AgentCanvas.app
#
# Required env:
#   IDENTITY — Developer ID Application identity (name or SHA-1 hash)
#
# Notary auth (one of):
#   NOTARY_PROFILE — keychain profile from `xcrun notarytool store-credentials`
#   or APPLE_API_KEY_PATH + APPLE_API_KEY_ID + APPLE_API_ISSUER_ID
#
# Optional env:
#   OUTPUT_DIR        — default: <repo>/dist/macos-release
#   DMG_NAME          — default: AgentCanvas.dmg
#   VOL_NAME          — default: Agent Canvas
#   STAGED_APP_NAME   — default: AgentCanvas.app (under OUTPUT_DIR)
#   SKIP_STAGED_APP=1 — do not copy stapled .app into OUTPUT_DIR
#   SKIP_DMG=1        — sign/notarize/staple .app only
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MACOS="$ROOT/platforms/macos"

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: $0 /path/to/AgentCanvas.app" >&2
  exit 1
fi

APP_SRC="$1"
if [[ ! -d "$APP_SRC" ]]; then
  echo "error: app bundle not found: $APP_SRC" >&2
  exit 1
fi

IDENTITY="${IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  echo "error: set IDENTITY to a Developer ID Application identity" >&2
  exit 1
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_API_KEY_PATH="${APPLE_API_KEY_PATH:-}"
APPLE_API_KEY_ID="${APPLE_API_KEY_ID:-}"
APPLE_API_ISSUER_ID="${APPLE_API_ISSUER_ID:-}"

if [[ -z "$NOTARY_PROFILE" ]]; then
  if [[ -z "$APPLE_API_KEY_PATH" || -z "$APPLE_API_KEY_ID" || -z "$APPLE_API_ISSUER_ID" ]]; then
    echo "error: set NOTARY_PROFILE or APPLE_API_KEY_PATH + APPLE_API_KEY_ID + APPLE_API_ISSUER_ID" >&2
    exit 1
  fi
  if [[ ! -f "$APPLE_API_KEY_PATH" ]]; then
    echo "error: APPLE_API_KEY_PATH not found: $APPLE_API_KEY_PATH" >&2
    exit 1
  fi
fi

OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist/macos-release}"
DMG_NAME="${DMG_NAME:-AgentCanvas.dmg}"
VOL_NAME="${VOL_NAME:-Agent Canvas}"
STAGED_APP_NAME="${STAGED_APP_NAME:-AgentCanvas.app}"
SKIP_STAGED_APP="${SKIP_STAGED_APP:-0}"
SKIP_DMG="${SKIP_DMG:-0}"

HOST_ENTS="$MACOS/AgentCanvas/AgentCanvas.entitlements"
WIDGET_ENTS="$MACOS/AgentCanvasWidget/AgentCanvasWidget.entitlements"
for f in "$HOST_ENTS" "$WIDGET_ENTS"; do
  if [[ ! -f "$f" ]]; then
    echo "error: missing entitlements: $f" >&2
    exit 1
  fi
done

mkdir -p "$OUTPUT_DIR"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/agent-canvas-notarize.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

APP="$WORK/AgentCanvas.app"
echo "==> Staging app → $APP"
ditto "$APP_SRC" "$APP"

sign() {
  local target="$1"
  shift
  echo "    codesign: $target"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@" "$target"
}

echo "==> Signing (Developer ID, inside-out)"
MCP="$APP/Contents/MacOS/agent-canvas-mcp"
if [[ ! -x "$MCP" ]]; then
  echo "error: embedded MCP helper missing at $MCP" >&2
  echo "  Build + embed first (just build-mcp-release && embed-mcp.sh)." >&2
  exit 1
fi
sign "$MCP"

APPEX="$APP/Contents/PlugIns/AgentCanvasWidget.appex"
if [[ ! -d "$APPEX" ]]; then
  echo "error: widget extension missing at $APPEX" >&2
  exit 1
fi
sign "$APPEX" --entitlements "$WIDGET_ENTS"
sign "$APP" --entitlements "$HOST_ENTS"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

notary_submit() {
  local artifact="$1"
  echo "==> Notarizing $(basename "$artifact")"
  if [[ -n "$NOTARY_PROFILE" ]]; then
    xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait
  else
    xcrun notarytool submit "$artifact" \
      --key "$APPLE_API_KEY_PATH" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER_ID" \
      --wait
  fi
}

APP_ZIP="$WORK/AgentCanvas-notarize.zip"
echo "==> Zipping app for notarization"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
notary_submit "$APP_ZIP"

echo "==> Stapling app"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

STAGED_APP=""
if [[ "$SKIP_STAGED_APP" != "1" ]]; then
  STAGED_APP="$OUTPUT_DIR/$STAGED_APP_NAME"
  rm -rf "$STAGED_APP"
  ditto "$APP" "$STAGED_APP"
fi

if [[ "$SKIP_DMG" == "1" ]]; then
  echo "==> SKIP_DMG=1 — writing checksums for .app only"
  if [[ -n "$STAGED_APP" ]]; then
    (
      cd "$OUTPUT_DIR"
      shasum -a 256 "$STAGED_APP_NAME/Contents/MacOS/AgentCanvas" > SHA256SUMS.txt
    )
    echo "Done: $STAGED_APP"
  else
    echo "Done (stapled app left in work dir only)"
  fi
  exit 0
fi

DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
STAGE_DMG="$WORK/dmg-root"
rm -rf "$STAGE_DMG"
mkdir -p "$STAGE_DMG"
ditto "$APP" "$STAGE_DMG/AgentCanvas.app"

echo "==> Creating DMG → $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE_DMG" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Signing DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

notary_submit "$DMG_PATH"

echo "==> Stapling DMG"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "==> Gatekeeper assess (app)"
spctl --assess --type execute -vv "$APP" 2>&1 || true

(
  cd "$OUTPUT_DIR"
  # Keep checksums for multiple DMGs (dual-arch releases).
  if [[ -f SHA256SUMS.txt ]]; then
    grep -v " ${DMG_NAME}\$" SHA256SUMS.txt > SHA256SUMS.txt.tmp || true
    mv SHA256SUMS.txt.tmp SHA256SUMS.txt
  else
    : > SHA256SUMS.txt
  fi
  shasum -a 256 "$DMG_NAME" >> SHA256SUMS.txt
)

echo ""
echo "Done:"
[[ -n "$STAGED_APP" ]] && echo "  App: $STAGED_APP"
echo "  DMG: $DMG_PATH"
echo "  Sums: $OUTPUT_DIR/SHA256SUMS.txt"
ls -lh "$DMG_PATH"
[[ -n "$STAGED_APP" ]] && ls -lh "$STAGED_APP"
