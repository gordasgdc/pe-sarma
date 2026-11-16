#!/usr/bin/env python3
"""Generates README.md (Romanian, the main language) and docs/i18n/README.{en,es}.md with the same structure.
Images: docs/media/hero-<lang>-{light,dark}.png, docs/media/demo-<lang>.gif (frames of the scripted tour)."""
import os,re
R=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GH='https://github.com/gordasgdc/pe-sarma'
D={}
D['ro']=dict(name='README.md',pre='',site='https://gordas.dev/pe-sarma/?lang=ro',
 tag='Pe sârmă — ediția în limba română, publicată și întreținută de Cristi Gordaș.',
 alt='Pe sârmă. Capturile și ce copiezi, la un gest distanță. Trei capturi și o notă atârnă pe un fir de cupru sub bara de meniu macOS.',
 try_='Încearcă în browser, pe gordas.dev/pe-sarma', free='Gratuită și cu sursă deschisă. Pentru macOS 14 sau mai nou.', dl='Descarcă', bfs='Compilare din sursă',
 h1='Departe de ochi. La îndemână.',
 p1='Fiecare captură de ecran și tot ce copiezi se agață pe un fir chiar sub bara de meniu. Lasă cursorul în mijlocul barei și firul coboară; îndepărtează-l și dispare.',
 demoalt='Cursorul se oprește în bara de meniu, firul coboară, o captură se agață, un clic o copiază, o tragi într-un folder, cauți un cuvânt și apoi anulezi.',
 demonote='Animația este o simulare a aplicației, cu date sintetice. Cursorul și efectul fiecărui gest se văd în ea.',
 h2='Un gest pentru fiecare lucru.', gh=('Gest','Efect'),
 rows=[('Clic','Copiază. O notă se copiază cu textul formatat.'),('Apăsare lungă','Deschide în Adnotare. O notă se deschide pentru editare.'),('Dublu clic','Deschide în Previzualizare. Un link se deschide în browser.'),('Tragere într-o aplicație','Trimite o copie. Rămâne pe fir.'),('Tragere într-un folder','O păstrezi acolo. Pleacă de pe fir.'),('Tragere în Coș sau clic pe cruciuliță','Scapi de ea.'),('Shift-clic','Selectezi mai multe; meniul, ⌘C, ⌫ și tragerea acționează asupra tuturor.'),('⌘Z cu cursorul pe fir','Anulează ultima acțiune, inclusiv pentru o selecție.'),('Spațiu cu cursorul pe o imagine','Previzualizare rapidă (Force Touch la fel).'),('Clic dreapta','Partajează, fixează pe fir, ține în fața ferestrelor, arată în Finder.'),('În Finder: clic dreapta → Agață pe fir','O agață pe fir, fixată.'),('⌃⌥T · ⌃⌥F','Arată sau ascunde firul · caută pe fir (configurabile).')],
 h3='Desktopul tău. În sfârșit liber.', p3='Dă-i capturile tale<sup>1</sup> lui Pe sârmă și sar peste Desktop. Fără miniatură plutitoare, fără așteptare de cinci secunde: fiecare captură se agață în clipa în care o faci, iar doar ce tragi afară rămâne păstrat. Înregistrările de ecran se agață la fel, cu un buton de redare deasupra; apasă lung una ca s-o decupezi. Aceleași scurtături, mai puțină dezordine.',
 fn='<sup>1</sup> Dacă alegi ca Pe sârmă să gestioneze capturile, aplicația schimbă setările de captură din macOS (`com.apple.screencapture`): locația, miniatura plutitoare și destinația. Valorile tale sunt salvate și puse la loc la dezactivare și la închiderea aplicației.',
 h4='Și text, linkuri, imagini copiate.', p4='Le activezi pe rând, la „Agață ce copiezi”, în bara de meniu. Textul copiat se agață ca o notă (prima linie este titlul, Markdown-ul apare formatat, codul își păstrează liniile). O adresă web se agață ca link, cu site-ul și calea. Nimic nu se păstrează din câmpurile de parolă, din ce marchează ca privat un manager de parole sau din alt dispozitiv prin Clipboard universal.',
 h5='Găsește orice pe fir.', p5='Apasă ⌃⌥F și scrie. Rămân pe fir doar potrivirile: cuvintele din capturi (citite local, pe Mac, în clipa în care se agață) și cuvintele din fiecare notă și link. Căutarea ignoră diacriticele: „sarma” găsește „sârmă”. Return copiază cea mai nouă potrivire.',
 h6='Privat prin construcție.', p6='Fără cont. Fără statistici. Rețeaua se folosește doar când apeși „Caută actualizări…”, ca să citească un fișier public de pe gordas.dev. Pe sârmă rulează în întregime pe Mac-ul tău, inclusiv citirea textului din capturi, și nimic din ce agăți nu-l părăsește. Dacă refuzi accesul la un folder, aplicația rămâne pornită, iar capturile din acel folder nu apar pe fir. Jurnalul local de diagnostic este în `~/Library/Logs/PeSarma/`, iar meniul „Diagnostic” exportă un ZIP inspectabil, fără capturi, text copiat sau căi.',
 h7='Specificații',
 spec=[('Compatibilitate','macOS 14 Sonoma sau mai nou, Apple Silicon și Intel.'),('Limbi','Română, spaniolă, engleză — după limba sistemului (română implicit). O schimbi oricând din meniul pictogramei: Limbă → Română, Español, English sau Limba sistemului.'),('Construită cu','Swift, AppKit și SwiftUI.'),('Acces la rețea','Doar la „Caută actualizări…”: citește un fișier public de pe gordas.dev.'),('Preț','Gratuită: fără cont, cheie de activare, abonament sau perioadă de probă.'),('Licență','MIT pentru cod. Numele și pictograma acestei ediții sunt proprii.')],
 h8='Instalare', i1='Descarcă imaginea disc din [ultima versiune]('+GH+'/releases/latest) și trage aplicația în Aplicații. Este semnată cu Developer ID și notarizată de Apple.', i2='Sau cu Homebrew:', h8u='Actualizare', u1='Din aplicație: meniul pictogramei → Caută actualizări…. Pentru o copie din imaginea disc, „Actualizează acum” descarcă versiunea nouă, îi verifică semnătura și o înlocuiește, cu setările și limba păstrate. Pentru o copie instalată cu Homebrew, aplicația arată comanda de mai jos, cu buton de copiere:',
 h9='Compilare din sursă', b1='Necesită uneltele Swift. Verificări: `swift scripts/check-strings.swift`, `scripts/test-selection.sh`, `scripts/test-diagnostics.sh`. Imaginea disc: `NOTARY_PROFILE=<profil> scripts/make-dmg.sh`. Identitatea vizuală: `PESARMA_BRAND_OUT=<folder> scripts/make-brand-assets.sh`. Actualizarea de la Tendedero: [docs/UPSTREAM.md](UPSTREAM_PATH).',
 cred='Pe sârmă este ediția în limba română a [Tendedero]('+'https://github.com/alejandrobujan/tendedero'+'), creat de Alejandro Buján (licență MIT), publicată și întreținută de Cristi Gordaș, cu nume, pictogramă și materiale proprii. Vezi [LICENSE](LICENSE_PATH) și [NOTICE.md](NOTICE_PATH).')
