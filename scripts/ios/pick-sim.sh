#!/usr/bin/env bash
# Sets IOS_SIM_UDID to the first available iPhone simulator.
# Usage: source scripts/ios/pick-sim.sh
set -euo pipefail

IOS_SIM_UDID="$(
  xcrun simctl list devices available |
    awk -F '[()]' '/iPhone/ && /Booted/ { gsub(/ /, "", $2); print $2; exit }'
)"
if [[ -z "${IOS_SIM_UDID}" ]]; then
  IOS_SIM_UDID="$(
    xcrun simctl list devices available |
      awk -F '[()]' '/iPhone/ && /Shutdown/ { gsub(/ /, "", $2); print $2; exit }'
  )"
fi
if [[ -z "${IOS_SIM_UDID}" ]]; then
  echo "error: no available iPhone simulator" >&2
  exit 1
fi
export IOS_SIM_UDID
echo "IOS_SIM_UDID=$IOS_SIM_UDID"
