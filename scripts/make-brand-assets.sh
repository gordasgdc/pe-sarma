#!/bin/bash
# Reproducible export of the approved identity (copper clip, wire, photo on teal).
# Source: scripts/brand/Logotip.swift (symbol + logo) and scripts/brand/MenuSymbol.swift.
# Usage: [PESARMA_BRAND_OUT=/path] scripts/make-brand-assets.sh
# Writes the masters to $PESARMA_BRAND_OUT and refreshes the derived files that live in the repo.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${PESARMA_BRAND_OUT:?set PESARMA_BRAND_OUT to a folder under /Volumes/CristiGordas/TESTE/...}"
mkdir -p "$OUT"
swift scripts/brand/Logotip.swift "$OUT"                 # PeSarma-Simbol.png, PeSarma-Logotip.png
swift scripts/brand/MenuSymbol.swift "$OUT"              # StatusIcon.png, StatusIcon@2x.png
cp "$OUT/StatusIcon.png" "$OUT/StatusIcon@2x.png" Sources/PeSarma/Resources/
python3 - "$OUT" <<'PY'
import sys
from PIL import Image
o = sys.argv[1]
sym = Image.open(o + "/PeSarma-Simbol.png").convert("RGBA")
logo = Image.open(o + "/PeSarma-Logotip.png").convert("RGBA")
def save(img, p): img.save(p, optimize=True)
site = "site/img/"
save(sym.resize((512, 512), Image.LANCZOS), site + "icon-512.png")
save(sym.resize((32, 32), Image.LANCZOS), site + "favicon-32.png")
tile = Image.new("RGBA", (180, 180), (15, 29, 33, 255))
s = sym.resize((180, 180), Image.LANCZOS); tile.alpha_composite(s); save(tile, site + "apple-touch-icon.png")
og = Image.new("RGBA", (1200, 630), (240, 241, 235, 255))
l = logo.resize((1000, int(1000 * logo.height / logo.width)), Image.LANCZOS)
og.alpha_composite(l, (100, (630 - l.height) // 2)); save(og, site + "og.png")
save(logo.resize((780, 280), Image.LANCZOS), site + "logo.png")
cover = Image.new("RGBA", (512, 512), (240, 241, 235, 255)); cover.alpha_composite(sym.resize((512, 512), Image.LANCZOS)); save(cover, o + "/catalog-cover-512.png")
PY
# macOS icon from the symbol
ICONSET="$OUT/PeSarma.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$OUT/PeSarma-Simbol.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$OUT/PeSarma-Simbol.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT/PeSarma.icns"
echo "Brand assets in $OUT"
