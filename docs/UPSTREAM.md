# Cum urmărim Tendedero

Pe sârmă este un fork al [Tendedero](https://github.com/alejandrobujan/tendedero) (MIT). Baza fixată pentru 1.0.0 și 1.1.0: `e362da6d92e7ca9dd141de4017eae779dc1e4284` (tag local `upstream-base`), cu 8 commituri după `upstream/v2.0.0`.

## Taguri

- Taguri proprii (release-uri Pe sârmă): `v1.0.0`, `v1.1.0`… Se împing explicit, unul câte unul.
- Taguri upstream: doar sub `upstream/` (`upstream/v2.0.0`…), aduse cu `git fetch upstream` (configurat: `+refs/tags/*:refs/tags/upstream/*`). Nu se împing niciodată.
- `upstream-base` marchează baza curentă preluată.

Ce este al nostru: localizarea (`Sources/PeSarma/Resources/*.lproj`), identitatea (`scripts/brand/`, `scripts/make-brand-assets.sh`), jurnalul de diagnostic (`Diagnostics.swift`), remedierea pornirii watcher-ului, scripturile de distribuție (`scripts/`), site-ul (`site/`), documentația (`README*.md`, `docs/`). Restul codului din `Sources/PeSarma/` este upstream, redenumit.

## Preluarea unei versiuni noi

```sh
git fetch upstream
git log --oneline upstream-base..upstream/main          # ce s-a schimbat
git diff upstream-base upstream/main -- Sources scripts  # codul; calea Sources/Tendedero ↔ Sources/PeSarma
```

1. Aplică modificările pe o ramură: `git checkout -b upstream-<versiune>`; porți fișierele din `Sources/Tendedero/` în `Sources/PeSarma/` (același nume, `Tendedero` → `PeSarma`, `L("…")` păstrat).
2. Textele noi: `swift scripts/check-strings.swift` listează cheile lipsă din `ro`, `es`, `en`; completează-le.
3. Ce nu se preia: numele și pictograma Tendedero, imaginile din `docs/` upstream (excluse de licență).
4. Retestare: `scripts/test-selection.sh`, `scripts/test-diagnostics.sh`, `scripts/probe-e2e.sh`, `scripts/probe-race.sh`, apoi o verificare manuală (captură, clic, tragere, ⌘Z, căutare, dezactivare).
5. Actualizează baza: `git tag -f upstream-base <commit-upstream>` și această pagină; incrementează versiunea; release nou (DMG, cask, catalog).

Nu se împinge niciodată un tag upstream în acest repository.
