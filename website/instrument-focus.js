/* KATARINA instrument intelligence control — changes chart, macro calendar, news and risk context together */
(function(){
"use strict";
const defs=[
["XAUUSD","OANDA:XAUUSD","XAUUSD · Gold"],["US30","INDEX:DJI","US30 · Dow Jones (^DJI proxy)"],
["NASDAQ","OANDA:NAS100USD","NASDAQ · Composite proxy"],["US500","INDEX:SPX","US500 · S&P 500 proxy"],
["EURUSD","OANDA:EURUSD","EURUSD"],["GBPUSD","OANDA:GBPUSD","GBPUSD"],
["BTCUSD","BITSTAMP:BTCUSD","BTCUSD"],["XAGUSD","OANDA:XAGUSD","XAGUSD"]];
const map=Object.fromEntries(defs.map(x=>[x[0],{symbol:x[1],label:x[2]}]));
const selectors=[...document.querySelectorAll("[data-instrument-select]")];if(!selectors.length)return;
const $=s=>document.querySelector(s);
let items=[],selected="XAUUSD";
const el=(tag,className,value)=>{const n=document.createElement(tag);if(className)n.className=className;if(value!==undefined)n.textContent=String(value);return n};
function save(v){try{localStorage.setItem("katarina_public_instrument",v)}catch(e){}}
function read(){try{const v=localStorage.getItem("katarina_public_instrument");return Object.hasOwn(map,v)?v:"XAUUSD"}catch(e){return "XAUUSD"}}
function renderContext(){const node=$("#instrument-context");if(!node)return;node.replaceChildren();const x=items.find(v=>v.id===selected);if(!x){node.append(el("p","muted","Memuat ringkasan instrumen..."));return}node.append(el("h3","focus-headline",x.headline));
const info=el("p","focus-monitor","Faktor utama untuk diamati: "+x.monitor);node.append(info);
const list=el("ul","focus-driver-list");for(const reason of x.drivers||[]){list.append(el("li",null,reason))}node.append(list);
const disclaimer=el("p","focus-disclosure","Faktor penggerak bersifat analisis makro/mikro bersyarat, bukan arah transaksi atau hasil pengujian KATARINA.");node.append(disclaimer);
const headline=$("#focus-active-symbol");if(headline)headline.textContent=x.label;
}
function setFocus(value,opts={}){if(!Object.hasOwn(map,value))return;selected=value;window.katarinaInstrument=value;window.katarinaMarketFocus=value;save(value);
for(const select of selectors)select.value=value;
if(!opts.fromButton){const control=[...document.querySelectorAll("[data-tv-symbol]")].find(b=>b.dataset.tvSymbol===map[value].symbol);if(control)control.click();}
renderContext();
const link=$("#focus-research-link");if(link)link.href="/research.html?symbol="+encodeURIComponent(value);
const open=$("#research-open-analysis");if(open)open.href="/analisa.html?symbol="+encodeURIComponent(value);
window.dispatchEvent(new CustomEvent("katarina-instrument",{detail:{symbol:value}}));
}
for(const select of selectors){select.replaceChildren();for(const [id,,label] of defs){const opt=el("option",null,label);opt.value=id;select.append(opt)}
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
window.addEventListener("katarina-language",renderContext);
})();
