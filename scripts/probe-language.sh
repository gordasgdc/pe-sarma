#!/bin/bash
# Real-app check of the Language menu. The menu bar item cannot be reached by
# accessibility on recent macOS, so this uses a test build (-DMENU_PROBE, never
# shipped) whose real menu object writes its titles on SIGUSR1 and runs an item
# by path on SIGUSR2. It runs under its own bundle id and preferences domain,
# so the installed app and its settings are not touched.
# Usage: PESARMA_BUILD_DIR=/path scripts/probe-language.sh   (needs the signing identity)
set -uo pipefail
cd "$(dirname "$0")/.."
B="${PESARMA_BUILD_DIR:?}"; ID="${PESARMA_SIGN_ID:-Developer ID Application}"
DOM=dev.gordas.PeSarma.langtest; RUN="$B/probe/run"; APP="$B/probe/PeSarmaProbe.app"
mkdir -p "$RUN"
swift build -c debug --scratch-path "$B/probe/swiftpm" -Xswiftc -DMENU_PROBE >/dev/null || exit 1
rm -rf "$APP"; ditto "$B/PeSarma.app" "$APP"
cp "$B/probe/swiftpm/out/Products/Debug/PeSarma" "$APP/Contents/MacOS/PeSarma"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DOM" "$APP/Contents/Info.plist"
codesign --force --deep --options runtime --sign "$ID" "$APP" 2>/dev/null
pid() { pgrep -f "PeSarmaProbe.app/Contents/MacOS" | head -1; }
stop() { pgrep -f "PeSarmaProbe.app/Contents/MacOS" | xargs kill 2>/dev/null; sleep 2; }
start() { open -n --env PESARMA_PROBE_DIR="$RUN" "$APP"; sleep 5; }
dump() { rm -f "$RUN/menu.txt"; kill -USR1 "$(pid)"; sleep 1; cat "$RUN/menu.txt"; }
pick() { printf '%s' "$1" > "$RUN/pick"; kill -USR2 "$(pid)"; sleep 1.5; }
ax() { osascript -e "tell application \"System Events\" to tell (first process whose bundle identifier is \"$DOM\") to $1" 2>/dev/null; }
head_of() { dump | grep -A5 -E "^(Idioma|Language|Limbă)"; }
PASS=0; FAIL=0
expect() { if echo "$2" | grep -q "$3"; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1"; FAIL=$((FAIL+1)); fi; }
stop; defaults delete $DOM 2>/dev/null; for k in welcomed copyingOffered inboxOffered; do defaults write $DOM $k -bool true; done
start; expect "system language is checked at first start" "$(head_of)" "System language \[x\]\|Limba sistemului \[x\]\|Idioma del sistema \[x\]"
pick "Language/Română"; A=$(ax 'return name of every button of window 1'); expect "Română gives a Romanian dialog with Redeschide acum" "$A" "Redeschide acum"
ax 'click button "Mai târziu" of window 1' >/dev/null
expect "menu is Romanian with the check on Română" "$(head_of)" "Română \[x\]"
stop; start; expect "choice persists after reopening" "$(head_of)" "Română \[x\]"
pick "Limbă/Español"; ax 'click button "Más tarde" of window 1' >/dev/null
expect "Español switches the menu" "$(head_of)" "Español \[x\]"
pick "Idioma/Idioma del sistema"; ax 'click button "Later" of window 1' >/dev/null
expect "system language returns to the automatic pick in the same session" "$(head_of)" "System language \[x\]"
pick "Language/Română"; OLD=$(pid); ax 'click button "Redeschide acum" of window 1' >/dev/null; sleep 7
expect "Redeschide acum starts a new process in Romanian" "$([ "$(pid)" != "$OLD" ] && head_of)" "Română \[x\]"
stop; defaults delete $DOM 2>/dev/null
echo "$PASS passed, $FAIL failed"; [ $FAIL -eq 0 ]