D['en']=dict(name='docs/i18n/README.en.md',pre='../../',site='https://gordas.dev/pe-sarma/?lang=en',
 tag='Pe sârmă — the Romanian edition, published and maintained by Cristi Gordaș.',
 alt='Pe sârmă. Your screenshots and copies, one gesture away. Three screenshots and a note hang from a copper wire under the macOS menu bar.',
 try_='Try it in your browser at gordas.dev/pe-sarma', free='Free and open source. For macOS 14 and later.', dl='Download', bfs='Build from source',
 h1='Out of sight. Within reach.',
 p1='Every screenshot you take, and anything you copy, hangs on a line right under the menu bar. Rest the pointer in the middle of the bar and it glides down; move away and it is gone.',
 demoalt='The pointer rests on the menu bar, the line comes down, a screenshot hangs, a click copies it, you drag it to a folder, search for a word and then undo.',
 demonote='The animation is a simulation of the app, with synthetic data. The pointer and the effect of each gesture are visible in it.',
 h2='A gesture for everything.', gh=('Gesture','Effect'),
 rows=[('Click','Copies. A note is copied with its formatted text.'),('Long press','Opens in Markup. A note opens for editing.'),('Double click','Opens in Preview. A link opens in the browser.'),('Drag into an app','Sends a copy. It stays on the line.'),('Drag into a folder','You keep it there. It leaves the line.'),('Drag to the Trash or click the cross','Discards it.'),('Shift-click','Select several; the menu, ⌘C, ⌫ and dragging act on all of them.'),('⌘Z with the cursor on the line','Undoes the last action, including for a selection.'),('Space over an image','Quick Look (Force Touch too).'),('Right click','Share, pin to the line, keep in front of windows, show in Finder.'),('In Finder: right click → Hang on the line','Hangs it, pinned.'),('⌃⌥T · ⌃⌥F','Show or hide the line · search the line (configurable).')],
 h3='Your Desktop. Finally clear.', p3='Hand Pe sârmă your screenshots<sup>1</sup> and they skip the Desktop entirely. No floating thumbnail, no five-second wait: each capture hangs the instant you take it, and only what you drag out is kept. Screen recordings hang there too, with a play button over them; press and hold one to trim it. Same shortcuts, just less mess.',
 fn='<sup>1</sup> If you let Pe sârmă handle screenshots, the app changes the macOS capture settings (`com.apple.screencapture`): the location, the floating thumbnail and the destination. Your values are saved and put back when you turn it off and when the app quits.',
 h4='Copied text, links and images too.', p4='Turn them on one by one under Hang what I copy in the menu bar. Copied text hangs as a note (the first line is the title, Markdown shows formatted, code keeps its lines). A web address hangs as a link, with its site and path. Nothing is kept from a password field, from what a password manager marks as private, or from another device through Universal Clipboard.',
 h5='Find anything on the line.', p5='Press ⌃⌥F and type. Only the matches stay on the line: the words in a screenshot, read on your Mac the moment it hangs, and the words of every note and link. Search ignores diacritics: “sarma” finds “sârmă”. Return copies the newest match.',
 h6='Private by design.', p6='No account. No analytics. The network is only used when you press “Check for Updates…”, to read a public file on gordas.dev. Pe sârmă runs entirely on your Mac, reading text in screenshots included, and nothing you hang ever leaves it. If you refuse access to a folder, the app keeps running and screenshots from that folder do not appear on the line. The local diagnostic log is in `~/Library/Logs/PeSarma/`; the Diagnostics menu exports an inspectable ZIP with no screenshots, copied text or paths.',
 h7='Tech Specs',
 spec=[('Compatibility','macOS 14 Sonoma or later, on Apple silicon and Intel.'),('Languages','Romanian, Spanish, English — following the system language (Romanian by default). Change it any time from the menu bar icon: Language → Română, Español, English or System language.'),('Built with','Swift, AppKit and SwiftUI.'),('Network access','Only for “Check for Updates…”: it reads a public file on gordas.dev.'),('Price','Free: no account, activation key, subscription or trial period.'),('License','MIT for the code. The name and icon of this edition are its own.')],
 h8='Install', i1='Download the disk image from the [latest release]('+GH+'/releases/latest) and drag the app to Applications. It is signed with a Developer ID and notarized by Apple.', i2='Or with Homebrew:', h8u='Update', u1='From the app: menu bar icon → Check for Updates…. For a copy from the disk image, “Update now” downloads the new version, checks its signature and replaces the app, keeping your settings and language. For a copy installed with Homebrew, the app shows the command below, with a copy button:',
 h9='Build from source', b1='Needs the Swift tools. Checks: `swift scripts/check-strings.swift`, `scripts/test-selection.sh`, `scripts/test-diagnostics.sh`. Disk image: `NOTARY_PROFILE=<profile> scripts/make-dmg.sh`. Visual identity: `PESARMA_BRAND_OUT=<folder> scripts/make-brand-assets.sh`. Updating from Tendedero: [docs/UPSTREAM.md](UPSTREAM_PATH).',
 cred='Pe sârmă is the Romanian edition of [Tendedero](https://github.com/alejandrobujan/tendedero), created by Alejandro Buján (MIT license), published and maintained by Cristi Gordaș, with its own name, icon and materials. See [LICENSE](LICENSE_PATH) and [NOTICE.md](NOTICE_PATH).')
