/* KATARINA AI — sintesis mingguan bersumber, bukan sinyal transaksi.
 * Harga historis + kalender terverifikasi + pemetaan faktor makro/mikro.
 * Tidak menyimpulkan aksi institusi, probabilitas menang, maupun entry.
 */
(()=>{"use strict";
const $=id=>document.getElementById(id);if(!$("kt-week-heading"))return;
const chartKeys={XAUUSD:"xau",XAGUSD:"silver",US30:"us30",US500:"sp500",NASDAQ:"nasdaq",BTCUSD:"bitcoin"};
let market=null,calendar=null,context=null,news=null;
const pair=()=>document.querySelector("[data-instrument-select]")?.value||new URLSearchParams(location.search).get("symbol")||"XAUUSD";
const txt=(id,v)=>{const n=$(id);if(n)n.textContent=v};
const el=(tag,cls,value)=>{const n=document.createElement(tag);if(cls)n.className=cls;if(value!==undefined)n.textContent=value;return n};
const date=d=>{try{return new Date(d+"T12:00:00Z").toLocaleDateString("id-ID",{day:"numeric",month:"short",year:"numeric",timeZone:"UTC"})}catch(e){return d}};
const compact=n=>Number(n).toLocaleString("id-ID",{maximumFractionDigits:5});
function addLink(parent,label,href){try{const u=new URL(href);if(u.protocol!=="https:")return;const a=el("a",null,label+" ↗");a.href=u.href;a.target="_blank";a.rel="noopener noreferrer";parent.append(a)}catch(e){}}
function sourceBars(symbol){const key=chartKeys[symbol]||symbol.toLowerCase();const series=market?.series?.[key];
const bars=Array.isArray(series?.bars)?series.bars.filter(b=>Array.isArray(b)&&b.length>=5&&b.slice(1,5).every(n=>typeof n==="number"&&Number.isFinite(n)&&n>0)&&b[2]>=Math.max(b[1],b[4])&&b[3]<=Math.min(b[1],b[4])):[];
return {bars,series};}
function priceSummary(bars){if(bars.length<20)return null;
const last=bars.at(-1)[4],previous=bars.at(-6)[4],change=(last/previous-1)*100,
sample=bars.slice(-20),mean=sample.reduce((sum,b)=>sum+b[4],0)/sample.length,
highest=Math.max(...sample.map(b=>b[2])),lowest=Math.min(...sample.map(b=>b[3])),
width=Math.max(.00000001,highest-lowest),position=(last-lowest)/width;
const tendency=change>.4?"naik":change<-.4?"turun":"relatif mendatar";
const balance=last>=mean?"di atas":"di bawah";
return {last,change,mean,highest,lowest,position,tendency,balance};
}
function render(){
 const symbol=pair(),{series,bars}=sourceBars(symbol),prices=priceSummary(bars),item=context?.instruments?.find(x=>x.id===symbol);
 const related=(calendar?.events||[]).filter(e=>e?.source&&e?.dateWIB&&e?.title&&(e.instrumentImpact?.[symbol]||0)>=2).sort((a,b)=>a.dateWIB.localeCompare(b.dateWIB));
 const strong=related.filter(e=>(e.instrumentImpact?.[symbol]||0)>=3);
 const important=(strong.length?strong:related);
 const unreleased=important.filter(e=>e.actual===null||e.actual===undefined);
 const catalyst=unreleased[0]||important[0];
 const headlines=(news?.news||[]).filter(n=>Array.isArray(n.symbols)&&n.symbols.includes(symbol)).slice(0,2);
 const isCross=!symbol.includes("USD")&&symbol.length===6&&symbol!=="NASDAQ";
 txt("kt-week-period",calendar?.weekStart&&calendar?.weekEnd?date(calendar.weekStart)+" – "+date(calendar.weekEnd):"Periode kalender belum tersedia");
 if(prices){
  txt("kt-week-structure",prices.tendency==="naik"?"Tekanan naik (historis)":prices.tendency==="turun"?"Tekanan turun (historis)":"Konsolidasi (historis)");
  txt("kt-week-price","Lima penutupan: "+(prices.change>=0?"+":"")+prices.change.toFixed(2)+"%; terakhir "+prices.balance+" rerata 20 sesi. Rentang 20 sesi "+compact(prices.lowest)+"–"+compact(prices.highest)+".");
 }else{txt("kt-week-structure","Data belum cukup");txt("kt-week-price","Perlu minimal 20 bar OHLC valid untuk membaca struktur historis.")}
 txt("kt-week-event",related.length?related.length+" rilis terpetakan":"Belum ada rilis terpetakan");
 txt("kt-week-timing",catalyst?date(catalyst.dateWIB)+" · "+catalyst.timeWIB+" WIB · "+catalyst.title+(unreleased.length?" (menunggu aktual)":""):"Belum ada agenda terverifikasi yang cukup relevan dengan instrumen ini.");
 txt("kt-week-theme",item?.headline||"Konteks instrumen belum tersedia");
 txt("kt-week-drivers",item?.monitor?"Pantau: "+item.monitor:"Faktor fundamental spesifik pair masih perlu dilengkapi dari sumber resmi.");
 const factors=(item?.drivers||[]).filter(x=>typeof x==="string"&&x.trim()).slice(0,3);
 const priceReading=prices?("Penutupan historis "+(prices.change>=0?"bertambah ":"berkurang ")+Math.abs(prices.change).toFixed(2)+"% dalam lima bar. Harga "+prices.balance+" rata-rata 20 sesi. "):"";
 const transmission=catalyst?("Perhatikan "+catalyst.title+" pada "+date(catalyst.dateWIB)+". Bandingkan angka aktual dan prediksi yang bersumber; periksa perubahan yield, kurs relatif, dan respons candle berikutnya. "):"Tidak ada rilis utama yang cukup terverifikasi untuk menyimpulkan pemicu baru minggu ini. ";
 const factorText=factors.length?("Faktor makro–mikro: "+factors.join("; ")+". "):"Data makro–mikro instrumen masih terbatas. ";
 const marketText=prices?(prices.position>=.75?"Penutupan mendekati seperempat atas rentang 20 sesi; waspadai respons pada volatilitas baru. ":prices.position<=.25?"Penutupan mendekati seperempat bawah rentang 20 sesi; amati apakah tekanan bertahan. ":"Posisi harga di bagian tengah rentang 20 sesi; belum menunjukkan dominasi ujung rentang. "):"";
 const story=headlines.length?("Berita yang dapat ditelusuri: "+headlines.map(n=>n.title).join("; ")+". "):"Belum ada berita tambahan yang lolos pemetaan pair; jangan mengisi dengan dugaan. ";
 txt("kt-week-plan",priceReading+transmission+factorText+marketText+story);
 const upper=catalyst?.ifAbove||"Jika hasil aktual melampaui konsensus, arah dan besarnya respons tetap bergantung pada komponen data serta posisi pasar.";
 const lower=catalyst?.ifBelow||"Jika hasil aktual di bawah konsensus, reaksi pasar dapat berbeda jika perubahan itu menandakan perlambatan.";
 const relative=isCross?"Perhatian: kalender yang tersedia lebih banyak berfokus pada AS. Pada cross tanpa USD, hubungan ini cenderung tidak langsung; perlu sumber data dari kedua negara mata uang. ":"";
 const caveat="Tidak ada keputusan buy/sell, level invalidasi atau probabilitas hasil KATARINA yang dapat dipublikasikan tanpa audit dan izin. ";
 txt("kt-week-risk","Jika data melebihi konsensus: "+upper+" Jika lebih rendah: "+lower+" "+relative+caveat);
 const links=$("kt-week-sources");
 if(links){links.replaceChildren();links.append(el("span",null,"Sumber yang dapat diperiksa:"));
   if(catalyst)addLink(links,"Jadwal resmi "+(catalyst.region||""),catalyst.source);
   if(series?.sourceUrl)addLink(links,"Harga historis",series.sourceUrl);
   if(headlines[0]?.url)addLink(links,"Berita relevan",headlines[0].url);
   const method=el("a",null,"Metodologi");method.href="/methodology.html";links.append(method);
 }
}
Promise.all([
 fetch("/market-ohlc.json",{cache:"no-store"}).then(r=>r.ok?r.json():null).catch(()=>null),
 fetch("/calendar-brief.json",{cache:"no-store"}).then(r=>r.ok?r.json():null).catch(()=>null),
 fetch("/instrument-context.json",{cache:"no-store"}).then(r=>r.ok?r.json():null).catch(()=>null)
]).then(([m,c,i])=>{market=m?.schema===1?m:null;calendar=c?.schema===1?c:null;context=i?.schema===1?i:null;news=calendar;render()});
window.addEventListener("katarina-instrument",render);
window.addEventListener("katarina-language",render);
})();