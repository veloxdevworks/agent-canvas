#!/usr/bin/env bash
# Copy agent-canvas-mcp into AgentCanvas.app/Contents/MacOS/.
#
# Usage:
#   embed-mcp.sh <path-to-AgentCanvas.app>
#   # or from an Xcode Run Script phase (uses TARGET_BUILD_DIR / CONTENTS_FOLDER_PATH)
#
# Env:
#   AGENT_CANVAS_MCP_SRC   — override source binary (default: <repo>/target/release/agent-canvas-mcp)
#   CONFIGURATION          — Debug|Release (Xcode); Release fails if binary missing
#   CODE_SIGN_IDENTITY     — when set and not "-", re-sign the helper after copy
set -euo pipefail

# Repo root: prefer Xcode SRCROOT (platforms/macos); else script location.
# (XcodeGen may inline this file — do not rely on $0 for the repo path.)
if [[ -n "${SRCROOT:-}" ]]; then
  ROOT="$(cd "$SRCROOT/../.." && pwd)"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

APP=""
MACOS_DIR=""
if [[ $# -ge 1 && -n "${1:-}" ]]; then
  APP="$1"
  MACOS_DIR="$APP/Contents/MacOS"
elif [[ -n "${TARGET_BUILD_DIR:-}" && -n "${CONTENTS_FOLDER_PATH:-}" ]]; then
  # CONTENTS_FOLDER_PATH is relative to TARGET_BUILD_DIR (e.g. AgentCanvas.app/Contents)
  MACOS_DIR="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/MacOS"
  APP="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME:-AgentCanvas.app}"
else
  echo "error: usage: embed-mcp.sh <AgentCanvas.app>  (or run from Xcode build phase)" >&2
  exit 1
fi

CONFIGURATION="${CONFIGURATION:-Debug}"
SRC="${AGENT_CANVAS_MCP_SRC:-$ROOT/target/release/agent-canvas-mcp}"
DEST="$MACOS_DIR/agent-canvas-mcp"

if [[ ! -x "$SRC" ]]; then
  if [[ "$CONFIGURATION" == "Release" ]]; then
    echo "error: MCP helper missing at $SRC" >&2
    echo "  Build it first: cargo build -p agent-canvas-mcp --release" >&2
    echo "  (or: just build-mcp-release)" >&2
    exit 1
  fi
  echo "note: MCP helper not at $SRC — skipping embed (Debug). Run: just build-mcp-release" >&2
  exit 0
fi

mkdir -p "$MACOS_DIR"
cp -f "$SRC" "$DEST"
chmod +x "$DEST"

# Ad-hoc or identity sign so Gatekeeper/hardened runtime accept the helper next to the host.
IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -n "$IDENTITY" && "$IDENTITY" != "-" && "$IDENTITY" != *"Do Not Code Sign"* ]]; then
  codesign --force --sign "$IDENTITY" --options runtime --timestamp=none "$DEST" 2>/dev/null \
    || codesign --force --sign "$IDENTITY" "$DEST" 2>/dev/null \
    || codesign --force --sign - "$DEST"
else
  codesign --force --sign - "$DEST" 2>/dev/null || true
fi

echo "Embedded MCP helper: $DEST"
