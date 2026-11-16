#!/bin/bash
# Compiles Diagnostics.swift with its checks and runs them in a scratch folder.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="${PESARMA_BUILD_DIR:-${TMPDIR:-/tmp}}/diag-test"
mkdir -p "$WORK"
cp Sources/PeSarma/Diagnostics.swift "$WORK/Diagnostics.swift"
cp scripts/test-diagnostics.swift "$WORK/main.swift"
swiftc -O -o "$WORK/test-diagnostics" "$WORK/Diagnostics.swift" "$WORK/main.swift"
"$WORK/test-diagnostics" "$WORK/logs"
