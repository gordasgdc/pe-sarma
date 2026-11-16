#!/bin/bash
# Real-app check of "Check for Updates…" and "Update now". The status item
# cannot be reached by accessibility on recent macOS, so this uses a test build
# (-DMENU_PROBE -DUPDATE_TEST, never shipped) that runs a menu item by path on
# SIGUSR2; the alerts are real NSAlerts, read and clicked through accessibility.
# The feed is a local file and the "installed" apps are copies under their own
# bundle id and preferences domain, so the installed app and its settings are
# not touched. Needs the Developer ID identity (the app checks the signature).
# Usage: PESARMA_BUILD_DIR=/path scripts/probe-updates.sh   (BUILD_DIR holds build/PeSarma.app)
set -uo pipefail
cd "$(dirname "$0")/.."
B="${PESARMA_BUILD_DIR:?}"; ID="${PESARMA_SIGN_ID:-Developer ID Application}"
DOM=dev.gordas.PeSarma.updtest
T="$B/e2e"; RUN="$T/run"; rm -rf "$T"; mkdir -p "$RUN" "$T/direct" "$T/feeds" "$T/dmg"
OLD=1.1.1; NEW=1.1.2
swift build -c debug --scratch-path "$B/probe/swiftpm" -Xswiftc -DMENU_PROBE -Xswiftc -DUPDATE_TEST >/dev/null || exit 1
BIN="$(swift build -c debug --scratch-path "$B/probe/swiftpm" --show-bin-path)/PeSarma"

# mkapp <dest> <version> <bundle id> [adhoc]
mkapp() {
  rm -rf "$1"; ditto "$B/build/PeSarma.app" "$1"; cp "$BIN" "$1/Contents/MacOS/PeSarma"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $3" -c "Set :CFBundleShortVersionString $2" "$1/Contents/Info.plist"
  if [ "${4:-}" = adhoc ]; then codesign --force --deep --sign - "$1" 2>/dev/null; else codesign --force --deep --options runtime --sign "$ID" "$1" 2>/dev/null; fi
}
# mkdmg <name> <app> -> $T/dmg/<name>.dmg
mkdmg() { rm -rf "$T/stage-$1"; mkdir "$T/stage-$1"; ditto "$2" "$T/stage-$1/$(basename "$2")"
  hdiutil create -quiet -srcfolder "$T/stage-$1" -volname "PeSarmaT" -format UDZO -ov "$T/dmg/$1.dmg"; rm -rf "$T/stage-$1"; }
# feed <name> <dmg> [sha-override] [version-override]
feed() { local f="$T/dmg/$2.dmg"; local sha="${3:-$(shasum -a 256 "$f" | cut -d' ' -f1)}"; local size; size=$(stat -f%z "$f")
  cat > "$T/feeds/$1.json" <<J
{"version":"${4:-$NEW}","download_url":"file://$f","sha256":"$sha","size":$size,
 "changes":{"ro":"Verificarea actualizărilor se face acum în aplicație.","es":"La comprobación de actualizaciones ahora se hace en la app.","en":"Update checks now happen inside the app."}}
J
}

mkapp "$T/new.app" $NEW $DOM; mkdmg good "$T/new.app"; feed newer good
echo '{"version":"'$OLD'","download_url":"file:///x","sha256":"'$(printf 'a%.0s' $(seq 64))'","size":1}' > "$T/feeds/same.json"
echo '<html>not a feed</html>' > "$T/feeds/garbage.json"
feed badsha good "$(printf 'b%.0s' $(seq 64))"
mkapp "$T/adhoc.app" $NEW $DOM adhoc; mkdmg adhoc "$T/adhoc.app"; feed adhoc adhoc
mkapp "$T/ver.app" 1.1.9 $DOM; mkdmg ver "$T/ver.app"; feed wrongversion ver
mkapp "$T/id.app" $NEW dev.gordas.Other; mkdmg id "$T/id.app"; feed wrongid id

APP="$T/direct/PeSarmaT.app"
pid() { pgrep -f "$APP/Contents/MacOS" | head -1; }
stop() { pkill -9 -f "$T/direct/PeSarmaT.app/Contents/MacOS" 2>/dev/null; sleep 2; }
# Started directly: through `open` the status item menu is not reachable by the probe.
start() { PESARMA_PROBE_DIR="$RUN" PESARMA_FEED_URL="$1" nohup "$APP/Contents/MacOS/PeSarma" >/dev/null 2>&1 & sleep 6; }
dump() { rm -f "$RUN/menu.txt"; kill -USR1 "$(pid)"; sleep 1; cat "$RUN/menu.txt"; }
pick() { printf '%s' "$1" > "$RUN/pick"; kill -USR2 "$(pid)"; }
ax() { osascript -e "tell application \"System Events\" to tell (first process whose bundle identifier is \"$DOM\") to $1" 2>/dev/null; }
alert() { for _ in $(seq 1 24); do t=$(ax 'return (value of every static text of window 1) as text'); [ -n "$t" ] && break; sleep 0.5; done
  echo "    texto: $t"; echo "    butoane: $(ax 'return (name of every button of window 1) as text')"; }
ver_on_disk() { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist"; }
PASS=0; FAIL=0
expect() { if echo "$2" | grep -q -- "$3"; then echo "PASS: $1"; PASS=$((PASS+1)); else echo "FAIL: $1 (nu conține: $3)"; FAIL=$((FAIL+1)); fi; }
check_item() { case "$1" in es) echo "Buscar actualizaciones…";; ro) echo "Caută actualizări…";; *) echo "Check for Updates…";; esac; }
reset_prefs() { defaults delete $DOM 2>/dev/null; for k in welcomed copyingOffered inboxOffered; do defaults write $DOM $k -bool true; done
  defaults write $DOM PeSarmaLanguage "$1"; defaults write $DOM inboxEnabled -bool false
  defaults write $DOM loginOfferedVersion -string "$OLD"; }
