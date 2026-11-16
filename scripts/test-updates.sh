#!/bin/bash
# Logic checks for the update code, without network or the installed app.
set -euo pipefail
cd "$(dirname "$0")/.."
D="$(mktemp -d "${PESARMA_BUILD_DIR:-${TMPDIR:-/tmp}}/pesarma-updates.XXXXXX")"
trap 'rm -rf "$D"' EXIT
swiftc -module-name PeSarma -DUPDATE_TEST -target "$(uname -m)-apple-macosx14.0" -parse-as-library \
  Sources/PeSarma/Updates.swift Sources/PeSarma/Localization.swift scripts/test-updates.swift -o "$D/checks"
"$D/checks"
