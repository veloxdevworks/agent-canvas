#!/usr/bin/env bash
# Ensure Config/Local.xcconfig has a DEVELOPMENT_TEAM for code signing.
# WidgetKit extensions almost never appear in the gallery without a real team.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CFG="$ROOT/platforms/macos/Config/Local.xcconfig"
EXAMPLE="$ROOT/platforms/macos/Config/Local.xcconfig.example"

write_cfg() {
  local team="$1"
  cat >"$CFG" <<EOF
// Managed by ensure-team.sh / just macos-team — gitignored
DEVELOPMENT_TEAM = ${team}
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY = Apple Development
CODE_SIGN_IDENTITY[sdk=macosx*] = Apple Development
EOF
}

# Extract the real Team ID (OU) from an Apple Development certificate.
# NOTE: The number in "Apple Development: Name (XXXXXXXXXX)" is often a *user*
# id, NOT the team id. Using it as DEVELOPMENT_TEAM causes:
#   No signing certificate "Mac Development" found … team ID "XXXXXXXXXX"
team_from_apple_development_cert() {
  local subject ou
  # OpenSSL may print "OU = TEAMID" (with spaces) or "OU=TEAMID".
  subject="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null || true)"
  if [[ -z "$subject" ]]; then
    return 1
  fi
  ou="$(printf '%s\n' "$subject" | sed -n 's/.*OU[[:space:]]*=[[:space:]]*\([A-Z0-9]\{10\}\).*/\1/p' | head -1)"
  if [[ -n "$ou" ]]; then
    printf '%s\n' "$ou"
    return 0
  fi
  return 1
}

if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
  write_cfg "$DEVELOPMENT_TEAM"
  echo "Wrote DEVELOPMENT_TEAM from env → $CFG"
  exit 0
fi

if [[ -f "$CFG" ]] && grep -qE 'DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}' "$CFG"; then
  if ! grep -q 'CODE_SIGN_IDENTITY' "$CFG"; then
    TEAM_EXISTING="$(grep -E 'DEVELOPMENT_TEAM[[:space:]]*=' "$CFG" | head -1 | sed -n 's/.*=[[:space:]]*\([A-Z0-9]\{10\}\).*/\1/p')"
    write_cfg "$TEAM_EXISTING"
    echo "Updated $CFG with Apple Development identity"
  fi
  # Self-heal: wrong id from CN parentheses (user id) → cert OU (real team id).
  CURRENT="$(grep -E 'DEVELOPMENT_TEAM[[:space:]]*=' "$CFG" | head -1 | sed -n 's/.*=[[:space:]]*\([A-Z0-9]\{10\}\).*/\1/p')"
  REAL="$(team_from_apple_development_cert 2>/dev/null || true)"
  if [[ -n "$REAL" && -n "$CURRENT" && "$CURRENT" != "$REAL" ]]; then
    CN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
      | grep 'Apple Development:' | head -1 \
      | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' || true)"
    if [[ -n "$CN_ID" && "$CURRENT" == "$CN_ID" ]]; then
      write_cfg "$REAL"
      echo "Corrected DEVELOPMENT_TEAM $CURRENT → $REAL (cert OU / real team id)"
    fi
  fi
  echo "Using existing team in $CFG"
  grep 'DEVELOPMENT_TEAM' "$CFG"
  exit 0
fi

TEAM=""
if TEAM="$(team_from_apple_development_cert 2>/dev/null)"; then
  :
else
  TEAM=""
fi

# Fallback: Developer ID Application team in parentheses is usually the real team.
if [[ -z "$TEAM" ]] && command -v security >/dev/null 2>&1; then
  TEAM="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application:' \
    | head -1 \
    | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' || true)"
fi

if [[ -n "$TEAM" ]]; then
  write_cfg "$TEAM"
  echo "Detected DEVELOPMENT_TEAM=$TEAM → $CFG"
  exit 0
fi

echo "error: No DEVELOPMENT_TEAM found." >&2
echo "" >&2
echo "WidgetKit extensions require a signed app with a development team." >&2
echo "Fix one of:" >&2
echo "  just macos-team TEAM=XXXXXXXXXX" >&2
echo "  DEVELOPMENT_TEAM=XXXXXXXXXX just macos-install" >&2
echo "  cp $EXAMPLE $CFG  # then edit TEAM id" >&2
echo "" >&2
echo "Find your Team ID: Xcode → Settings → Accounts → Team → Team ID" >&2
echo "  (Not the number in parentheses after your name on the cert — that can be a user id.)" >&2
exit 1