SC_BEFORE="$(defaults read com.apple.screencapture 2>&1)"

# scenario <name> <lang> <feed file or url> -> leaves the alert open, prints it
scenario() { stop; reset_prefs "$2"; mkapp "$APP" $OLD $DOM; start "$3"; pick "$(check_item "$2")"; echo "== $1 [$2]"; alert; }

echo "### 1. Versiune mai veche instalată (1.1.1), feed cu 1.1.2, copie directă"
scenario "mai veche" es "file://$T/feeds/newer.json"; O=$(alert); expect "ofertă 1.1.2 în spaniolă" "$O" "Pe sârmă 1.1.2 está disponible"; expect "text din feed" "$O" "La comprobación de actualizaciones"; expect "butoane Actualizar ahora / Más tarde" "$O" "Actualizar ahora"
ax 'click button "Más tarde" of window 1' >/dev/null; sleep 1; expect "Más tarde nu schimbă nimic" "$(ver_on_disk)" "^$OLD$"
echo "### 2. Versiune la zi"
scenario "la zi" ro "file://$T/feeds/same.json"; expect "Ai ultima versiune" "$(alert)" "Ai ultima versiune"; ax 'click button "OK" of window 1' >/dev/null
echo "### 3. Conexiune indisponibilă"
scenario "offline" en "https://127.0.0.1:9/update.json"; O=$(alert); expect "mesaj de conexiune" "$O" "could not reach the update server"; expect "restul aplicației funcționează" "$O" "keeps working"; ax 'click button "OK" of window 1' >/dev/null
sleep 1; expect "meniul rămâne funcțional offline" "$(dump)" "Check for Updates"
echo "### 4. Feed invalid"
scenario "feed invalid" ro "file://$T/feeds/garbage.json"; expect "feed invalid" "$(alert)" "nu sunt valide"; ax 'click button "OK" of window 1' >/dev/null
echo "### 5. Refuzuri la instalare (versiunea instalată rămâne)"
for c in "badsha|nu corespunde celui publicat" "adhoc|nu este a dezvoltatorului" "wrongversion|altă versiune decât cea anunțată" "wrongid|nu conține Pe sârmă"; do
  n="${c%%|*}"; want="${c#*|}"; scenario "$n" ro "file://$T/feeds/$n.json" >/dev/null; P=$(pid)
  ax 'click button "Actualizează acum" of window 1' >/dev/null; sleep 1
  for _ in $(seq 1 30); do t=$(ax 'return (value of every static text of window 1) as text'); echo "$t" | grep -q "nu s-a putut instala\|$want" && break; sleep 1; done
  expect "$n: refuzat ($want)" "$t" "$want"; expect "$n: aplicația instalată neschimbată" "$(ver_on_disk) $([ "$(pid)" = "$P" ] && echo same-process)" "^$OLD same-process$"
  ax 'click button "OK" of window 1' >/dev/null
done
echo "### 6. Actualizare reală (copie directă), limba spaniolă + preferințe păstrate"
stop; reset_prefs es; defaults write $DOM probeMarker -string keep-me; mkapp "$APP" $OLD $DOM; start "file://$T/feeds/newer.json"
P=$(pid); pick "Buscar actualizaciones…"; alert >/dev/null
ax 'click button "Actualizar ahora" of window 1' >/dev/null
for _ in $(seq 1 40); do [ "$(ver_on_disk)" = "$NEW" ] && [ -n "$(pid)" ] && [ "$(pid)" != "$P" ] && break; sleep 1; done; sleep 4
expect "versiunea de pe disc e 1.1.2" "$(ver_on_disk)" "^$NEW$"; expect "proces nou pornit" "$([ -n "$(pid)" ] && [ "$(pid)" != "$P" ] && echo yes)" "yes"
expect "semnătura copiei noi e validă" "$(codesign --verify --deep --strict "$APP" 2>&1; echo rc=$?)" "rc=0"
expect "după actualizare apare o dată oferta de pornire la login (comportament existent, pe versiune nouă)" "$(ax 'return (value of every static text of window 1) as text')" "iniciar sesión"
ax 'click button "Ahora no" of window 1' >/dev/null; sleep 1
stop; start "file://$T/feeds/newer.json"
expect "limba spaniolă păstrată (aplicația nouă, pornită din nou)" "$(dump)" "Idioma"
expect "preferințe păstrate" "$(defaults read $DOM probeMarker) $(defaults read $DOM PeSarmaLanguage) $(defaults read $DOM inboxOffered)" "keep-me es 1"
expect "setările macOS de captură neschimbate" "$(defaults read com.apple.screencapture 2>&1 | diff - <(echo "$SC_BEFORE") >/dev/null && echo same)" "same"
pick "Buscar actualizaciones…"; sleep 0.5
echo "### 7. Noua versiune, după actualizare: la zi"
stop; start "file://$T/feeds/newer.json"; pick "Buscar actualizaciones…"; expect "după actualizare: la ultima versiune" "$(alert)" "Tienes la última versión"; ax 'click button "OK" of window 1' >/dev/null
stop; defaults delete $DOM 2>/dev/null
echo "$PASS passed, $FAIL failed"; [ $FAIL -eq 0 ]
