/* KATARINA instrument intelligence control — changes chart, macro calendar, news and risk context together */
(function(){
"use strict";
const defs=[["EURUSD","OANDA:EURUSD","EURUSD · Major","major"],["GBPUSD","OANDA:GBPUSD","GBPUSD · Major","major"],["USDJPY","FX:USDJPY","USDJPY · Major","major"],["USDCHF","FX:USDCHF","USDCHF · Major","major"],["USDCAD","FX:USDCAD","USDCAD · Major","major"],["AUDUSD","FX:AUDUSD","AUDUSD · Major","major"],["NZDUSD","FX:NZDUSD","NZDUSD · Major","major"],["EURGBP","FX:EURGBP","EURGBP · Cross","minor"],["EURJPY","FX:EURJPY","EURJPY · Cross","minor"],["EURCHF","FX:EURCHF","EURCHF · Cross","minor"],["EURCAD","FX:EURCAD","EURCAD · Cross","minor"],["EURAUD","FX:EURAUD","EURAUD · Cross","minor"],["EURNZD","FX:EURNZD","EURNZD · Cross","minor"],["GBPJPY","FX:GBPJPY","GBPJPY · Cross","minor"],["GBPCHF","FX:GBPCHF","GBPCHF · Cross","minor"],["GBPCAD","FX:GBPCAD","GBPCAD · Cross","minor"],["GBPAUD","FX:GBPAUD","GBPAUD · Cross","minor"],["GBPNZD","FX:GBPNZD","GBPNZD · Cross","minor"],["AUDJPY","FX:AUDJPY","AUDJPY · Cross","minor"],["AUDCAD","FX:AUDCAD","AUDCAD · Cross","minor"],["AUDCHF","FX:AUDCHF","AUDCHF · Cross","minor"],["AUDNZD","FX:AUDNZD","AUDNZD · Cross","minor"],["CADJPY","FX:CADJPY","CADJPY · Cross","minor"],["CADCHF","FX:CADCHF","CADCHF · Cross","minor"],["CHFJPY","FX:CHFJPY","CHFJPY · Cross","minor"],["NZDJPY","FX:NZDJPY","NZDJPY · Cross","minor"],["NZDCAD","FX:NZDCAD","NZDCAD · Cross","minor"],["NZDCHF","FX:NZDCHF","NZDCHF · Cross","minor"],["XAUUSD","OANDA:XAUUSD","XAUUSD · Gold","metal"],["XAGUSD","OANDA:XAGUSD","XAGUSD · Silver","metal"],["US30","INDEX:DJI","US30 · Dow Jones (^DJI)","index"],["US500","INDEX:SPX","US500 · S&P 500","index"],["NASDAQ","OANDA:NAS100USD","NASDAQ Composite","index"],["BTCUSD","BITSTAMP:BTCUSD","BTCUSD · Bitcoin","crypto"]];
const map=Object.fromEntries(defs.map(x=>[x[0],{symbol:x[1],label:x[2]}]));
const selectors=[...document.querySelectorAll("[data-instrument-select]")];if(!selectors.length)return;
const $=s=>document.querySelector(s);
let items=[],selected="XAUUSD",publishedNews=[];
const el=(tag,className,value)=>{const n=document.createElement(tag);if(className)n.className=className;if(value!==undefined)n.textContent=String(value);return n};
function save(v){try{localStorage.setItem("katarina_public_instrument",v)}catch(e){}}
function read(){try{const v=localStorage.getItem("katarina_public_instrument");return Object.hasOwn(map,v)?v:"XAUUSD"}catch(e){return "XAUUSD"}}
function renderContext(){const node=$("#instrument-context");if(!node)return;node.replaceChildren();const x=items.find(v=>v.id===selected);if(!x){node.append(el("p","muted","Memuat ringkasan instrumen..."));return}node.append(el("h3","focus-headline",x.headline));
const info=el("p","focus-monitor","Faktor utama untuk diamati: "+x.monitor);node.append(info);
const list=el("ul","focus-driver-list");for(const reason of x.drivers||[]){list.append(el("li",null,reason))}node.append(list);
const disclaimer=el("p","focus-disclosure","Faktor penggerak bersifat analisis makro/mikro bersyarat, bukan arah transaksi atau hasil pengujian KATARINA.");node.append(disclaimer);
const headline=$("#focus-active-symbol");if(headline)headline.textContent=x.label;
const metric=$("#focus-kpi-symbol");if(metric)metric.textContent=x.id;
const src=$("#focus-kpi-data");if(src)src.textContent=x.id==="US30"?"Dow ^DJI":x.id==="US500"?"S&P 500":x.id==="NASDAQ"?"Nasdaq Composite":x.id.length===6&&["USD","EUR","GBP","AUD","NZD","CAD","CHF","JPY"].includes(x.id.slice(0,3))?"FX OHLC 1D":"OHLC Harian";
const ct=$("#focus-kpi-news");if(ct){const num=publishedNews.filter(n=>(n.symbols||[]).includes(selected)).length;ct.textContent=num?num+" berita":"Belum ada";}

}
function setFocus(value,opts={}){if(!Object.hasOwn(map,value))return;selected=value;window.katarinaInstrument=value;window.katarinaMarketFocus=value;save(value);
for(const select of selectors)select.value=value;
for(const urlLink of document.querySelectorAll('a[href^="/analisa.html"],a[href^="/research.html"]')){
 try{const destination=new URL(urlLink.href,location.origin);
     if(destination.origin!==location.origin)continue;
     destination.searchParams.set('symbol',value);
     urlLink.href=destination.pathname+destination.search+destination.hash;
 }catch(e){}
}
if(opts.history!==false && (location.pathname.endsWith('.html')||['/research','/analisa'].includes(location.pathname))){
  const destination=new URL(location.href);destination.searchParams.set('symbol',value);
  if(destination.search!==location.search)history.replaceState(history.state,'',destination.pathname+destination.search+destination.hash);
}
const allFilter=document.querySelector('.pulse-tags [data-filter="all"]');if(allFilter&&allFilter.getAttribute('aria-pressed')!=='true')allFilter.click();
window.dispatchEvent(new CustomEvent("katarina-select-symbol",{detail:{symbol:map[value].symbol,pair:value}}));
renderContext();
const link=$("#focus-research-link");if(link)link.href="/research.html?symbol="+encodeURIComponent(value);
const open=$("#research-open-analysis");if(open)open.href="/analisa.html?symbol="+encodeURIComponent(value);
window.dispatchEvent(new CustomEvent("katarina-instrument",{detail:{symbol:value}}));
}

// Searchable pair list in both Research and Analisa; native optgroup select remains
// available as the accessible fallback, and the chart dropdown shares its value.
const searchScopes=[...document.querySelectorAll('[data-instrument-lookup]')];
const groupTitle={major:'Forex Major',minor:'Forex Minor / Cross',metal:'Metals',index:'Indices',crypto:'Crypto'};
for(const scope of searchScopes){
const toggle=scope.querySelector('[data-pair-search-toggle]');
const panel=scope.querySelector('[data-pair-search-panel]');
const input=scope.querySelector('[data-pair-search-query]');
const results=scope.querySelector('[data-pair-search-results]');
const closer=scope.querySelector('[data-pair-search-close]');
if(!toggle||!panel||!input||!results||!closer)continue;
let matches=[],activeIndex=0;
function renderMatches(){
  const needle=input.value.toUpperCase().replace(/[^A-Z0-9]/g,'');
  const related=needle==='GOLD'?'XAUUSD':needle==='SILVER'?'XAGUSD':needle==='DOW'?'US30':needle==='BITCOIN'?'BTCUSD':needle==='SP500'?'US500':needle;
  matches=defs.filter(([id,,name])=>!related||id.includes(related)||name.toUpperCase().replace(/[^A-Z0-9]/g,'').includes(related)).slice(0,34);
  activeIndex=0;results.replaceChildren();
  if(matches.length===0){results.append(el('p','pair-no-result','Pair tidak ditemukan. Periksa ejaan atau gunakan dropdown.'));input.removeAttribute('aria-activedescendant');return}
  let last='';
  matches.forEach(([id,,name,type],i)=>{
   if(type!==last){results.append(el('div','pair-search-group',groupTitle[type]||type));last=type}
   const button=el('button','pair-search-choice');button.type='button';button.setAttribute('role','option');button.dataset.pair=id;button.id=results.id+'-opt-'+i;
   button.setAttribute('aria-selected',String(i===activeIndex));
   const namePart=el('strong','',id);const labelPart=el('span','',name.replace(id,'').replace(/^[\s·]+/,'').trim()||groupTitle[type]||'');
   button.append(namePart,labelPart);
   button.addEventListener('click',()=>choose(id));results.append(button);
  });
  updateActive();
}
function updateActive(){
  const buttons=[...results.querySelectorAll('[role=option]')];
  buttons.forEach((b,i)=>b.setAttribute('aria-selected',String(i===activeIndex)));
  const active=buttons[activeIndex];
  if(active){input.setAttribute('aria-activedescendant',active.id);active.scrollIntoView({block:'nearest'});}
}
function open(){panel.hidden=false;toggle.setAttribute('aria-expanded','true');input.setAttribute('aria-expanded','true');input.value='';renderMatches();input.focus();}
function close(){panel.hidden=true;toggle.setAttribute('aria-expanded','false');input.setAttribute('aria-expanded','false');input.removeAttribute('aria-activedescendant');}
function choose(value){setFocus(value);close();toggle.focus();}
toggle.addEventListener('click',()=>panel.hidden?open():close());
closer.addEventListener('click',()=>{close();toggle.focus()});
input.addEventListener('input',renderMatches);
input.addEventListener('keydown',e=>{
  if(e.key==='Escape'){e.preventDefault();close();toggle.focus();return}
  if(!matches.length)return;
  if(e.key==='ArrowDown'){e.preventDefault();activeIndex=(activeIndex+1)%matches.length;updateActive()}
  else if(e.key==='ArrowUp'){e.preventDefault();activeIndex=(activeIndex+matches.length-1)%matches.length;updateActive()}
  else if(e.key==='Enter'){e.preventDefault();choose(matches[activeIndex][0])}
});
document.addEventListener('pointerdown',e=>{if(!panel.hidden&&!scope.contains(e.target))close()});
}
window.addEventListener('popstate',()=>{
  const pair=new URLSearchParams(location.search).get('symbol');
  if(pair&&Object.hasOwn(map,pair))setFocus(pair,{history:false});
});

for(const select of selectors){select.replaceChildren();for(const [group,label] of [["major","Forex · Major"],["minor","Forex · Minor / Cross"],["metal","Metals"],["index","Indices"],["crypto","Crypto"]]){const optgroup=el("optgroup");optgroup.label=label;for(const [id,,name,type] of defs.filter(x=>x[3]===group)){const opt=el("option",null,name);opt.value=id;optgroup.append(opt)}select.append(optgroup)}
select.addEventListener("change",()=>setFocus(select.value));}
const urlParam=new URLSearchParams(location.search).get("symbol");
const initial=Object.hasOwn(map,urlParam)?urlParam:read();
window.katarinaInstrument=initial;
window.katarinaMarketFocus=initial;
setFocus(initial);
document.querySelectorAll("[data-tv-symbol]").forEach(button=>{
button.addEventListener("click",()=>{const found=defs.find(x=>x[1]===button.dataset.tvSymbol);if(found&&found[0]!==selected)setFocus(found[0],{fromButton:true})});
});
fetch("/instrument-context.json",{cache:"no-store"}).then(r=>{if(!r.ok)throw Error("No instrument context");return r.json()}).then(j=>{if(j.schema===1&&Array.isArray(j.instruments))items=j.instruments;renderContext()}).catch(renderContext);
fetch("/calendar-brief.json",{cache:"no-store"}).then(r=>r.ok?r.json():null).then(j=>{if(j&&Array.isArray(j.news))publishedNews=j.news;renderContext()}).catch(()=>{});
window.addEventListener("katarina-language",renderContext);
})();