D['es']=dict(name='docs/i18n/README.es.md',pre='../../',site='https://gordas.dev/pe-sarma/?lang=es',
 tag='Pe sârmă — la edición en rumano, publicada y mantenida por Cristi Gordaș.',
 alt='Pe sârmă. Tus capturas y lo que copias, a un gesto de distancia. Tres capturas y una nota cuelgan de un hilo de cobre bajo la barra de menús de macOS.',
 try_='Pruébalo en el navegador en gordas.dev/pe-sarma', free='Gratuita y de código abierto. Para macOS 14 o posterior.', dl='Descargar', bfs='Compilar desde el código',
 h1='Fuera de la vista. Al alcance.',
 p1='Cada captura de pantalla y todo lo que copias cuelga de un hilo justo bajo la barra de menús. Deja el cursor en el centro de la barra y el hilo baja; apártalo y desaparece.',
 demoalt='El cursor se detiene en la barra de menús, el hilo baja, una captura se cuelga, un clic la copia, la arrastras a una carpeta, buscas una palabra y luego deshaces.',
 demonote='La animación es una simulación de la app, con datos sintéticos. En ella se ven el cursor y el efecto de cada gesto.',
 h2='Un gesto para cada cosa.', gh=('Gesto','Efecto'),
 rows=[('Clic','Copia. Una nota se copia con su texto con formato.'),('Pulsación larga','Abre en Marcado. Una nota se abre para editar.'),('Doble clic','Abre en Vista Previa. Un enlace se abre en el navegador.'),('Arrastrar a una app','Envía una copia. Sigue en el hilo.'),('Arrastrar a una carpeta','Te la quedas allí. Sale del hilo.'),('Arrastrar a la Papelera o clic en la cruz','La descarta.'),('Shift-clic','Selecciona varias; el menú, ⌘C, ⌫ y el arrastre actúan sobre todas.'),('⌘Z con el cursor sobre el hilo','Deshace la última acción, también en una selección.'),('Espacio sobre una imagen','Vista rápida (Force Touch también).'),('Clic derecho','Compartir, fijar en el hilo, mantener delante de las ventanas, mostrar en Finder.'),('En Finder: clic derecho → Colgar en el hilo','La cuelga, fijada.'),('⌃⌥T · ⌃⌥F','Muestra u oculta el hilo · busca en el hilo (configurables).')],
 h3='Tu Escritorio. Por fin despejado.', p3='Dale tus capturas<sup>1</sup> a Pe sârmă y se saltan el Escritorio. Sin miniatura flotante, sin esperar cinco segundos: cada captura cuelga en cuanto la haces, y solo se conserva lo que arrastras fuera. Las grabaciones de pantalla cuelgan igual, con un botón de reproducción encima; pulsa largo en una para recortarla. Los mismos atajos, menos desorden.',
 fn='<sup>1</sup> Si dejas que Pe sârmă gestione las capturas, la app cambia los ajustes de captura de macOS (`com.apple.screencapture`): la ubicación, la miniatura flotante y el destino. Tus valores se guardan y se restauran al desactivarlo y al cerrar la app.',
 h4='También texto, enlaces e imágenes copiados.', p4='Actívalos uno a uno en «Colgar lo que copio», en la barra de menús. El texto copiado cuelga como una nota (la primera línea es el título, el Markdown se ve con formato, el código conserva sus líneas). Una dirección web cuelga como enlace, con su sitio y ruta. No se guarda nada de campos de contraseña, de lo que un gestor de contraseñas marca como privado ni de otro dispositivo por Portapapeles universal.',
 h5='Encuentra lo que sea en el hilo.', p5='Pulsa ⌃⌥F y escribe. Solo quedan en el hilo las coincidencias: las palabras de una captura, leídas en tu Mac en cuanto cuelga, y las de cada nota y enlace. La búsqueda ignora los diacríticos: «sarma» encuentra «sârmă». Return copia la coincidencia más reciente.',
 h6='Privada por diseño.', p6='Sin cuenta. Sin analíticas. La red solo se usa cuando pulsas «Buscar actualizaciones…», para leer un archivo público de gordas.dev. Pe sârmă funciona por completo en tu Mac, incluida la lectura del texto de las capturas, y nada de lo que cuelgas sale de él. Si rechazas el acceso a una carpeta, la app sigue abierta y las capturas de esa carpeta no aparecen en el hilo. El registro local está en `~/Library/Logs/PeSarma/`; el menú «Diagnóstico» exporta un ZIP inspeccionable, sin capturas, texto copiado ni rutas.',
 h7='Especificaciones',
 spec=[('Compatibilidad','macOS 14 Sonoma o posterior, en Apple silicon e Intel.'),('Idiomas','Rumano, español, inglés — según el idioma del sistema (rumano por defecto). Cámbialo cuando quieras desde el menú del icono: Idioma → Română, Español, English o Idioma del sistema.'),('Hecha con','Swift, AppKit y SwiftUI.'),('Acceso a la red','Solo con «Buscar actualizaciones…»: lee un archivo público de gordas.dev.'),('Precio','Gratuita: sin cuenta, clave de activación, suscripción ni periodo de prueba.'),('Licencia','MIT para el código. El nombre y el icono de esta edición son propios.')],
 h8='Instalación', i1='Descarga la imagen de disco desde la [última versión]('+GH+'/releases/latest) y arrastra la app a Aplicaciones. Está firmada con Developer ID y notarizada por Apple.', i2='O con Homebrew:', h8u='Actualización', u1='Desde la app: menú del icono → Buscar actualizaciones…. En una copia de la imagen de disco, «Actualizar ahora» descarga la versión nueva, comprueba su firma y reemplaza la app, conservando tus ajustes y el idioma. En una copia instalada con Homebrew, la app muestra el comando de abajo, con botón de copiar:',
 h9='Compilar desde el código', b1='Requiere las herramientas de Swift. Comprobaciones: `swift scripts/check-strings.swift`, `scripts/test-selection.sh`, `scripts/test-diagnostics.sh`. Imagen de disco: `NOTARY_PROFILE=<perfil> scripts/make-dmg.sh`. Identidad visual: `PESARMA_BRAND_OUT=<carpeta> scripts/make-brand-assets.sh`. Actualizar desde Tendedero: [docs/UPSTREAM.md](UPSTREAM_PATH).',
 cred='Pe sârmă es la edición en rumano de [Tendedero](https://github.com/alejandrobujan/tendedero), creado por Alejandro Buján (licencia MIT), publicada y mantenida por Cristi Gordaș, con nombre, icono y materiales propios. Consulta [LICENSE](LICENSE_PATH) y [NOTICE.md](NOTICE_PATH).')
