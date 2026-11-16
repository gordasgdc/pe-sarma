# Pe sârmă

🇷🇴 Română · [🇬🇧 English](#english) · [🇪🇸 Español](#español)

**Pe sârmă — ediția în limba română, publicată și întreținută de Cristi Gordaș.**

Capturile de ecran și tot ce copiezi se agață pe un fir chiar sub bara de meniu.
Le găsești după conținut și le folosești cu gesturi directe. Gratuită, cu sursă deschisă,
pentru macOS 14 sau mai nou. Fără cont, fără cheie de activare, fără abonament.

Site, demonstrație interactivă și descărcare: **https://gordas.dev/pe-sarma/**

Descărcare directă (ultima versiune): https://github.com/gordasgdc/pe-sarma/releases/latest/download/PeSarma.dmg

Aplicația este bazată pe [Tendedero](https://github.com/alejandrobujan/tendedero), creat de
Alejandro Buján (licență MIT). Vezi [NOTICE.md](NOTICE.md) și [LICENSE](LICENSE).

## Gesturi

| Gest | Efect |
|:--|:--|
| Clic | Copiază. O notă se copiază cu textul formatat. |
| Apăsare lungă | Deschide în Adnotare. O notă se deschide pentru editare. |
| Dublu clic | Deschide în Previzualizare. Un link se deschide în browser. |
| Force Touch | Previzualizare rapidă. |
| Tragere într-o aplicație | Trimite o copie. Rămâne pe fir. |
| Tragere într-un folder | O păstrezi acolo. Pleacă de pe fir. |
| Tragere în Coș sau clic pe cruciuliță | Scapi de ea. |
| Shift-clic | Selectezi mai multe; meniul, ⌘C, ⌫ și tragerea acționează asupra tuturor. Esc sau un clic simplu anulează selecția. |
| ⌘Z cu cursorul pe fir | Anulează ultima acțiune (aruncare, fixare, salvare pe Desktop), inclusiv pentru o selecție. |
| Spațiu cu cursorul pe o imagine | Previzualizare rapidă. |
| Clic dreapta → Partajează | Trimite prin AirDrop, Mesaje, Mail etc. Rămâne pe fir. |
| Clic dreapta → Fixează | O păstrează pe fir, la stânga nodului. |
| Clic dreapta → Ține în față | O scoate de pe fir și o ține în fața ferestrelor. |
| În Finder: clic dreapta pe o imagine sau un fișier text → Agață pe fir | O agață pe fir, fixată. |
| Cursorul în mijlocul barei de meniu | Coboară firul pe ecranul respectiv. |
| ⌃⌥T | Arată sau ascunde firul (configurabil din bara de meniu, la „Scurtătură”). |
| ⌃⌥F | Caută pe fir (configurabil). |

## Ce face

- **Capturi și înregistrări de ecran** apar pe fir în clipa în care le faci. Pe înregistrări poți apăsa lung pentru a le decupa.
- **Ce copiezi**: imagini, text (ca notă; Markdown formatat, cod cu liniile păstrate) și linkuri, activabile separat, la „Agață ce copiezi”.
- **Căutare** în textul din capturi (citit local, pe Mac, cu recunoașterea de text din sistem), în note și în linkuri. Căutarea ignoră diacriticele: „sarma” găsește „sârmă”.
- **Confidențialitate**: nu se păstrează nimic din câmpurile de parolă, din ce marchează ca privat un manager de parole sau din alt dispozitiv prin Clipboard universal. Fără rețea, fără statistici.

### Ce setări schimbă „Gestionează capturile”

Dacă alegi ca Pe sârmă să gestioneze capturile, aplicația schimbă setările de captură din macOS (`com.apple.screencapture`): locația salvării, miniatura plutitoare și destinația (fișier). Valorile tale anterioare sunt salvate și puse la loc la dezactivare și la închiderea aplicației.

### Permisiuni

Pe sârmă urmărește folderul în care macOS salvează capturile (implicit al ei, în `~/Library/Application Support/PeSarma`) și, la cerere, folderele pe care le adaugi tu. macOS poate cere acces la Desktop, Documente sau Descărcări. Dacă refuzi, aplicația rămâne pornită, iar capturile din acel folder nu apar pe fir.

## Instalare

Deschide imaginea disc `PeSarma-<versiune>.dmg` din [Releases](https://github.com/gordasgdc/pe-sarma/releases) și trage aplicația în Aplicații. Este semnată cu Developer ID și notarizată de Apple.

Sau cu Homebrew (același DMG notarizat din Releases):

```sh
brew install --cask gordasgdc/tap/pe-sarma
```

## Compilare din sursă

```sh
git clone https://github.com/gordasgdc/pe-sarma.git
cd pe-sarma
PESARMA_BUILD_DIR=/calea/ta/de/build scripts/build-app.sh
open /calea/ta/de/build/PeSarma.app
```

Necesită uneltele Swift (Xcode opțional). Verificări: `swift scripts/check-strings.swift`, `scripts/test-selection.sh`, `scripts/test-diagnostics.sh`. Imaginea disc: `NOTARY_PROFILE=<profil> scripts/make-dmg.sh`.

## Diagnostic

Jurnalul local este în `~/Library/Logs/PeSarma/`. Meniul „Diagnostic” permite deschiderea folderului, exportul unui ZIP inspectabil (fără capturi, text copiat sau căi) și copierea ID-ului sesiunii. Nimic nu este trimis automat.

## Licență

Cod: MIT (vezi [LICENSE](LICENSE)). Numele „Pe sârmă” și pictograma sunt ale acestei ediții.

---

## English

**Pe sârmă — the Romanian edition, published and maintained by Cristi Gordaș.**

Screenshots and everything you copy hang on a line right under the menu bar. Search them by content and use them with direct gestures. Free, open source, macOS 14 or later. No account, no activation key, no subscription. The app follows the system language (Romanian, English, Spanish; Romanian fallback), or a per-app language set in System Settings.

Site and interactive demo: https://gordas.dev/pe-sarma/ · Download: https://github.com/gordasgdc/pe-sarma/releases/latest/download/PeSarma.dmg

Install: `brew install --cask gordasgdc/tap/pe-sarma` or the DMG from Releases. Based on [Tendedero](https://github.com/alejandrobujan/tendedero) by Alejandro Buján (MIT). Gestures: click copies, long press annotates, double click previews, drag out sends a copy, Shift-click selects several, ⌘Z undoes, ⌃⌥F searches. Build and logs: see the Romanian sections above.

## Español

**Pe sârmă — la edición en rumano, publicada y mantenida por Cristi Gordaș.**

Las capturas de pantalla y todo lo que copias se cuelgan de un hilo bajo la barra de menús. Búscalas por contenido y úsalas con gestos directos. Gratuita, de código abierto, macOS 14 o posterior. Sin cuenta, sin clave de activación, sin suscripción. La app sigue el idioma del sistema (rumano, inglés, español; rumano por defecto) o el idioma por app de Ajustes del Sistema.

Sitio y demo interactiva: https://gordas.dev/pe-sarma/ · Descarga: https://github.com/gordasgdc/pe-sarma/releases/latest/download/PeSarma.dmg

Instalación: `brew install --cask gordasgdc/tap/pe-sarma` o el DMG de Releases. Basada en [Tendedero](https://github.com/alejandrobujan/tendedero) de Alejandro Buján (MIT). Gestos: clic copia, pulsación larga anota, doble clic previsualiza, arrastrar fuera envía una copia, Shift-clic selecciona varias, ⌘Z deshace, ⌃⌥F busca.
