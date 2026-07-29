#!/usr/bin/env bash
# Pre-tag release checks so we don't discover menu/packaging/UX issues after the cut.
#
# Usage:
#   just release-preflight
#   SKIP_BUILD=1 just release-preflight          # strings + git only
#   ALLOW_DIRTY=1 just release-preflight         # permit uncommitted changes
#
# Exit 0 only when automated checks pass. Prints a short human smoke checklist
# that must still be walked on the Release install before tagging.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MACOS="$ROOT/platforms/macos"
MENU="$MACOS/AgentCanvas/MenuBarExtraView.swift"
SETTINGS="$MACOS/AgentCanvas/SettingsView.swift"
PROJECT_YML="$MACOS/project.yml"
CHANGELOG="$ROOT/CHANGELOG.md"
INFO_PLIST="$MACOS/AgentCanvas/Info.plist"

SKIP_BUILD="${SKIP_BUILD:-0}"
ALLOW_DIRTY="${ALLOW_DIRTY:-0}"

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

fail() {
  red "error: $*"
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_grep() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if ! grep -qE "$pattern" "$file"; then
    fail "$label — expected /$pattern/ in ${file#"$ROOT"/}"
  fi
  green "  ok  $label"
}

forbid_grep() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -qE "$pattern" "$file"; then
    fail "$label — found /$pattern/ in ${file#"$ROOT"/} (should not be there)"
  fi
  green "  ok  $label"
}

echo "==> Agent Canvas release preflight"
echo "    repo: $ROOT"

# ── Git cleanliness ─────────────────────────────────────────────────────────
echo ""
echo "==> Git working tree"
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  if [[ "$ALLOW_DIRTY" == "1" ]]; then
    yellow "  warn dirty tree (ALLOW_DIRTY=1) — do not tag until committed"
    git -C "$ROOT" status -sb
  else
    git -C "$ROOT" status -sb
    fail "working tree is dirty — commit or stash, or set ALLOW_DIRTY=1"
  fi
else
  green "  ok  clean working tree"
fi

# ── Version / changelog alignment ───────────────────────────────────────────
echo ""
echo "==> Version + CHANGELOG"
require_file "$PROJECT_YML"
require_file "$CHANGELOG"
VERSION="$(
  awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "$PROJECT_YML"
)"
[[ -n "$VERSION" ]] || fail "could not parse MARKETING_VERSION from project.yml"
BUILD="$(
  awk '/CURRENT_PROJECT_VERSION:/ {
    for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit }
  }' "$PROJECT_YML"
)"
[[ -n "$BUILD" ]] || fail "could not parse CURRENT_PROJECT_VERSION from project.yml"
echo "    MARKETING_VERSION=$VERSION  CURRENT_PROJECT_VERSION=$BUILD"

if ! grep -qE "^## \[${VERSION}\]" "$CHANGELOG"; then
  fail "CHANGELOG.md missing section ## [$VERSION] — move [Unreleased] before tagging"
fi
green "  ok  CHANGELOG has ## [$VERSION]"

# Warn if Unreleased still has bullet content (common cut mistake).
if awk '
  /^## \[Unreleased\]/ { in_u=1; next }
  /^## \[/ { in_u=0 }
  in_u && /^### / { has_h=1 }
  in_u && /^- / { has_item=1 }
  END { exit (has_h || has_item) ? 0 : 1 }
' "$CHANGELOG"; then
  yellow "  warn [Unreleased] still has entries — empty it when cutting $VERSION"
else
  green "  ok  [Unreleased] is empty"
fi

