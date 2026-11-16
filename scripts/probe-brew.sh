#!/bin/bash
# Real check of the Homebrew path of "Check for Updates…". A throw-away cask
# (pe-sarma-test, in a throw-away local tap, installed into a test folder with
# --appdir) stands in for pe-sarma, so the installed app, the real cask and its
# settings are not touched. The test build reads the cask name from the
# environment; everything else (the Caskroom link check, the alert, the copied
# command) is the shipping code. Removes the cask and the tap at the end.
# Usage: PESARMA_BUILD_DIR=/path scripts/probe-brew.sh   (needs build/PeSarma.app from build-app.sh)
set -uo pipefail
cd "$(dirname "$0")/.."
B="${PESARMA_BUILD_DIR:?}"; ID="${PESARMA_SIGN_ID:-Developer ID Application}"
DOM=dev.gordas.PeSarma.brewtest; T="$B/brew"; RUN="$T/run"; APPS="$T/apps"; TAP=local/pesarmatest
rm -rf "$T"; mkdir -p "$RUN" "$APPS" "$T/dmg"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_CASK_OPTS="--appdir=$APPS --no-quarantine"
BIN="$(swift build -c debug --scratch-path "$B/probe/swiftpm" -Xswiftc -DMENU_PROBE -Xswiftc -DUPDATE_TEST --show-bin-path)/PeSarma"
swift build -c debug --scratch-path "$B/probe/swiftpm" -Xswiftc -DMENU_PROBE -Xswiftc -DUPDATE_TEST >/dev/null || exit 1
mkapp() { rm -rf "$1"; ditto "$B/build/PeSarma.app" "$1"; cp "$BIN" "$1/Contents/MacOS/PeSarma"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DOM" -c "Set :CFBundleShortVersionString $2" "$1/Contents/Info.plist"
  codesign --force --deep --options runtime --sign "$ID" "$1" 2>/dev/null; }
for v in 1.1.1 1.1.2; do mkdir -p "$T/src-$v"; mkapp "$T/src-$v/PeSarmaT.app" $v
  hdiutil create -quiet -srcfolder "$T/src-$v" -volname PeSarmaT -format UDZO -ov "$T/dmg/PeSarmaT-$v.dmg"; done
cask() { # <version>
  local f="$T/dmg/PeSarmaT-$1.dmg"
  mkdir -p "$(brew --repository $TAP)/Casks"
  cat > "$(brew --repository $TAP)/Casks/pe-sarma-test.rb" <<R
cask "pe-sarma-test" do
  version "$1"
  sha256 "$(shasum -a 256 "$f" | cut -d' ' -f1)"
  url "file://$f"
  name "Pe sarma test"
  desc "Throw-away cask for the update test"
  homepage "https://gordas.dev/pe-sarma/"
  app "PeSarmaT.app"
end
R
}
cleanup() { pkill -9 -f "$APPS/PeSarmaT.app" 2>/dev/null; brew uninstall --cask --force pe-sarma-test >/dev/null 2>&1; brew untap $TAP >/dev/null 2>&1; defaults delete $DOM 2>/dev/null; }
trap cleanup EXIT
brew untap $TAP >/dev/null 2>&1; brew tap-new --no-git $TAP >/dev/null || exit 1
cask 1.1.1
brew install --cask $TAP/pe-sarma-test 2>&1 | tail -3

APP="$APPS/PeSarmaT.app"; ls -l "$(brew --caskroom)/pe-sarma-test"/*/ | sed 's/^/    caskroom: /'
pid() { pgrep -f "$APP/Contents/MacOS" | head -1; }
stop() { pkill -9 -f "$APP/Contents/MacOS" 2>/dev/null; sleep 2; }
start() { PESARMA_PROBE_DIR="$RUN" PESARMA_FEED_URL="$1" PESARMA_CASK_TOKEN=pe-sarma-test nohup "$APP/Contents/MacOS/PeSarma" >/dev/null 2>&1 & sleep 6; }
dump() { rm -f "$RUN/menu.txt"; kill -USR1 "$(pid)"; sleep 1; cat "$RUN/menu.txt"; }
pick() { printf '%s' "$1" > "$RUN/pick"; kill -USR2 "$(pid)"; }
ax() { osascript -e "tell application \"System Events\" to tell (first process whose bundle identifier is \"$DOM\") to $1" 2>/dev/null; }
ver() { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist"; }
PASS=0; FAIL=0
expect() { if echo "$2" | grep -q -- "$3"; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1 (nu conține: $3)"; FAIL=$((FAIL+1)); fi; }
cat > "$T/feed.json" <<J
{"version":"1.1.2","download_url":"https://github.com/gordasgdc/pe-sarma/releases/download/v1.1.2/PeSarma-1.1.2.dmg","sha256":"$(printf 'c%.0s' $(seq 64))","size":3000000,
 "changes":{"ro":"Verificarea actualizărilor se face acum în aplicație.","es":"La comprobación de actualizaciones ahora se hace en la app.","en":"Update checks now happen inside the app."}}
J
defaults delete $DOM 2>/dev/null; for k in welcomed copyingOffered inboxOffered; do defaults write $DOM $k -bool true; done
defaults write $DOM PeSarmaLanguage es; defaults write $DOM loginOfferedVersion -string 1.1.1; defaults write $DOM probeMarker -string keep-me
SAVED_CLIP="$(pbpaste 2>/dev/null)"
echo "### 8. Copie instalată cu Homebrew, versiune 1.1.1, feed cu 1.1.2"
start "file://$T/feed.json"; pick "Buscar actualizaciones…"
for _ in $(seq 1 24); do t=$(ax 'return (value of every static text of window 1) as text'); [ -n "$t" ] && break; sleep 0.5; done
echo "    texto: $t"; B1=$(ax 'return (name of every button of window 1) as text'); echo "    butoane: $B1"
expect "recunoscută ca instalare Homebrew (nu oferă Actualizar ahora)" "$t" "Homebrew la actualiza"; expect "arată comanda brew upgrade" "$(ax 'return (value of every text field of window 1) as text') $t" "brew upgrade --cask gordasgdc/tap/pe-sarma"
expect "butoane: Copiar comando / Más tarde" "$B1" "Copiar comando"; expect "fără Actualizar ahora" "$([ "${B1#*Actualizar ahora}" = "$B1" ] && echo no-update-now)" "no-update-now"
ax 'click button "Copiar comando" of window 1' >/dev/null; sleep 1
expect "comanda e în clipboard" "$(pbpaste)" "^brew upgrade --cask gordasgdc/tap/pe-sarma$"
printf '%s' "$SAVED_CLIP" | pbcopy
expect "aplicația instalată neschimbată" "$(ver)" "^1.1.1$"
stop
echo "### 9. brew upgrade (traseul pe care îl arată aplicația), apoi pornire"
cask 1.1.2; brew upgrade --cask $TAP/pe-sarma-test 2>&1 | tail -2
expect "după brew upgrade versiunea e 1.1.2" "$(ver)" "^1.1.2$"
expect "semnătura copiei Homebrew e validă" "$(codesign --verify --deep --strict "$APP" 2>&1; echo rc=$?)" "rc=0"
defaults write $DOM loginOfferedVersion -string 1.1.2
start "file://$T/feed.json"
expect "limba spaniolă păstrată după upgrade" "$(dump)" "Idioma"
expect "preferințe păstrate" "$(defaults read $DOM probeMarker) $(defaults read $DOM PeSarmaLanguage)" "keep-me es"
stop; echo "$PASS passed, $FAIL failed"; [ $FAIL -eq 0 ]