LANGS=[('ro','Română','README.md'),('en','English','docs/i18n/README.en.md'),('es','Español','docs/i18n/README.es.md')]
def rel(frm,to):
    return os.path.relpath(os.path.join(R,to),os.path.dirname(os.path.join(R,frm)))
for k,d in D.items():
    pre=d['pre']; m=lambda n:pre+'docs/media/'+n
    nav='&nbsp;·&nbsp;'.join(n if l==k else '<a href="%s">%s</a>'%(rel(d['name'],p),n) for l,n,p in LANGS)
    t=f'''<picture>
  <source media="(prefers-color-scheme: dark)" srcset="{m(f'hero-{k}-dark.png')}">
  <img src="{m(f'hero-{k}-light.png')}" alt="{d['alt']}">
</picture>

<h3 align="center"><a href="{d['site']}">{d['try_']}&nbsp;&rsaquo;</a></h3>

<p align="center">
  {d['free']}
  <br>
  <a href="{GH}/releases/latest">{d['dl']}&nbsp;&rsaquo;</a>
  &nbsp;&nbsp;
  <a href="#{d['h9'].lower().replace(' ','-').replace('ă','a').replace('î','i').replace('ț','t').replace('ș','s').replace('â','a')}">{d['bfs']}&nbsp;&rsaquo;</a>
  <br><br>
  {nav}
</p>

<p align="center"><b>{d['tag']}</b></p>

<br>

## {d['h1']}

{d['p1']}

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="{m(f'demo-{k}-dark.gif')}">
  <img src="{m(f'demo-{k}-light.gif')}" alt="{d['demoalt']}">
</picture>

<sub>{d['demonote']}</sub>

<br>

## {d['h2']}

| {d['gh'][0]} | {d['gh'][1]} |
|:--|:--|
''' + ''.join(f'| {a} | {b} |\n' for a,b in d['rows']) + f'''
<br>

## {d['h3']}

{d['p3']}

{d['fn']}

<br>

## {d['h4']}

{d['p4']}

<br>

## {d['h5']}

{d['p5']}

<br>

## {d['h6']}

{d['p6']}

<br>

## {d['h7']}

| | |
|:--|:--|
''' + ''.join(f'| **{a}** | {b} |\n' for a,b in d['spec']) + f'''
<br>

## {d['h8']}

{d['i1']}

**{GH}/releases/latest/download/PeSarma.dmg**

{d['i2']}

```sh
brew install --cask gordasgdc/tap/pe-sarma
```

<br>

## {d['h8u']}

{d['u1']}

```sh
brew upgrade --cask gordasgdc/tap/pe-sarma
```

<br>

## {d['h9']}

```sh
git clone {GH}.git
cd pe-sarma
PESARMA_BUILD_DIR=/path/to/build scripts/build-app.sh
open /path/to/build/PeSarma.app
```

{d['b1'].replace('UPSTREAM_PATH',rel(d['name'],'docs/UPSTREAM.md'))}

<br>

<p align="center">
  <img src="{m('icon.png')}" width="64" height="64" alt="">
  <br>
  {re.sub(r'\[([^\]]+)\]\(([^)]+)\)',r'<a href="\2">\1</a>',d['cred'].replace('LICENSE_PATH',rel(d['name'],'LICENSE')).replace('NOTICE_PATH',rel(d['name'],'NOTICE.md')))}
</p>
'''
    path=os.path.join(R,d['name']); os.makedirs(os.path.dirname(path),exist_ok=True); open(path,'w',encoding='utf-8').write(t)
print('ok')
