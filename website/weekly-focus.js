/* KATARINA AI / Ringkasan riset mingguan berbasis data publik.
 * Analisis deskriptif dan skenario bersyarat; BUKAN model live atau sinyal order.
 */
(()=>{"use strict";
const $=id=>document.getElementById(id);
if(!$("kt-week-heading"))return;
const catalog={XAUUSD:"xau",XAGUSD:"silver",US30:"us30",US500:"sp500",NASDAQ:"nasdaq",BTCUSD:"bitcoin"};
let market=null,calendar=null,context=null;
const pair=()=>document.querySelector("[data-instrument-select]")?.value||new URLSearchParams(location.search).get("symbol")||"XAUUSD";
const el=(t,cls,txt)=>{const x=document.createElement(t);if(cls)x.className=cls;if(txt!=null)x.textContent=txt;return x};
const set=(id,value)=>{if($(id))$(id).textContent=value};
const date=d=>new Date(d).toLocaleDateString("id-ID",{day:"numeric",month:"short",year:"numeric",timeZone:"UTC"});
function link(parent,title,href){try{const url=new URL(href);if(url.protocol!=="https:")return;const a=el("a",null,title+" ↗");a.href=url.href;a.target="_blank";a.rel="noopener noreferrer";parent.append(a)}catch(e){}}
function render(){
 const symbol=pair(),key=catalog[symbol]||symbol.toLowerCase(),pack=market?.series?.[key],bars=pack?.bars||[];
 const ctx=context?.instruments?.find(x=>x.id===symbol);
 const events=(calendar?.events||[]).filter(x=>(x.instrumentImpact?.[symbol]||0)>=2).filter(x=>x.dateWIB&&x.title&&x.source);
 const explicitEvents=events.filter(x=>(x.instrumentImpact?.[symbol]||0)>=3);
 const relevant=(explicitEvents.length?explicitEvents:events).slice().sort((a,b)=>a.dateWIB.localeCompare(b.dateWIB));
 const base=bars.length>=20?bars.at(-1)[4]:null;
 const prev=bars.length>=6?bars.at(-6)[4]:null;
 const valid=base&&prev&&Number.isFinite(base)&&Number.isFinite(prev)&&base>0&&prev>0;
 let pct=valid?(base/prev-1)*100:null,trend="Data belum cukup";
 if(valid){trend=pct>0.4?"Menguat dalam 5 sesi":pct<-.4?"Melemah dalam 5 sesi":"Bergerak relatif terbatas"}
 const mean20=bars.length>=20?bars.slice(-20).reduce((sum,b)=>sum+b[4],0)/20:null;
 const pos=mean20&&base?(base>=mean20?"di atas":"di bawah")+" rata-rata 20 penutupan":"tidak tersedia";
 set("kt-week-structure",trend);
 set("kt-week-price",valid?"Perubahan 5 bar: "+(pct>=0?"+":"")+pct.toFixed(2)+"%. Penutupan terakhir "+pos+".":"Snapshot OHLC belum cukup untuk membaca perubahan 5 sesi.");
 set("kt-week-period",calendar?.weekStart&&calendar?.weekEnd?date(calendar.weekStart)+" – "+date(calendar.weekEnd):"Pekan terkini berdasarkan kalender sumber");
 const impact=relevant.filter(x=>x.actual==null).length;
 set("kt-week-event",relevant.length?relevant.length+" agenda terkait":"Belum tercakup");
 set("kt-week-timing",relevant.length?relevant.slice(0,2).map(x=>x.dateWIB.slice(5).replace("-","/")+" · "+x.title).join("  |  "):"Belum ada agenda resmi yang dapat dikaitkan dengan pair ini.");
 set("kt-week-theme",ctx?.headline||"Konteks sumber belum tersedia");
 set("kt-week-drivers",ctx?.monitor?"Pantau: "+ctx.monitor:"Periksa sumber bank sentral dan data dua mata uang dalam pasangan.");
 const first=relevant[0],one=ctx?.drivers?.[0],two=ctx?.drivers?.[1];
 const weekly=first?"Prioritaskan "+first.title+" ("+date(first.dateWIB)+", "+first.timeWIB+" WIB). "+(one?one+". ":"")+"Bandingkan hasil aktual dengan konsensus dan respons candle setelah publikasi.":"Amati reaksi harga terhadap "+(one||"perubahan sentimen pasar")+". Kalender resmi minggu ini belum mencakup rilis spesifik pair secara memadai.";
 const change=valid?"Harga historis terakhir "+(pct>=0?"menguat":"melemah")+" "+Math.abs(pct).toFixed(2)+"% terhadap lima bar sebelumnya. ":"";
 set("kt-week-plan",change+weekly);
 const scenario=first?(first.ifAbove||first.conditional||"Hasil yang melebihi konsensus dapat mengubah ekspektasi suku bunga dan risiko."):"Jika muncul katalis resmi baru, nilai selisih aktual–konsensus dan respons pasar sebelum menarik kesimpulan.";
 const risk=(two?two+". ":"")+"Skenario alternatif: "+scenario+" Ini bersifat kemungkinan, bukan kepastian arah "+symbol+". Belum ada level invalidasi teknikal KATARINA yang telah disetujui. "+(explicitEvents.length===0&&events.length?"Penting: kalender yang tersedia sebagian besar AS dan mungkin berpengaruh hanya secara tidak langsung terhadap pasangan cross ini.":"");
 set("kt-week-risk",risk);
 const sourceRoot=$("kt-week-sources");if(sourceRoot){sourceRoot.replaceChildren();sourceRoot.append(el("span",null,"Periksa sumber:"));
 if(first)link(sourceRoot,"Jadwal "+first.region,first.source);
 if(pack?.sourceUrl)link(sourceRoot,"Sumber harga",pack.sourceUrl);
 const method=el("a",null,"Metodologi ↗");method.href="/methodology.html";sourceRoot.append(method);
 }
}
Promise.all([
 fetch("/market-ohlc.json",{cache:"no-store"}).then(r=>r.ok?r.json():null).catch(()=>null),
 fetch("/calendar-brief.json",{cache:"no-store"}).then(r=>r.ok?r.json():null).catch(()=>null),
 fetch("/instrument-context.json",{cache:"no-store"}).then(r=>r.ok?r.json():null).catch(()=>null)
]).then(([m,c,i])=>{market=m?.schema===1?m:null;calendar=c?.schema===1?c:null;context=i?.schema===1?i:null;render()});
window.addEventListener("katarina-instrument",render);
window.addEventListener("katarina-language",render);
})();
