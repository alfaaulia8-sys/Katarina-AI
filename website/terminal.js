
/* KATARINA TERMINAL / UI only / reads approved public market snapshots.
 * No fabricated quotes, no signals, no live order exposure.
 */
(()=>{"use strict";
const root=document.querySelector("[data-kt-dashboard]");if(!root)return;
const by=id=>document.getElementById(id);
const models=[
 {symbol:"XAUUSD",key:"xau",hint:"Gold / USD"},
 {symbol:"EURUSD",key:"eurusd",hint:"Euro / Dollar"},
 {symbol:"USDJPY",key:"usdjpy",hint:"USD / Japanese Yen"},
 {symbol:"US30",key:"us30",hint:"Dow Jones Index proxy"},
 {symbol:"BTCUSD",key:"bitcoin",hint:"Bitcoin / USD"},
 {symbol:"XAGUSD",key:"silver",hint:"Silver / USD"}
];
const workflow=[
 {title:"AKUISISI DATA",info:"Harga historis, rilis ekonomi, data pasar dan sumber yang memiliki waktu serta atribusi. Ini tahap rancangan sistem, bukan tanda sumber data live terkoneksi."},
 {title:"CEK KUALITAS",info:"Periksa kronologi OHLC, sumber, duplikasi, nilai yang tidak masuk akal, zona waktu, dan perubahan jadwal rilis."},
 {title:"KONTEKS PASAR",info:"Amati struktur makro, hubungan mata uang dasar dan kuotasi, suku bunga relatif, likuiditas serta sentimen global."},
 {title:"REGIME & RISET",info:"Bandingkan konteks trending atau ranging dan dokumentasikan hipotesis; tanpa bukti cukup, tidak ada level teknikal yang diklaim terverifikasi."},
 {title:"KONTROL RISIKO",info:"Tahap penilaian spread, volatilitas, margin, ketentuan kontrak, batas pengujian dan skenario invalidasi sebelum sebuah metode dinilai layak."},
 {title:"UJI & EKSEKUSI",info:"Pisahkan backtest, demo, dan live. Diagram ini tidak menyatakan robot melakukan order saat halaman diakses atau sedang menghasilkan profit."},
 {title:"JURNAL & FEEDBACK",info:"Catat keterbatasan sumber, kualitas sampel, dan hasil yang disetujui untuk publikasi. Evaluasi kembali hipotesis tanpa mempublikasikan rahasia strategi."}
];
let market=null,selected="XAUUSD",hoverIndex=null;
const format=(n,symbol)=>Number(n).toLocaleString("id-ID",{minimumFractionDigits:["EURUSD","USDJPY"].includes(symbol)?(symbol==="USDJPY"?3:5):2,maximumFractionDigits:["EURUSD","USDJPY"].includes(symbol)?(symbol==="USDJPY"?3:5):2});
const pointValue=b=>b.length>=5?b[4]:b[1];
function active(){return models.find(m=>m.symbol===selected)||models[0]}
function bars(symbol=selected){return market?.series?.[models.find(x=>x.symbol===symbol)?.key||""]?.bars||[]}
function series(symbol=selected){return market?.series?.[models.find(x=>x.symbol===symbol)?.key||""]||null}
function isValidBar(b){return Array.isArray(b)&&b.length>=5&&b.every(n=>typeof n==="number"&&Number.isFinite(n))&&b[1]>0&&b[2]>=Math.max(b[1],b[4])&&b[3]<=Math.min(b[1],b[4])}
function sourceDate(){const p=series();if(!p?.asOf)return "Sumber belum tersedia";const date=new Date(p.asOf);return Number.isFinite(date.getTime())?"Snapshot: "+date.toLocaleDateString("id-ID",{day:"numeric",month:"short",year:"numeric",timeZone:"UTC"}):"Tanggal tidak tersedia"}
function chg(symbol=selected){const b=bars(symbol);if(b.length<2)return null;const price=pointValue(b.at(-1)),prev=pointValue(b.at(-2));return {price,prev,pct:(price/prev-1)*100}}
function text(node,value){if(node)node.textContent=value}
function renderBars(canvas,opts={}){
if(!canvas||!market)return;
const values=bars();const safe=values.slice(-(opts.compact?36:72)).filter(isValidBar);if(safe.length<8){const parent=canvas.parentElement;text(parent?.querySelector("[data-kt-no-data]"),"Data candlestick terverifikasi belum tersedia");return}
const width=Math.max(280,Math.round(canvas.getBoundingClientRect().width)),height=Math.max(120,Math.round(canvas.getBoundingClientRect().height)),ratio=Math.min(2,window.devicePixelRatio||1);
canvas.width=Math.round(width*ratio);canvas.height=Math.round(height*ratio);
const cx=canvas.getContext("2d");if(!cx)return;cx.setTransform(ratio,0,0,ratio,0,0);
const top=opts.compact?8:25,left=opts.compact?12:18,right=opts.compact?10:79,bottom=opts.compact?8:36;
const plotW=width-left-right,plotH=height-top-bottom;
const minimum=Math.min(...safe.map(b=>b[3])),maximum=Math.max(...safe.map(b=>b[2])),margin=Math.max((maximum-minimum)*.1,Math.abs(maximum)*.001);
const lo=minimum-margin,hi=maximum+margin,yy=v=>top+(hi-v)/(hi-lo)*plotH,xx=i=>left+(i+.5)*plotW/safe.length;
cx.clearRect(0,0,width,height);
if(!opts.compact){cx.font="11px system-ui";cx.textAlign="right";cx.textBaseline="middle";
for(let k=0;k<=4;k++){const y=top+k*plotH/4;cx.strokeStyle="#23456666";cx.lineWidth=1;cx.beginPath();cx.moveTo(left,y);cx.lineTo(width-right+4,y);cx.stroke();cx.fillStyle="#91b2c9";cx.fillText(format(hi-(hi-lo)*k/4,selected),width-5,y)}
for(let k=0;k<=4;k++){const idx=Math.min(safe.length-1,Math.round((safe.length-1)*k/4));const x=xx(idx);cx.strokeStyle="#2b496044";cx.beginPath();cx.moveTo(x,top);cx.lineTo(x,top+plotH);cx.stroke();cx.textAlign="center";cx.fillStyle="#95b7ca";cx.fillText(new Date(safe[idx][0]*1000).toLocaleDateString("id-ID",{day:"numeric",month:"short",timeZone:"UTC"}),x,height-14)}}
const barWidth=Math.max(1.6,Math.min(opts.compact?11:9,plotW/safe.length*.62));
for(let i=0;i<safe.length;i++){const [time,o,h,l,c]=safe[i],x=xx(i),up=c>=o;color(up);cx.beginPath();cx.moveTo(x,yy(h));cx.lineTo(x,yy(l));cx.lineWidth=opts.compact?1.3:1.1;cx.stroke();cx.fillRect(x-barWidth/2,yy(Math.max(o,c)),barWidth,Math.max(1.5,Math.abs(yy(o)-yy(c))))}
function color(up){cx.fillStyle=cx.strokeStyle=up?"#28e3bf":"#fb7b91"}
if(!opts.compact&&hoverIndex!==null){const i=Math.max(0,Math.min(safe.length-1,hoverIndex)),b=safe[i],x=xx(i),y=yy(b[4]);
cx.save();cx.setLineDash([3,4]);cx.strokeStyle="#95dfff";cx.beginPath();cx.moveTo(x,top);cx.lineTo(x,top+plotH);cx.moveTo(left,y);cx.lineTo(width-right,y);cx.stroke();cx.restore();
cx.fillStyle="#071b30";cx.fillRect(left,top,Math.min(plotW,390),22);cx.font="11px system-ui";cx.fillStyle="#ceebff";cx.textAlign="left";cx.fillText(new Date(b[0]*1000).toLocaleDateString("id-ID",{day:"2-digit",month:"short",timeZone:"UTC"})+"  O "+format(b[1],selected)+"  H "+format(b[2],selected)+"  L "+format(b[3],selected)+"  C "+format(b[4],selected),left+4,top+14);
cx.beginPath();cx.arc(x,y,3,0,Math.PI*2);cx.fillStyle="#adf8ff";cx.fill()}
}
function renderWatchlist(){const place=by("kt-watchlist");if(!place)return;place.replaceChildren();for(const m of models){
const vals=chg(m.symbol),button=document.createElement("button");button.type="button";button.className="kt-watch-item";button.setAttribute("aria-pressed",String(selected===m.symbol));button.dataset.symbol=m.symbol;
const title=document.createElement("div"),name=document.createElement("b"),desc=document.createElement("small");name.textContent=m.symbol;desc.textContent=m.hint;title.append(name,desc);
const price=document.createElement("div");price.className="kt-watch-price";price.textContent=vals?format(vals.price,m.symbol):"—";
const change=document.createElement("small");change.className=vals?(vals.pct>=0?"pos":"neg"):"";change.textContent=vals?(vals.pct>=0?"+":"")+vals.pct.toFixed(2)+"%":"Belum tersedia";price.append(change);
button.append(title,price);button.addEventListener("click",()=>switchSymbol(m.symbol));place.append(button);
}}
function switchSymbol(symbol){if(!models.some(m=>m.symbol===symbol))return;selected=symbol;hoverIndex=null;renderWatchlist();renderDashboard()}
function renderDashboard(){const c=chg();
text(by("kt-chart-title"),selected+" · Historical OHLC");
text(by("kt-chart-price"),c?format(c.price,selected):"—");
text(by("kt-chart-change"),c?(c.pct>=0?"+":"")+c.pct.toFixed(2)+"%":"Data belum ada");
const sign=by("kt-chart-change");if(sign)sign.style.color=c?(c.pct>=0?"#2ce0b6":"#fa768c"):"#9abbd1";
text(by("kt-chart-date"),sourceDate());text(by("kt-preview-symbol"),selected+" / 1D");text(by("kt-preview-price"),c?format(c.price,selected):"—");
const link=by("kt-market-go");if(link)link.href="/analisa.html?symbol="+encodeURIComponent(selected);
renderBars(by("kt-dashboard-canvas"));renderBars(by("kt-hero-canvas"),{compact:true});}
function bindPointer(){const canvas=by("kt-dashboard-canvas");if(!canvas)return;
canvas.addEventListener("pointermove",e=>{const count=Math.min(bars().length,72),bounds=canvas.getBoundingClientRect(),plotW=bounds.width-97;if(count<8)return;hoverIndex=Math.max(0,Math.min(count-1,Math.floor((e.clientX-bounds.left-18)/plotW*count)));renderBars(canvas)},{passive:true});
canvas.addEventListener("pointerleave",()=>{hoverIndex=null;renderBars(canvas)},{passive:true});}
function workflowUI(){const nodes=[...document.querySelectorAll(".kt-workflow .workflow-node")],panel=by("kt-workflow-info");
if(!nodes.length||!panel)return;nodes.forEach((node,i)=>{node.setAttribute("role","button");node.setAttribute("tabindex","0");node.setAttribute("aria-label","Lihat tahap "+(i+1)+": "+workflow[i].title);node.setAttribute("aria-pressed",String(i===0));
const click=()=>{nodes.forEach((x,j)=>x.setAttribute("aria-pressed",String(i===j)));text(by("kt-workflow-index"),String(i+1).padStart(2,"0"));text(by("kt-workflow-title"),workflow[i].title);text(by("kt-workflow-desc"),workflow[i].info)};
node.addEventListener("click",click);node.addEventListener("keydown",e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();click()}})});
text(by("kt-workflow-index"),"01");text(by("kt-workflow-title"),workflow[0].title);text(by("kt-workflow-desc"),workflow[0].info);}
function init(){workflowUI();bindPointer();fetch("/market-ohlc.json",{cache:"no-store"})
.then(x=>{if(!x.ok)throw Error("market snapshot missing");return x.json()})
.then(x=>{if(x.schema!==1||!x.series||!Array.isArray(x.series.xau?.bars))throw Error("invalid snapshot");market=x;
let latest=0;let count=0;for(const [key,p] of Object.entries(x.series)){if(Array.isArray(p.bars)&&p.bars.length>=15){count++;const date=Date.parse(p.asOf||"");if(Number.isFinite(date))latest=Math.max(latest,date)}}
text(by("kt-stat-assets"),count+" instrumen");text(by("kt-stat-source"),"Harga historis");text(by("kt-stat-updated"),latest?new Date(latest).toLocaleDateString("id-ID",{day:"numeric",month:"short",timeZone:"UTC"}):"—");
renderWatchlist();renderDashboard();
}).catch(()=>{text(by("kt-stat-source"),"Belum tersedia");text(by("kt-watch-note"),"Sumber historis belum dapat dimuat; buka Analisa untuk memeriksa data.")});
window.addEventListener("resize",()=>{if(market)renderDashboard()});
}
init();
})();
