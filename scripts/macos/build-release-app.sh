#!/usr/bin/env bash
# Build an arch-specific Release AgentCanvas.app with embedded MCP (unsigned).
#
# Usage:
#   scripts/macos/build-release-app.sh x86_64
#   scripts/macos/build-release-app.sh arm64
#
# Prints the absolute path of the built .app on the last line (also sets
# APP_PATH via GitHub Actions GITHUB_ENV when present).
#
# Optional env:
#   DERIVED_DATA — default: <repo>/build/ci-macos-release-<arch>
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MACOS="$ROOT/platforms/macos"
ARCH="${1:-}"

case "$ARCH" in
  x86_64)
    RUST_TARGET="x86_64-apple-darwin"
    ;;
  arm64)
    RUST_TARGET="aarch64-apple-darwin"
    ;;
  *)
    echo "usage: $0 x86_64|arm64" >&2
    exit 1
    ;;
esac

# shellcheck disable=SC1091
source "$HOME/.cargo/env" 2>/dev/null || true

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found" >&2
  exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found" >&2
  exit 1
fi

DERIVED_DATA="${DERIVED_DATA:-$ROOT/build/ci-macos-release-$ARCH}"
MCP_BIN="$ROOT/target/$RUST_TARGET/release/agent-canvas-mcp"

echo "==> Rust target: $RUST_TARGET"
rustup target add "$RUST_TARGET" >/dev/null
cargo build --manifest-path "$ROOT/Cargo.toml" -p agent-canvas-mcp --release --target "$RUST_TARGET"
test -x "$MCP_BIN"

echo "==> XcodeGen + xcodebuild (ARCHS=$ARCH)"
# Xcode "Embed agent-canvas-mcp" phase reads this (defaults to target/release otherwise).
export AGENT_CANVAS_MCP_SRC="$MCP_BIN"
# generic/platform=macOS allows cross-compiling (e.g. arm64 on an Intel runner).
# platform=macOS,arch=* only works when that CPU is available as "My Mac".
if [[ "$ARCH" == arm64 ]]; then
  EXCLUDE_ARCHS="x86_64"
else
  EXCLUDE_ARCHS="arm64"
fi
(
  cd "$MACOS"
  xcodegen generate
  xcodebuild \
    -project AgentCanvas.xcodeproj \
    -scheme AgentCanvas \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="$ARCH" \
    ONLY_ACTIVE_ARCH=YES \
    EXCLUDED_ARCHS="$EXCLUDE_ARCHS" \
    CODE_SIGNING_ALLOWED=NO \
    AGENT_CANVAS_MCP_SRC="$MCP_BIN" \
    build
)

APP=$(find "$DERIVED_DATA/Build/Products/Release" -name 'AgentCanvas.app' -type d | head -1)
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: AgentCanvas.app not found under $DERIVED_DATA" >&2
  exit 1
fi

echo "==> Embed MCP ($RUST_TARGET)"
CONFIGURATION=Release AGENT_CANVAS_MCP_SRC="$MCP_BIN" \
  bash "$ROOT/scripts/macos/embed-mcp.sh" "$APP"

# Sanity: binary arch
if command -v lipo >/dev/null 2>&1; then
  echo "==> lipo -info (host binary)"
  lipo -info "$APP/Contents/MacOS/AgentCanvas" || true
  lipo -info "$APP/Contents/MacOS/agent-canvas-mcp" || true
fi

APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
echo "Built: $APP"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "APP_PATH=$APP" >> "$GITHUB_ENV"
fi
# Last line = path for command substitution
echo "$APP"
