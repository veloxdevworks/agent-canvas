#!/usr/bin/env bash
# Print everything useful when widgets don't show up.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
DEST="$INSTALL_DIR/AgentCanvas.app"
APP_ID="com.velox.agentcanvas"
WIDGET_ID="com.velox.agentcanvas.widget"
GROUP_ID="group.com.velox.agentcanvas"

ok() { echo "  OK  $*"; }
bad() { echo "  BAD $*"; }
info() { echo "  ·   $*"; }

echo "=== Agent Canvas widget diagnostics ==="
echo ""

echo "1) Installed app"
if [[ -d "$DEST" ]]; then
  ok "Found $DEST"
else
  bad "No app at $DEST — run: just macos-install"
fi

if [[ -d "$DEST" ]]; then
  PLUGIN="$DEST/Contents/PlugIns/AgentCanvasWidget.appex"
  if [[ -d "$PLUGIN" ]]; then
    ok "Embedded appex present"
    info "app  id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || echo '?')"
    info "appex id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLUGIN/Contents/Info.plist" 2>/dev/null || echo '?')"
    EXT_POINT="$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$PLUGIN/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$EXT_POINT" == "com.apple.widgetkit-extension" ]]; then
      ok "NSExtensionPointIdentifier = com.apple.widgetkit-extension"
    else
      bad "Unexpected extension point: ${EXT_POINT:-missing}"
    fi
  else
    bad "Missing PlugIns/AgentCanvasWidget.appex — widgets cannot register"
  fi

  echo ""
  echo "2) Code signing"
  codesign -dv --verbose=4 "$DEST" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier|Signature' | sed 's/^/  /' || true
  TEAM="$(codesign -dv --verbose=4 "$DEST" 2>&1 | sed -n 's/^TeamIdentifier=\(.*\)/\1/p' | head -1)"
  if [[ -z "$TEAM" || "$TEAM" == "not set" ]]; then
    bad "No TeamIdentifier — set DEVELOPMENT_TEAM (just macos-team TEAM=…)"
  else
    ok "TeamIdentifier=$TEAM"
  fi
  if [[ -d "$PLUGIN" ]]; then
    codesign -dv --verbose=4 "$PLUGIN" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier' | sed 's/^/  appex /' || true
  fi
fi

echo ""
echo "3) Local.xcconfig / team"
CFG="$ROOT/platforms/macos/Config/Local.xcconfig"
if [[ -f "$CFG" ]]; then
  ok "Present: $CFG"
  grep -E 'DEVELOPMENT_TEAM|CODE_SIGN' "$CFG" | sed 's/^/  /' || true
else
  bad "Missing $CFG — just macos-team TEAM=XXXXXXXXXX"
fi

echo ""
echo "4) Widget entitlements (expect temporary-exception for Application Support)"
if [[ -d "$DEST/Contents/PlugIns/AgentCanvasWidget.appex" ]]; then
  codesign -d --entitlements :- "$DEST/Contents/PlugIns/AgentCanvasWidget.appex" 2>/dev/null \
    | plutil -p - 2>/dev/null | sed 's/^/  /' || info "could not dump entitlements"
fi

echo ""
echo "5) Data dir ~/.velox/canvas (MCP + widget path)"
AS="$HOME/.velox/canvas"
if [[ -d "$AS" ]]; then
  ok "$AS"
  ls -la "$AS/canvases" 2>/dev/null | sed 's/^/  /' || info "(no canvases yet)"
else
  info "No AS data yet — run host or: just mcp-seed"
fi

echo ""
echo "6) Running processes"
if pgrep -x AgentCanvas >/dev/null 2>&1; then
  ok "AgentCanvas is running"
else
  info "AgentCanvas not running — just macos-run (needed for live reloads)"
fi

echo ""
echo "7) Launch Services hit (best-effort)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -dump 2>/dev/null | grep -F "$APP_ID" | head -5 | sed 's/^/  /' || info "No LS dump lines for $APP_ID"
fi

echo ""
echo "=== Recovery cheatsheet ==="
echo "  just macos-widgets-reset   # wipe containers + uninstall"
echo "  just macos-install         # rebuild + install to ~/Applications"
echo "  just macos-run             # launch once"
echo "  Desktop → Edit Widgets → search “Agent Canvas”"
echo "  HARD_RESET=1 just macos-widgets-reset  # also bounce Dock"
