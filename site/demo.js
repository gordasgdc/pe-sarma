(function(){
'use strict';
var $=function(i){return document.getElementById(i)};
var line=$('line'),cards=$('cards'),toast=$('toast'),hint=$('hint'),q=$('q'),search=$('search'),pv=$('preview');
var items=[],undo=[],uid=0,selected={},toastT=0,reduce=window.matchMedia&&matchMedia('(prefers-reduced-motion: reduce)').matches;
var texts=[
 {t:'Idei pentru sâmbătă',b:'Piața de dimineață, cafea la Șarpele Roșu, apoi o plimbare prin Parcul Carol.'},
 {t:'Listă de cumpărături',b:'Roșii, usturoi, țuică de prune, pâine caldă, sarmale pentru duminică.'},
 {t:'Adresă',b:'Strada Sârmei nr. 12, ap. 3, București. Interfon 03.'},
 {t:'Cod ciudat',b:'const sarma = rosii.map(x => x.frunza);'},
 {t:'Rețetă',b:'Foi de varză, carne tocată, orez, ceapă, boia dulce, o lingură de pastă de roșii.'}];
var shots=[ 'Captură ecran 9.41.12','Captură ecran 9.42.03','Captură ecran 9.43.40','Captură ecran 9.45.18'];
function fold(s){return String(s).normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[șş]/gi,'s').replace(/[țţ]/gi,'t').toLowerCase()}
function say(m){toast.textContent=m;toast.classList.add('show');clearTimeout(toastT);toastT=setTimeout(function(){toast.classList.remove('show')},1900)}
function setLine(on){line.classList.toggle('open',on);$('b-line').setAttribute('aria-pressed',on);$('b-line').textContent=on?'Ascunde firul':'Arată firul';hint.parentNode.parentNode.style.opacity=on?.0:1;if(!on)closeSearch()}
function shotFace(n){var w=['#E08E4A','#7b5ea7','#3b8c9e','#c0578a'][n%4];return '<span class="face shot"><span class="win"><i><s></s><s></s><s></s></i><span class="body"><u style="width:80%"></u><u style="width:55%"></u><span class="blk" style="background:linear-gradient(135deg,'+w+',#2b3038)"></span><u style="width:70%"></u></span></span></span>'}
function esc(s){return String(s).replace(/[&<>"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
function render(){
  cards.innerHTML='';
  items.forEach(function(it,i){
    var el=document.createElement('div');el.className='card'+(selected[it.id]?' sel':'');el.setAttribute('role','listitem');el.tabIndex=0;el.dataset.id=it.id;
    el.style.setProperty('--d',(-i*0.7)+'s');
    el.setAttribute('aria-label',(it.kind==='shot'?'Captură: ':'Notă: ')+it.title+(it.pinned?' (fixată)':'')+'. Enter copiază, Delete aruncă.');
    el.innerHTML='<span class="clip"></span>'+(it.pinned?'<span class="pin">fixat</span>':'')+
      (it.kind==='shot'?shotFace(it.n):'<span class="face nt"><b>'+esc(it.title)+'</b>'+esc(it.body)+'</span>')+
      '<span class="cap">'+esc(it.title)+'</span><button class="x" aria-label="Aruncă '+esc(it.title)+'" tabindex="-1">×</button>';
    cards.appendChild(el);
  });
  applyFilter();
}
function applyFilter(){
  var words=fold(q.value).split(/\s+/).filter(Boolean);
  Array.prototype.forEach.call(cards.children,function(el){
    var it=find(el.dataset.id);var hay=fold(it.title+' '+it.body+' '+(it.ocr||''));
    el.classList.toggle('hide',!words.every(function(w){return hay.indexOf(w)>-1}));
  });
}
function find(id){for(var i=0;i<items.length;i++)if(String(items[i].id)===String(id))return items[i]}
function add(it,silent){it.id=++uid;items.unshift(it);undo.push({type:'add',id:it.id});render();if(!silent){setLine(true);say(it.kind==='shot'?'Captura s-a agățat pe fir':'Textul s-a agățat ca notă')}}
function shot(){
  var f=$('flash');f.classList.remove('go');void f.offsetWidth;f.classList.add('go');
  var n=Math.floor(Math.random()*shots.length);
  add({kind:'shot',n:n,title:shots[n],body:'',ocr:'Pe sârmă ședință țară înființare Șarpele'});
}
function copyText(){var t=texts[Math.floor(Math.random()*texts.length)];add({kind:'note',title:t.t,body:t.b})}
function remove(id,why){var i=items.findIndex(function(x){return String(x.id)===String(id)});if(i<0)return;var it=items.splice(i,1)[0];undo.push({type:'del',it:it,i:i});delete selected[id];render();say(why||'Aruncat. Anulează cu ⌘Z sau „Anulează”.')}
function undoLast(){var u=undo.pop();if(!u){say('Nimic de anulat');return}
  if(u.type==='add'){var i=items.findIndex(function(x){return x.id===u.id});if(i>-1)items.splice(i,1)}
  else if(u.type==='del'){items.splice(u.i,0,u.it)}
  else if(u.type==='pin'){var p=find(u.id);if(p)p.pinned=u.was}
  render();say('Anulat')}
function copyItem(it){say('Copiat: '+it.title)}
function openPreview(it){$('pv-t').textContent=it.title;$('pv-b').innerHTML=it.kind==='shot'?'<p>Aici s-ar deschide în Previzualizare. Captura din demonstrație este o ilustrație generată.</p>':'<p>'+esc(it.body)+'</p>';pv.classList.add('open');$('pv-x').focus()}
function closePreview(){pv.classList.remove('open')}
function openSearch(){setLine(true);search.classList.add('open');q.focus()}
function closeSearch(){search.classList.remove('open');q.value='';applyFilter()}

cards.addEventListener('click',function(e){
  var card=e.target.closest('.card');if(!card)return;var it=find(card.dataset.id);
  if(e.target.closest('.x')){remove(it.id);return}
  if(e.shiftKey){selected[it.id]=!selected[it.id];card.classList.toggle('sel');var n=Object.keys(selected).filter(function(k){return selected[k]}).length;say(n+' selectate');return}
  copyItem(it)});
cards.addEventListener('dblclick',function(e){var card=e.target.closest('.card');if(card)openPreview(find(card.dataset.id))});
cards.addEventListener('contextmenu',function(e){var card=e.target.closest('.card');if(!card)return;e.preventDefault();var it=find(card.dataset.id);undo.push({type:'pin',id:it.id,was:!!it.pinned});it.pinned=!it.pinned;render();say(it.pinned?'Fixat pe fir':'Desprins')});
cards.addEventListener('keydown',function(e){
  var card=e.target.closest('.card');if(!card)return;var it=find(card.dataset.id);
  if(e.key==='Enter'){copyItem(it)} else if(e.key===' '){e.preventDefault();openPreview(it)}
  else if(e.key==='Delete'||e.key==='Backspace'){e.preventDefault();var nx=card.nextElementSibling||card.previousElementSibling;remove(it.id);if(nx){var t=cards.querySelector('[data-id="'+nx.dataset.id+'"]');t&&t.focus()}}
  else if(e.key==='p'){undo.push({type:'pin',id:it.id,was:!!it.pinned});it.pinned=!it.pinned;render();say(it.pinned?'Fixat pe fir':'Desprins')}
  else if(e.key==='ArrowRight'&&card.nextElementSibling){card.nextElementSibling.focus()}
  else if(e.key==='ArrowLeft'&&card.previousElementSibling){card.previousElementSibling.focus()}});
/* drag to folder (simulated, pointer events) */
var drag=null;
cards.addEventListener('pointerdown',function(e){var card=e.target.closest('.card');if(!card||e.target.closest('.x')||e.button!==0)return;drag={id:card.dataset.id,x:e.clientX,y:e.clientY,ghost:null}});
window.addEventListener('pointermove',function(e){if(!drag)return;
  if(!drag.ghost&&Math.abs(e.clientY-drag.y)+Math.abs(e.clientX-drag.x)>14){var g=document.createElement('div');g.className='drag-ghost';document.body.appendChild(g);drag.ghost=g}
  if(drag.ghost){drag.ghost.style.left=(e.clientX-55)+'px';drag.ghost.style.top=(e.clientY-40)+'px';var r=$('folder').getBoundingClientRect();$('folder').classList.toggle('over',e.clientX>r.left&&e.clientX<r.right&&e.clientY>r.top&&e.clientY<r.bottom)}});
window.addEventListener('pointerup',function(e){if(!drag)return;var d=drag;drag=null;if(!d.ghost)return;d.ghost.remove();var f=$('folder');var r=f.getBoundingClientRect();var over=e.clientX>r.left&&e.clientX<r.right&&e.clientY>r.top&&e.clientY<r.bottom;f.classList.remove('over');
  if(over){var it=find(d.id);remove(d.id,'„'+it.title+'” s-a păstrat în folderul Proiecte și a plecat de pe fir')}else say('Trimis ca o copie; rămâne pe fir')});
$('b-line').onclick=function(){setLine(!line.classList.contains('open'))};
$('hot').onclick=function(){setLine(!line.classList.contains('open'))};
$('hot').addEventListener('mouseenter',function(){if(!reduce)setLine(true)});
$('b-shot').onclick=shot;$('b-copy').onclick=copyText;$('b-find').onclick=openSearch;$('b-undo').onclick=undoLast;
q.addEventListener('input',applyFilter);
q.addEventListener('keydown',function(e){if(e.key==='Escape'){closeSearch();$('b-find').focus()}else if(e.key==='Enter'){var vis=Array.prototype.filter.call(cards.children,function(c){return !c.classList.contains('hide')})[0];if(vis){copyItem(find(vis.dataset.id));say('Copiat cel mai nou rezultat')}}});
$('pv-x').onclick=function(){closePreview()};
document.addEventListener('keydown',function(e){
  if(e.key==='Escape'&&pv.classList.contains('open')){closePreview();return}
  var mac=$('mac');var inDemo=mac.contains(document.activeElement)||document.activeElement===document.body;
  if(e.ctrlKey&&e.altKey&&(e.key==='f'||e.key==='ƒ'||e.code==='KeyF')){e.preventDefault();openSearch()}
  else if(e.ctrlKey&&e.altKey&&(e.key==='t'||e.code==='KeyT')){e.preventDefault();setLine(!line.classList.contains('open'))}
  else if((e.metaKey||e.ctrlKey)&&e.key==='z'&&inDemo&&document.activeElement!==q){e.preventDefault();undoLast()}});
setInterval(function(){var d=new Date();$('clock').textContent=d.getHours()+':'+('0'+d.getMinutes()).slice(-2)},20000);
(function(){var d=new Date();$('clock').textContent=d.getHours()+':'+('0'+d.getMinutes()).slice(-2)})();
/* starting content */
add({kind:'note',title:'Bun venit',body:'Aceasta este o notă. Fă clic pentru a o copia, dublu clic pentru previzualizare, clic dreapta pentru a o fixa.'},true);
add({kind:'shot',n:0,title:shots[0],body:'',ocr:'Pe sârmă ședință'},true);
undo=[];render();
})();
