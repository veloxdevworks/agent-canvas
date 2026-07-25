#!/usr/bin/env bash
# Build AgentCanvas.app and install to a stable path Launch Services / WidgetKit can see.
# Installing only from DerivedData is a common reason widgets never show up in the gallery.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MACOS="$ROOT/platforms/macos"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/macos}"
# Prefer user Applications — no admin; still fully registered with LS / WidgetKit.
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_NAME="AgentCanvas.app"
DEST="$INSTALL_DIR/$APP_NAME"
CONFIGURATION="${CONFIGURATION:-Debug}"

bash "$ROOT/scripts/macos/ensure-team.sh"

mkdir -p "$BUILD_DIR" "$INSTALL_DIR"

if [[ ! -f "$MACOS/AgentCanvas.xcodeproj/project.pbxproj" ]]; then
  echo "Generating Xcode project…"
  (cd "$MACOS" && xcodegen generate)
fi

echo "Building $CONFIGURATION → $BUILD_DIR"
set -o pipefail
# -allowProvisioningUpdates: required when App Groups / capabilities need a
# Mac Development profile generated automatically for the team.
if ! xcodebuild \
  -project "$MACOS/AgentCanvas.xcodeproj" \
  -scheme AgentCanvas \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'platform=macOS,arch=arm64' \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  build 2>&1 | tee "$BUILD_DIR/xcodebuild.log"; then
  echo "Build failed — last 40 lines of log:" >&2
  tail -40 "$BUILD_DIR/xcodebuild.log" >&2
  echo "" >&2
  echo "If this is a provisioning error, open once in Xcode and enable" >&2
  echo "  Signing & Capabilities → App Groups → group.com.velox.agentcanvas" >&2
  echo "or run: just macos-xcode" >&2
  exit 1
fi

PRODUCT="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$PRODUCT" ]]; then
  # Sometimes configuration folder casing differs
  PRODUCT="$(find "$BUILD_DIR/Build/Products" -maxdepth 2 -name "$APP_NAME" -type d | head -1 || true)"
fi
if [[ ! -d "$PRODUCT" ]]; then
  echo "error: built app not found under $BUILD_DIR/Build/Products" >&2
  exit 1
fi

# Quit running instance so we can replace the bundle.
if pgrep -x AgentCanvas >/dev/null 2>&1; then
  echo "Quitting running AgentCanvas…"
  osascript -e 'tell application "AgentCanvas" to quit' 2>/dev/null || true
  sleep 0.5
  killall AgentCanvas 2>/dev/null || true
fi

echo "Installing $PRODUCT → $DEST"
rm -rf "$DEST"
ditto "$PRODUCT" "$DEST"

# Clear quarantine / extended attrs that block extension discovery after copy.
xattr -cr "$DEST" 2>/dev/null || true

# Force Launch Services to re-scan the app (critical for widget gallery).
# Unregister DerivedData / other build copies first so the gallery does not
# keep serving stale widget kinds from an older AgentCanvas.app.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  for stale in \
    "$ROOT/build/macos/Build/Products/Debug/AgentCanvas.app" \
    "$ROOT/build/macos/Build/Products/Release/AgentCanvas.app" \
    "$ROOT/build/macos-adhoc/Build/Products/Debug/AgentCanvas.app"
  do
    if [[ -d "$stale" && "$stale" != "$DEST" ]]; then
      "$LSREGISTER" -u "$stale" 2>/dev/null || true
      echo "Unregistered stale build: $stale"
    fi
  done
  "$LSREGISTER" -f -R -trusted "$DEST"
  echo "Launch Services re-registered $DEST (trusted)"
fi

# Verify widget extension is embedded.
PLUGIN="$DEST/Contents/PlugIns/AgentCanvasWidget.appex"
if [[ ! -d "$PLUGIN" ]]; then
  echo "error: Widget extension missing at $PLUGIN" >&2
  echo "The app will not expose widgets. Check Embed App Extensions build phase." >&2
  exit 1
fi

echo "Embedded extension OK: $PLUGIN"
echo "Bundle id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist" 2>/dev/null || true)"
echo "Widget id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLUGIN/Contents/Info.plist" 2>/dev/null || true)"
echo ""
# WidgetKit keeps the old appex process alive across installs; kill it so the
# next timeline load uses the binary we just installed.
echo "Restarting widget extension process…"
killall AgentCanvasWidget 2>/dev/null || true
killall chronod 2>/dev/null || true
sleep 0.3

echo "Installed: $DEST"
echo "Next: just macos-run   # launch once so WidgetKit indexes the extension"
echo "      then right-click desktop → Edit Widgets → search Agent Canvas"
