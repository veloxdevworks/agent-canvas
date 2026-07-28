#!/usr/bin/env bash
# Merge two single-arch AgentCanvas.app bundles into one universal .app (unsigned).
#
# Usage:
#   scripts/macos/make-universal-app.sh \
#     /path/to/AgentCanvas-x86_64.app \
#     /path/to/AgentCanvas-arm64.app \
#     /path/to/out/AgentCanvas.app
#
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <x86_64.app> <arm64.app> <out.app>" >&2
  exit 1
fi

X86="$1"
ARM="$2"
OUT="$3"

for app in "$X86" "$ARM"; do
  if [[ ! -d "$app" ]]; then
    echo "error: app not found: $app" >&2
    exit 1
  fi
done

rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
# Prefer arm64 tree as the structural base (Sparkle / resources).
ditto "$ARM" "$OUT"

lipo_pair() {
  local rel="$1"
  local a="$X86/$rel"
  local b="$ARM/$rel"
  local dest="$OUT/$rel"
  if [[ -f "$a" && -f "$b" ]]; then
    mkdir -p "$(dirname "$dest")"
    echo "    lipo: $rel"
    lipo -create "$a" "$b" -output "$dest"
    chmod +x "$dest" 2>/dev/null || true
  elif [[ -f "$b" ]]; then
    echo "    keep arm64-only: $rel"
  elif [[ -f "$a" ]]; then
    mkdir -p "$(dirname "$dest")"
    ditto "$a" "$dest"
    echo "    keep x86_64-only: $rel"
  fi
}

# Host + helper + widget executable
lipo_pair "Contents/MacOS/AgentCanvas"
lipo_pair "Contents/MacOS/agent-canvas-mcp"
lipo_pair "Contents/PlugIns/AgentCanvasWidget.appex/Contents/MacOS/AgentCanvasWidget"

# Mach-O binaries under Frameworks (Sparkle + XPCs)
while IFS= read -r -d '' bin; do
  rel="${bin#"$ARM/"}"
  lipo_pair "$rel"
done < <(find "$ARM/Contents/Frameworks" -type f -perm +111 -print0 2>/dev/null || true)

echo "==> Universal app → $OUT"
lipo -info "$OUT/Contents/MacOS/AgentCanvas" || true
lipo -info "$OUT/Contents/MacOS/agent-canvas-mcp" || true
