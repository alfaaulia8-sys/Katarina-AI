/* KATARINA Dashboard Hot News — 15-minute OPEN PAGE poll, source-linked RSS titles.
 * Feed updated by public GitHub Actions on best-effort */ 
(()=>{"use strict";
const root=document.getElementById("kt-hotnews");if(!root)return;
const list=document.getElementById("kt-hotnews-list"),featured=document.getElementById("kt-hotnews-featured");
const status=document.getElementById("kt-hotnews-status"),stamp=document.getElementById("kt-hotnews-checked");
const manual=document.getElementById("kt-hotnews-refresh");
const REMOTE="https://raw.githubusercontent.com/alfaauliau-katarinaAI/Katarina-AI/main/website/hot-news.json";
const ALLOWED=new Set(["www.cnbc.com","www.federalreserve.gov","www.ecb.europa.eu","www.bankofengland.co.uk","www.bls.gov","www.bea.gov"]);
const INTERVAL=15*60*1000;let lastPoll=0,current="",busy=false,lastValid=[];
const span=(cls,text)=>{const x=document.createElement("span");if(cls)x.className=cls;x.textContent=text;return x};
const p=(cls,text)=>{const x=document.createElement("p");if(cls)x.className=cls;x.textContent=text;return x};
function timeLabel(iso){try{return new Date(iso).toLocaleString("id-ID",{timeZone:"Asia/Jakarta",day:"2-digit",month:"short",hour:"2-digit",minute:"2-digit"})+" WIB"}catch(e){return "waktu tidak tersedia"}}
function approved(item){
 if(!item||typeof item.title!=="string"||item.title.length<20||item.title.length>230||typeof item.url!=="string")return false;
 let url;try{url=new URL(item.url)}catch(e){return false}
 if(url.protocol!=="https:"||!ALLOWED.has(url.hostname))return false;
 const dt=Date.parse(item.publishedAt);if(!Number.isFinite(dt)||dt>Date.now()+30*60*1000||dt<Date.now()-72*3600*1000)return false;
 return typeof item.source==="string"&&item.source.length>=3;
}
function article(item,lead=false){
 const a=document.createElement("a");a.className=lead?"kt-hotnews-lead":"kt-hotnews-item";
 a.href=item.url;a.target="_blank";a.rel="noopener noreferrer";
 const meta=document.createElement("div");meta.className="kt-hotnews-meta";
 meta.append(span("kt-hotnews-tag",item.category||"Berita Pasar"),span("",item.source),span("",timeLabel(item.publishedAt)));
 const heading=document.createElement(lead?"h3":"h4");heading.textContent=item.title;heading.lang=item.language==="en"?"en":"id";
 a.append(meta,heading);
 if(lead)a.append(p("kt-hotnews-context","Judul asli dari penerbit. Buka sumber untuk membaca konteks lengkap; KATARINA tidak menambahkan klaim yang belum diperiksa."));
 else a.append(span("kt-hotnews-open","Baca sumber ↗"));
 return a;
}
function render(items){
 const signature=items.map(x=>x.url).join("|");
 const changed=!!current&&signature!==current;current=signature;lastValid=items;
 featured.replaceChildren();list.replaceChildren();
 if(!items.length){
  featured.append(p("kt-hotnews-no-data","Belum ada headline pasar terbaru yang memenuhi syarat sumber dan waktu. Berita lama tidak ditampilkan sebagai hot news."));
  status.textContent="Belum ada kabar baru terverifikasi sumber";return;
 }
 featured.append(article(items[0],true));
 for(const item of items.slice(1,7))list.append(article(item));
 status.textContent=changed?"Ada headline baru dari sumber":"Menampilkan "+items.length+" headline terbaru yang tersaring";
 root.dataset.latest=items[0].publishedAt;
}
async function loadOne(url){
 const ac=new AbortController();const timeout=setTimeout(()=>ac.abort(),12000);
 try{const response=await fetch(url,{cache:"no-store",signal:ac.signal});if(!response.ok)throw Error("HTTP "+response.status);
 const data=await response.json();if(data?.schema!==1||!Array.isArray(data.items))throw Error("Format tidak sesuai");
 return data.items.filter(approved).sort((a,b)=>Date.parse(b.publishedAt)-Date.parse(a.publishedAt)).slice(0,12)
 }finally{clearTimeout(timeout)}
}
async function check(){
 if(busy)return;busy=true;lastPoll=Date.now();
 manual.disabled=true;status.textContent="Memeriksa sumber berita…";
 let items=null;
 try{items=await loadOne(REMOTE+"?v="+lastPoll)}
 catch(e){try{items=await loadOne("/hot-news.json?v="+lastPoll)}catch(e2){}}
 if(items!==null)render(items);
 else {status.textContent=lastValid.length?"Sumber pembaruan belum tersedia; mempertahankan headline sebelumnya":"Sumber belum tersedia, tidak menampilkan berita tanpa bukti"}
 stamp.textContent="Diperiksa: "+new Date().toLocaleTimeString("id-ID",{timeZone:"Asia/Jakarta",hour:"2-digit",minute:"2-digit"})+" WIB · cek ulang setiap 15 menit selama halaman terbuka";
 manual.disabled=false;busy=false;
}
manual?.addEventListener("click",check);
document.addEventListener("visibilitychange",()=>{if(!document.hidden&&Date.now()-lastPoll>=INTERVAL)check()});
setInterval(()=>{if(!document.hidden)check()},INTERVAL);
check();
})();