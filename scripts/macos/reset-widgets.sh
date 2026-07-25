#!/usr/bin/env bash
# Nuclear-ish reset when widgets won't appear after a dev rebuild / kind rename.
# Safe for local dev; removes this app's container + group data, not other apps.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_ID="com.velox.agentcanvas"
WIDGET_ID="com.velox.agentcanvas.widget"
GROUP_ID="group.com.velox.agentcanvas"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
DEST="$INSTALL_DIR/AgentCanvas.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Quitting AgentCanvas"
osascript -e 'tell application "AgentCanvas" to quit' 2>/dev/null || true
sleep 0.3
killall AgentCanvas 2>/dev/null || true

echo "==> Stopping widget-related processes (best-effort)"
# chronod drives WidgetKit timelines; NotificationCenter hosts the gallery on some OS versions.
killall chronod 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true
killall WidgetKitSimulator 2>/dev/null || true
# Desktop widgets are Dock-hosted on recent macOS — bounce on hard reset.
if [[ "${HARD_RESET:-0}" == "1" ]]; then
  echo "==> HARD_RESET: restarting Dock"
  killall Dock 2>/dev/null || true
fi

echo "==> Removing app / widget containers"
rm -rf "$HOME/Library/Containers/$APP_ID" 2>/dev/null || true
rm -rf "$HOME/Library/Containers/$WIDGET_ID" 2>/dev/null || true
# Any leftover variant containers
find "$HOME/Library/Containers" -maxdepth 1 -name "${APP_ID}*" -exec rm -rf {} + 2>/dev/null || true
find "$HOME/Library/Containers" -maxdepth 1 -name "${WIDGET_ID}*" -exec rm -rf {} + 2>/dev/null || true
rm -rf "$HOME/Library/Group Containers/$GROUP_ID" 2>/dev/null || true

# WidgetKit sometimes caches extension metadata under these trees
echo "==> Clearing WidgetKit caches (best-effort)"
rm -rf "$HOME/Library/Caches/com.apple.chronod" 2>/dev/null || true
rm -rf "$HOME/Library/Caches/com.apple.WidgetKit-Simulator" 2>/dev/null || true
find "$HOME/Library/Caches" -maxdepth 1 -name '*Widget*' -exec rm -rf {} + 2>/dev/null || true
find "$HOME/Library/Caches" -maxdepth 1 -name '*chrono*' -exec rm -rf {} + 2>/dev/null || true

echo "==> Unregistering from Launch Services"
if [[ -x "$LSREGISTER" ]]; then
  if [[ -d "$DEST" ]]; then
    "$LSREGISTER" -u "$DEST" 2>/dev/null || true
  fi
  # Also purge any other AgentCanvas.app copies LS might know about
  "$LSREGISTER" -dump 2>/dev/null | grep -F "com.velox.agentcanvas" | head -5 || true
fi

if [[ "${KEEP_APP:-0}" != "1" ]]; then
  echo "==> Removing installed app at $DEST"
  rm -rf "$DEST"
fi

# Optional: wipe Application Support canvas JSON (keep by default so agent data survives)
if [[ "${WIPE_DATA:-0}" == "1" ]]; then
  echo "==> Wiping ~/.velox/canvas"
  rm -rf "$HOME/.velox/canvas"
fi

echo "==> Done."
echo ""
echo "Next:"
echo "  1. Remove any remaining Agent Canvas tiles from the desktop (right-click → Remove Widget)"
echo "  2. just macos-install && just macos-run"
echo "  3. Edit Widgets → search “Agent Canvas” → look for “Small · One”, “Medium · One”, …"
echo ""
echo "Still only old names? HARD_RESET=1 just macos-widgets-reset  # restarts Dock"
echo "  then log out/in if macOS still caches the extension catalog."
