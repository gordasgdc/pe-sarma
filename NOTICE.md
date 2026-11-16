# Atribuire

**Pe sârmă — ediția în limba română, publicată și întreținută de Cristi Gordaș.**

Pe sârmă este bazată pe [Tendedero](https://github.com/alejandrobujan/tendedero),
creat de Alejandro Buján și publicat sub licență MIT. Punctul de plecare este
versiunea 2.0.0 plus modificările ulterioare, până la commitul upstream
`e362da6d92e7ca9dd141de4017eae779dc1e4284` (14 noiembrie 2026), fixat în acest
repository prin eticheta `upstream-base`. Istoricul autorilor upstream este păstrat
în acest repository (`git shortlog -sne upstream-base`).

Notificarea de copyright și permisiunile MIT originale sunt în [LICENSE](LICENSE).

## Ce s-a schimbat față de upstream

- Nume, identificator de pachet (`dev.gordas.PeSarma`), pictogramă și materiale vizuale proprii.
- Interfață integral în limba română (singura limbă livrată).
- Fereastra „Despre Pe sârmă” cu creditele ediției și ale upstream-ului.
- Jurnal local de diagnostic și export de diagnostic, fără conținut din capturi sau clipboard.
- Scripturi de build care scriu într-un director ales (`PESARMA_BUILD_DIR`).
- Fără canale de actualizare în rețea: „Caută actualizări…” deschide pagina proiectului în browser.