# ── Accessory-app UX contract (source of truth = menu bar, not Commands) ───
echo ""
echo "==> Menu bar UX (MenuBarExtraView — primary surface)"
require_file "$MENU"
require_grep "$MENU" 'Button\("Settings"\)' "menu: Settings"
require_grep "$MENU" 'Menu\("Connect MCP"\)' "menu: Connect MCP"
require_grep "$MENU" 'Button\("How to Use"\)' "menu: How to Use"
require_grep "$MENU" 'Button\("Send Feedback"\)' "menu: Send Feedback"
require_grep "$MENU" 'Button\("Report Issue"\)' "menu: Report Issue"
require_grep "$MENU" 'Button\("Check for Updates…"\)' "menu: Check for Updates…"
require_grep "$MENU" 'Button\("Quit"\)' "menu: Quit"
# Privacy belongs in Settings, not the menu bar.
forbid_grep "$MENU" 'Button\("Privacy' "menu: Privacy not in menu bar"

echo ""
echo "==> Settings General UX"
require_file "$SETTINGS"
require_grep "$SETTINGS" 'Check for Updates…' "settings: Check for Updates…"
require_grep "$SETTINGS" 'LabeledContent\("Privacy"\)' "settings: Privacy"

echo ""
echo "==> Sparkle feed wiring"
require_file "$INFO_PLIST"
require_grep "$INFO_PLIST" 'SUFeedURL' "Info.plist: SUFeedURL"
require_grep "$INFO_PLIST" 'SUPublicEDKey' "Info.plist: SUPublicEDKey"
require_grep "$INFO_PLIST" 'SUEnableAutomaticChecks' "Info.plist: SUEnableAutomaticChecks"

# ── Release build (catches #if DEBUG / Release-only breakage) ───────────────
if [[ "$SKIP_BUILD" == "1" ]]; then
  yellow "==> Skipping Release build (SKIP_BUILD=1)"
else
  echo ""
  echo "==> Release build"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "Release build requires macOS (or set SKIP_BUILD=1)"
  fi
  ARCH="$(uname -m)"
  case "$ARCH" in
    arm64|x86_64) ;;
    *) fail "unsupported arch: $ARCH" ;;
  esac
  echo "    arch=$ARCH (scripts/macos/build-release-app.sh)"
  APP_PATH="$("$ROOT/scripts/macos/build-release-app.sh" "$ARCH" | tee /dev/stderr | tail -1)"
  [[ -d "$APP_PATH" ]] || fail "Release .app not produced"
  green "  ok  Release app: $APP_PATH"

  echo ""
  echo "==> Swift unit tests (Debug host — fast contract checks)"
  bash "$ROOT/scripts/macos/ensure-team.sh"
  (cd "$MACOS" && xcodegen generate >/dev/null)
  TEST_ARGS=(
    -project "$MACOS/AgentCanvas.xcodeproj"
    -scheme AgentCanvas
    -configuration Debug
    -destination "platform=macOS,arch=$ARCH"
    -derivedDataPath "$ROOT/build/macos-preflight"
    CODE_SIGNING_ALLOWED=NO
    test
    -only-testing:AgentCanvasTests/ContentClipConformanceTests
  )
  if [[ -f "$MACOS/AgentCanvasTests/NotificationPrefsTests.swift" ]]; then
    TEST_ARGS+=(-only-testing:AgentCanvasTests/NotificationPrefsTests)
  fi
  xcodebuild "${TEST_ARGS[@]}" >/dev/null
  green "  ok  AgentCanvasTests"
fi

# ── Human checklist (not automated) ─────────────────────────────────────────
cat <<EOF

$(green "==> Automated checks passed")

Before tagging v${VERSION}, walk this on a Release install
(CONFIGURATION=Release just macos-install && just macos-run — or the
preflight .app above):

  [ ] Menu bar dropdown: Settings, Connect MCP, How to Use, Send Feedback,
      Report Issue, Check for Updates…, Quit — nothing missing / no dead items
  [ ] Settings → General: Updates + Privacy match the product story
  [ ] If packaging/Sparkle scripts changed: dry-run private release with
      publish_public=false (or local notarize) before a public tag
  [ ] Working tree committed; then:
        git tag v${VERSION}
        git push origin v${VERSION}
      then trigger agent-canvas-release (see .github/CI.md)

Do not use a real version tag only to discover notarize/Sparkle bugs.

EOF
