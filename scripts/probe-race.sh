#!/bin/bash
# Reproduces the start-up race: an image that lands in the capture folder
# right after the app starts, before its folder watcher exists. Each round
# launches the app with the capture takeover on, copies an image in as soon as
# the process exists, and checks that it was hung (the OCR index gets its words).
# Changes the macOS screenshot settings temporarily and restores them on quit.
# Usage: PESARMA_BUILD_DIR=/path PESARMA_EVIDENCE_DIR=/path scripts/probe-race.sh <probe.png> [rounds]
set -uo pipefail
cd "$(dirname "$0")/.."
APP="${PESARMA_BUILD_DIR:?}/PeSarma.app"; EV="${PESARMA_EVIDENCE_DIR:?}"; PNG="${1:?probe image}"; ROUNDS="${2:-6}"
DOM=dev.gordas.PeSarma; SUP="$HOME/Library/Application Support/PeSarma"; LOC="$SUP/Screenshots"
prefs() { defaults read com.apple.screencapture 2>/dev/null | grep -v last-analytics-stamp; }
alive() { pgrep -f "$APP/Contents/MacOS/PeSarma" >/dev/null; }
prefs > "$EV/race-prefs-before.txt"; hung=0; lost=0
for i in $(seq 1 "$ROUNDS"); do
  defaults delete $DOM >/dev/null 2>&1; rm -rf "$SUP"; mkdir -p "$LOC"
  for k in welcomed inboxEnabled inboxOffered copyingOffered; do defaults write $DOM $k -bool true; done
  defaults write $DOM loginOfferedVersion -string "$(cat VERSION)"
  open -g "$APP"
  until alive; do :; done
  cp "$PNG" "$LOC/Captura $i.png"
  ok=0; for _ in $(seq 1 20); do grep -q -i sedinta "$SUP/SearchIndex.json" 2>/dev/null && { ok=1; break; }; sleep 1; done
  if [ $ok = 1 ]; then hung=$((hung+1)); echo "round $i: hung"; else lost=$((lost+1)); echo "round $i: LOST"; fi
  osascript -e "tell application id \"$DOM\" to quit" >/dev/null 2>&1
  for _ in $(seq 1 15); do alive || break; sleep 1; done
done
defaults delete $DOM >/dev/null 2>&1; rm -rf "$SUP"
[ "$(prefs)" = "$(cat "$EV/race-prefs-before.txt")" ] && echo "settings restored" || echo "SETTINGS NOT RESTORED"
echo "RESULT: $hung hung, $lost lost of $ROUNDS"
[ "$lost" -eq 0 ]
