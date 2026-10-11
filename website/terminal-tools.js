
/* KATARINA Analysis interaction tools: sourced OHLC cards, chart focus, share.
 * This does not access MT5, place trades, estimate win rate, or invent prices.
 */
(()=>{"use strict";
const section=document.getElementById("kt-analysis-terminal");
if(!section)return;
const btn=document.getElementById("kt-chart-focus"),share=document.getElementById("kt-chart-share");
let data=null;const keys={XAUUSD:"xau",XAGUSD:"silver",BTCUSD:"bitcoin",US30:"us30",US500:"sp500",NASDAQ:"nasdaq"};
const el=id=>document.getElementById(id);
const current=()=>{const item=document.querySelector("[data-instrument-select]");return item?.value||new URLSearchParams(location.search).get("symbol")||"XAUUSD"};
const readKey=s=>keys[s]||s.toLowerCase();
const show=(id,value)=>{const node=el(id);if(node)node.textContent=value};
function fmt(number,pair){const digits=pair.endsWith("JPY")?3:/^[A-Z]{6}$/.test(pair)&&!(pair.endsWith("USD")&&["XAU","XAG","BTC"].some(x=>pair.startsWith(x)))?5:2;return Number(number).toLocaleString("id-ID",{minimumFractionDigits:digits,maximumFractionDigits:digits})}
function render(){
const sym=current(),series=data?.series?.[readKey(sym)],bar=series?.bars?.at(-1);
const values=bar?.slice(1);
if(!Array.isArray(values)||values.length<4||!values.every(x=>typeof x==="number"&&Number.isFinite(x))){["kt-last-open","kt-last-high","kt-last-low","kt-last-close"].forEach(x=>show(x,"—"));show("kt-ohlc-source","Belum ada snapshot OHLC bersumber untuk "+sym);return}
const [o,h,l,c]=values;
show("kt-last-open",fmt(o,sym));show("kt-last-high",fmt(h,sym));show("kt-last-low",fmt(l,sym));show("kt-last-close",fmt(c,sym));
const asof=series.asOf?new Date(series.asOf):null;
const stamp=asof&&Number.isFinite(asof.getTime())?asof.toLocaleDateString("id-ID",{day:"numeric",month:"short",year:"numeric",timeZone:"UTC"}):"tanggal tidak tersedia";
show("kt-ohlc-source",sym+" · "+stamp+" · "+(series.source||data.provider||"Data harga publik")+" · historis, bukan quote broker MT5");
}
function focus(active){document.body.classList.toggle("kt-focus-active",active);if(btn){btn.setAttribute("aria-pressed",String(active));btn.textContent=active?"⊟  Kembali ke halaman":"⛶  Fokus grafik";}const top=el("kt-analysis-terminal");if(active)top?.scrollIntoView({block:"start",behavior:"smooth"});}
btn?.addEventListener("click",()=>focus(!document.body.classList.contains("kt-focus-active")));
share?.addEventListener("click",async()=>{
const u=new URL(location.href);u.searchParams.set("symbol",current());u.hash="kt-analysis-terminal";
try{await navigator.clipboard.writeText(u.toString());share.textContent="✓ Tautan tersalin";setTimeout(()=>{share.textContent="↗  Salin tautan"},1800)}
catch(e){share.textContent="Salin URL dari browser";}
});
window.addEventListener("katarina-instrument",render);
window.addEventListener("katarina-select-symbol",render);
document.querySelectorAll("[data-instrument-select]").forEach(x=>x.addEventListener("change",()=>requestAnimationFrame(render)));
document.addEventListener("keydown",e=>{
const tag=e.target?.tagName;if((e.key==="/"||((e.ctrlKey||e.metaKey)&&e.key==="k"))&&!["INPUT","TEXTAREA","SELECT"].includes(tag)){const search=document.querySelector("[data-pair-search-toggle]");if(search){e.preventDefault();search.click()}}
if(e.key==="Escape"&&document.body.classList.contains("kt-focus-active"))focus(false);
});
fetch("/market-ohlc.json",{cache:"no-store"}).then(r=>{if(!r.ok)throw Error("No market snapshot");return r.json()}).then(x=>{if(x.schema!==1||!x.series)throw Error("Invalid market data");data=x;render()}).catch(()=>{show("kt-ohlc-source","Sumber data OHLC belum dapat dimuat; tidak ada angka pengganti.")});
})();
