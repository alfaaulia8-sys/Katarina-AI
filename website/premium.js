/* KATARINA static market chart v5, mobile-safe. No third-party iframe.
   All OHLC snapshots are independently sourced and timestamped.
   GBPUSD official-reference rate is intentionally a GARIS, not synthetic OHLC.
   NASDAQ data is an index proxy and must never be labelled a NAS100 CFD. */
(()=>{"use strict";
const root=document.getElementById("tv-host");if(!root)return;
const mapping={"OANDA:XAUUSD":"xau","INDEX:DJI":"us30","OANDA:NAS100USD":"nasdaq","INDEX:SPX":"sp500","OANDA:EURUSD":"eurusd","OANDA:GBPUSD":"gbpusd","BITSTAMP:BTCUSD":"bitcoin","OANDA:XAGUSD":"silver"};
const names={"xau":"XAUUSD · Emas Spot","us30":"US30 · Dow Jones Index ^DJI (referensi indeks)","nasdaq":"NASDAQ Composite (bukan NAS100 CFD)","sp500":"S&P 500 (proxy US500 CFD)","eurusd":"EURUSD","gbpusd":"GBPUSD · Kurs Referensi","bitcoin":"BTCUSD","silver":"XAGUSD · Perak"};
const providerLink={"xau":"https://www.tradingview.com/symbols/XAUUSD/","us30":"https://www.tradingview.com/symbols/DJ-DJI/","nasdaq":"https://www.tradingview.com/symbols/NASDAQ-IXIC/","sp500":"https://www.tradingview.com/symbols/SP-SPX/","eurusd":"https://www.tradingview.com/symbols/EURUSD/","gbpusd":"https://www.tradingview.com/symbols/GBPUSD/","bitcoin":"https://www.tradingview.com/symbols/BTCUSD/","silver":"https://www.tradingview.com/symbols/XAGUSD/"};
const forexPairs=["USDJPY","USDCHF","USDCAD","AUDUSD","NZDUSD","EURGBP","EURJPY","EURCHF","EURCAD","EURAUD","EURNZD","GBPJPY","GBPCHF","GBPCAD","GBPAUD","GBPNZD","AUDJPY","AUDCAD","AUDCHF","AUDNZD","CADJPY","CADCHF","CHFJPY","NZDJPY","NZDCAD","NZDCHF"];
for(const p of forexPairs){const k=p.toLowerCase();mapping["FX:"+p]=k;names[k]=p+" · Kurs Referensi";providerLink[k]="https://www.tradingview.com/symbols/"+p+"/"}
let data=null,symbol="OANDA:XAUUSD",range=60,offset=0,hover=-1,canvas,ctx,frame,stats,status,selection,retainedObserver;let touches=new Map(),drag=null,pinch=null,detailBox;let scenarioOn=true;
const $=s=>document.querySelector(s);
function el(tag,cls,value){const e=document.createElement(tag);if(cls)e.className=cls;if(value!==undefined)e.textContent=String(value);return e}
function fmt(n,type){const decimal=/^[a-z]{6}$/.test(type)?(type.endsWith("jpy")?3:5):2;return Number(n).toLocaleString("id-ID",{maximumFractionDigits:decimal,minimumFractionDigits:decimal})}
function showError(message){root.replaceChildren();const box=el("div","market-empty");box.append(el("strong",null,message));box.append(el("p",null,"Gunakan tombol TradingView untuk membuka grafik penyedia secara langsung."));root.append(box)}
function niceStep(x){const raw=x||1,base=Math.pow(10,Math.floor(Math.log10(raw)));const r=raw/base;return(r<=1?1:r<=2?2:r<=5?5:10)*base}
function paint(){if(!canvas||!ctx||!frame)return;const key=mapping[symbol],pack=data?.series?.[key],raw=pack?.bars;
if(!Array.isArray(raw)||!raw.length)return;
offset=Math.max(0,Math.min(offset,Math.max(0,raw.length-range)));const stop=raw.length-offset;const list=raw.slice(Math.max(0,stop-range),stop),isLine=pack.type==="close-only";if(list.length<8)return;
const bbox=frame.getBoundingClientRect(),w=Math.max(280,Math.floor(bbox.width)),h=Math.max(280,Math.floor(bbox.height)),dpr=Math.min(2.4,devicePixelRatio||1);
canvas.width=Math.floor(w*dpr);canvas.height=Math.floor(h*dpr);canvas.style.width=w+"px";canvas.style.height=h+"px";
ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,w,h);
const left=12,right=72,top=57,bottom=37,plotW=w-left-right,plotH=h-top-bottom;
ctx.fillStyle="#041226";ctx.fillRect(0,0,w,h);
let lows=list.map(b=>isLine?b[1]:b[3]),highs=list.map(b=>isLine?b[1]:b[2]);const low=Math.min(...lows),high=Math.max(...highs),ext=Math.max((high-low)*.09,Math.abs(high)*.0009),min=low-ext,max=high+ext;
const y=v=>top+(max-v)/(max-min)*plotH;
const chartW=plotW*(scenarioOn?.73:1);const xx=i=>left+((i+.5)*chartW/list.length);
ctx.font="11px system-ui,Arial";ctx.textAlign="right";ctx.textBaseline="middle";
for(let z=0;z<=4;z++){const yy=top+plotH*z/4;
 ctx.strokeStyle="#17334e";ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(left,yy+.5);ctx.lineTo(w-right+5,yy+.5);ctx.stroke();
 ctx.fillStyle="#8bb0cd";ctx.fillText(fmt(max-(max-min)*z/4,key),w-5,yy);
}
for(let z=0;z<=4;z++){const idx=Math.round((list.length-1)*z/4),x=xx(idx),v=list[idx][0];
 ctx.strokeStyle="#102943";ctx.beginPath();ctx.moveTo(x,top);ctx.lineTo(x,top+plotH);ctx.stroke();
 const date=new Date(v*1000);ctx.textAlign="center";ctx.fillStyle="#93b8d2";ctx.fillText(date.toLocaleDateString("id-ID",{day:"numeric",month:"short",timeZone:"UTC"}),x,top+plotH+19);
}
if(isLine){const gradient=ctx.createLinearGradient(0,top,0,top+plotH);gradient.addColorStop(0,"rgba(31,219,255,.22)");gradient.addColorStop(1,"rgba(12,119,224,0)");
 ctx.beginPath();list.forEach((b,i)=>{const x=xx(i),q=y(b[1]);i?ctx.lineTo(x,q):ctx.moveTo(x,q)});
 ctx.lineTo(xx(list.length-1),top+plotH);ctx.lineTo(xx(0),top+plotH);ctx.closePath();ctx.fillStyle=gradient;ctx.fill();
 ctx.beginPath();list.forEach((b,i)=>{const x=xx(i),q=y(b[1]);i?ctx.lineTo(x,q):ctx.moveTo(x,q)});ctx.strokeStyle="#35d3ff";ctx.lineWidth=2.3;ctx.stroke();
}else{const cw=Math.max(1.8,Math.min(14,plotW/list.length*.66));list.forEach((b,i)=>{const x=xx(i),[,o,hi,lo,c]=b,green=c>=o;color(green);ctx.lineWidth=1.3;ctx.beginPath();ctx.moveTo(x,y(hi));ctx.lineTo(x,y(lo));ctx.stroke();ctx.fillRect(x-cw/2,y(Math.max(o,c)),cw,Math.max(1.5,Math.abs(y(o)-y(c))))});}
function color(g){ctx.fillStyle=ctx.strokeStyle=g?"#20dbc3":"#ff677e"}
const last=list.at(-1),prev=list.at(-2),price=isLine?last[1]:last[4],prevPrice=isLine?prev[1]:prev[4],pct=(price/prevPrice-1)*100;
ctx.textAlign="left";ctx.textBaseline="middle";ctx.font="700 14px system-ui,Arial";ctx.fillStyle="#daf4ff";ctx.fillText(names[key]||key,left,21);
ctx.textAlign="right";ctx.fillStyle=pct>=0?"#38e9cc":"#ff8192";ctx.fillText(fmt(price,key)+"  "+(pct>=0?"+":"")+pct.toFixed(2)+"%",w-12,21);
const rangeCaption=range+" candle / geser untuk histori";ctx.textAlign="left";ctx.fillStyle="#7fabc9";ctx.font="11px system-ui,Arial";ctx.fillText((isLine?"KURS REFERENSI · LINE":"OHLC · CANDLE") +"  •  1D  •  "+rangeCaption,left,42);
if(scenarioOn&&!isLine)paintSkenarioMingguan(list,{left,plotW,top,plotH,y,xx,w,right,key});
if(hover>=0&&hover<list.length){const b=list[hover],x=xx(hover),p=isLine?b[1]:b[4],cy=y(p);if(detailBox){detailBox.textContent=new Date(b[0]*1000).toLocaleDateString('id-ID',{dateStyle:'medium',timeZone:'UTC'})+' · '+(isLine?'Tutup ':'Buka '+fmt(b[1],key)+' · Tinggi '+fmt(b[2],key)+' · Rendah '+fmt(b[3],key)+' · Tutup ')+fmt(p,key)}ctx.save();ctx.setLineDash([3,4]);ctx.strokeStyle="#8dcef8";ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(x,top);ctx.lineTo(x,top+plotH);ctx.moveTo(left,cy);ctx.lineTo(w-right,cy);ctx.stroke();ctx.restore();
 let text=isLine?"C "+fmt(p,key):"O "+fmt(b[1],key)+"   H "+fmt(b[2],key)+"   L "+fmt(b[3],key)+"   C "+fmt(b[4],key);
 ctx.fillStyle="#031729";ctx.fillRect(left,top,Math.min(w-right-left,340),22);ctx.fillStyle="#b9e9ff";ctx.font="10px system-ui,Arial";ctx.textAlign="left";ctx.fillText(new Date(b[0]*1000).toISOString().slice(0,10)+"   "+text,left+4,top+12);
 ctx.beginPath();ctx.arc(x,cy,3,0,Math.PI*2);ctx.fillStyle="#aaf1ff";ctx.fill();
}
}

function paintSkenarioMingguan(list,g){
 if(list.length<20)return;
 const recent=list.slice(-20);
 const peak=Math.max(...recent.map(b=>b[2])),trough=Math.min(...recent.map(b=>b[3]));
 const width=peak-trough;if(!(width>0))return;
 const {left,plotW,top,plotH,y,xx,w,right,key}=g,base=recent.at(-1)[4];
 const x0=left+plotW*.01,x1=left+plotW*.97,xNew=left+plotW*.75,xEnd=left+plotW*.97;
 const bands=[{name:"ATAS",from:peak-width*.13,to:peak,color:"46,213,191",text:"#63e9d4"},
              {name:"BAWAH",from:trough,to:trough+width*.13,color:"253,136,147",text:"#ff9eae"}];
 ctx.save();
 // Reference zones use ACTUAL last-20 candle extrema, not unpublished proprietary supply/demand.
 for(const b of bands){
  const y1=y(b.to),y2=y(b.from);ctx.fillStyle="rgba("+b.color+",.105)";
  ctx.fillRect(x0,y1,x1-x0,Math.max(2,y2-y1));
  ctx.strokeStyle="rgba("+b.color+",.55)";ctx.setLineDash([4,5]);ctx.lineWidth=.8;
  ctx.strokeRect(x0,y1,x1-x0,Math.max(2,y2-y1));ctx.setLineDash([]);
  ctx.font="700 10px system-ui";ctx.textAlign="right";ctx.fillStyle=b.text;ctx.fillText(b.name,xEnd,y1+12);
 }
 // Measured 38.2% / 61.8% retracement of the observed 20-session high-low.
 for(const fib of [.382,.618]){
  const price=peak-width*fib;ctx.strokeStyle="#7290ad50";ctx.setLineDash([3,5]);
  ctx.beginPath();ctx.moveTo(x0,y(price));ctx.lineTo(xEnd,y(price));ctx.stroke();ctx.setLineDash([]);
  if(w>580){ctx.fillStyle="#a5c0d1";ctx.textAlign="right";ctx.font="10px system-ui";ctx.fillText((fib*100).toFixed(1)+"%",xNew-4,y(price)-5)}
 }
 // Both branches are conditional ILLUSTRATIONS, not predictions or executable price targets.
 const xBase=xx(list.length-1),z=[xBase,xNew+plotW*.06,xNew+plotW*.12,xNew+plotW*.17];
 const limit=(v)=>Math.max(top+5,Math.min(top+plotH-5,y(v)));
 const draw=(dir)=>{
  const goal=dir>0?peak:trough;
  const middle=base+(goal-base)*.28,back=base+(goal-base)*.17,tail=base+(goal-base)*.78;
  const points=[[xBase,limit(base)],[z[1],limit(middle)],[z[2],limit(back)],[z[3],limit(tail)]];
  ctx.strokeStyle=dir>0?"#54eac1":"#fc8394";ctx.lineWidth=w<500?1.6:2;ctx.setLineDash([6,4]);
  ctx.beginPath();points.forEach(([x,t],i)=>i?ctx.lineTo(x,t):ctx.moveTo(x,t));ctx.stroke();ctx.setLineDash([]);
  const prev=points.at(-2),last=points.at(-1),angle=Math.atan2(last[1]-prev[1],last[0]-prev[0]);
  ctx.beginPath();ctx.moveTo(last[0],last[1]);ctx.lineTo(last[0]-7*Math.cos(angle-.5),last[1]-7*Math.sin(angle-.5));ctx.lineTo(last[0]-7*Math.cos(angle+.5),last[1]-7*Math.sin(angle+.5));ctx.closePath();ctx.fillStyle=ctx.strokeStyle;ctx.fill();
 };
 draw(1);draw(-1);
 ctx.textAlign="center";ctx.font="700 9px system-ui";ctx.fillStyle="#94b4cd";ctx.fillText(w<580?"SKENARIO":"SKENARIO BERSYARAT",xNew+plotW*.1,top+12);
 ctx.restore();
}

function available(){return data?.series?.[mapping[symbol]]?.bars?.length||0}
function adjustRange(count){const total=available();range=Math.min(Math.max(12,total),Math.max(12,count));offset=Math.max(0,Math.min(offset,Math.max(0,total-range)));hover=-1;paint()}
function hoverAt(e){if(!frame)return;const r=frame.getBoundingClientRect(),count=Math.min(available()-offset,range),plotW=Math.max(1,(r.width-84)*(scenarioOn?.73:1));if(count<1)return;hover=Math.min(count-1,Math.max(0,Math.floor(((e.clientX-r.left-12)/plotW)*count)));requestAnimationFrame(paint)}
function down(e){if(e.pointerType==="mouse"&&e.button!==0)return;e.preventDefault();canvas.setPointerCapture?.(e.pointerId);touches.set(e.pointerId,{x:e.clientX,y:e.clientY});if(touches.size===1){drag={x:e.clientX,base:offset,moved:false};pinch=null;hoverAt(e)}else if(touches.size===2){const a=[...touches.values()];pinch={distance:Math.hypot(a[0].x-a[1].x,a[0].y-a[1].y),range};drag=null}}
function pointer(e){if(!touches.has(e.pointerId)){if(e.pointerType==="mouse")hoverAt(e);return}touches.set(e.pointerId,{x:e.clientX,y:e.clientY});if(touches.size>=2){const v=[...touches.values()];if(!pinch)pinch={distance:Math.hypot(v[0].x-v[1].x,v[0].y-v[1].y),range};const dist=Math.max(10,Math.hypot(v[0].x-v[1].x,v[0].y-v[1].y));adjustRange(Math.round(pinch.range*pinch.distance/dist));return}
if(drag){const dx=e.clientX-drag.x;if(Math.abs(dx)>7)drag.moved=true;if(drag.moved){const total=available(),width=Math.max(1,(frame.getBoundingClientRect().width-84)*(scenarioOn?.73:1));offset=Math.max(0,Math.min(Math.max(0,total-range),drag.base+Math.round(dx/width*range)));hover=-1;requestAnimationFrame(paint)}else hoverAt(e)}}
function up(e){const moved=drag?.moved;touches.delete(e.pointerId);if(touches.size<2)pinch=null;if(touches.size===0){drag=null;if(!moved)hoverAt(e)}}
function build(){root.replaceChildren();const wrap=el("div","self-chart-frame");root.append(wrap);frame=wrap;canvas=document.createElement("canvas");canvas.setAttribute("role","img");canvas.setAttribute("aria-label","Grafik historis OHLC atau garis dari data pasar eksternal, bukan hasil trading KATARINA");canvas.style.cssText="display:block;width:100%;height:100%;touch-action:none;user-select:none";wrap.append(canvas);ctx=canvas.getContext("2d");if(!ctx){showError("Canvas grafik tidak didukung");return}
canvas.addEventListener("pointerdown",down);canvas.addEventListener("pointermove",pointer);canvas.addEventListener("pointerup",up);canvas.addEventListener("pointercancel",up);canvas.addEventListener("pointerleave",e=>{if(e.pointerType!=="touch"&&!touches.size){hover=-1;paint()}});
canvas.addEventListener("wheel",e=>{e.preventDefault();adjustRange(range+(e.deltaY>0?8:-8))},{passive:false});
retainedObserver=new ResizeObserver(()=>requestAnimationFrame(paint));retainedObserver.observe(wrap);
stats=el("div","market-chart-meta");root.append(stats);
detailBox=el("div","kt-chart-touch-info","Ketuk candle untuk rincian OHLC • Geser kiri/kanan • Cubit atau gunakan + / − untuk zoom");root.append(detailBox);
const nav=el("div","market-chart-controls");for(const [period,value] of [["1 bulan",25],["3 bulan",65]]){const b=el("button","market-period",period);b.type="button";b.dataset.days=value;b.setAttribute("aria-pressed",String(range===value));b.addEventListener("click",()=>{range=Math.min(available(),value);offset=0;hover=-1;nav.querySelectorAll("[data-days]").forEach(z=>z.setAttribute("aria-pressed",String(z===b)));update()});nav.append(b)}for(const [label,step] of [["−",9],["+",-9]]){const b=el("button","market-period",label);b.type="button";b.setAttribute("aria-label",step<0?"Perbesar candle":"Perkecil candle");b.addEventListener("click",()=>adjustRange(range+step));nav.append(b)}
const reset=el("button","market-period","Terbaru");reset.type="button";reset.addEventListener("click",()=>{offset=0;hover=-1;paint()});nav.append(reset);
root.append(nav);
update()}
function update(){const key=mapping[symbol],item=data?.series?.[key];if(!item||!item.bars?.length){showError("Data grafik belum tersedia");return}
const dt=new Date(item.asOf);const asOf=Number.isFinite(dt.getTime())?dt.toLocaleString("id-ID",{dateStyle:"medium",timeStyle:"short",timeZone:"Asia/Jakarta"})+" WIB":"waktu tidak tersedia";
const days=Math.max(0,Math.floor((Date.now()-new Date(item.asOf).getTime())/86400000));stats.textContent="Sumber: "+(item.source||data.provider)+" • Terakhir: "+asOf+(days>3?" • DATA LAMA, bukan harga terkini":"")+" • "+(item.type==="close-only"?"kurs penutupan referensi":"candle historis")+(item.status==="stale"?" • DATA LAMA: sumber terbaru tidak lolos validasi":"")+(item.latestBarIsOpen?" • candle harian belum final":"")+" • Bukan sinyal KATARINA";
if(ctx)requestAnimationFrame(paint);}
const mapToggle=document.getElementById("kt-week-map-toggle");
if(mapToggle){mapToggle.addEventListener("click",()=>{scenarioOn=!scenarioOn;mapToggle.setAttribute("aria-pressed",String(scenarioOn));mapToggle.textContent=scenarioOn?"◇ Sembunyikan peta mingguan":"◇ Tampilkan peta mingguan";hover=-1;requestAnimationFrame(paint)})}
function select(s){if(symbol!==s){offset=0;range=60}symbol=s;hover=-1;const key=mapping[s];const btns=document.querySelectorAll("[data-tv-symbol]");btns.forEach(b=>b.setAttribute("aria-selected",String(b.dataset.tvSymbol===s)));
const tv=$('#chart-direct-link');const lbl=$('#chart-symbol-label');if(tv)tv.href=providerLink[key]||"https://www.tradingview.com/";if(lbl)lbl.textContent=document.querySelector("[data-instrument-select]")?.value||(key==="nasdaq"?"NASDAQ":key.toUpperCase());
const source=$('#source-chart');if(source)source.href="https://www.tradingview.com/chart/";
if(data?.series?.[key]){if(!frame)build();else update()}else showError("Data harga "+key.toUpperCase()+" belum tersedia dari penyedia tepercaya");}
document.querySelectorAll("[data-tv-symbol]").forEach(b=>b.addEventListener("click",()=>select(b.dataset.tvSymbol)));
window.addEventListener("katarina-select-symbol",e=>{const target=e.detail?.symbol;if(target&&Object.prototype.hasOwnProperty.call(mapping,target))select(target)});
const warning=el("p","market-disclaimer","Grafik ini menggunakan snapshot harga publik yang diperiksa berkala. Bukan data tick real-time MT5. Gunakan chart broker untuk eksekusi.");
root.after(warning);
fetch("/market-ohlc.json",{cache:"no-store"}).then(r=>{if(!r.ok)throw Error("Gagal ambil market-ohlc.json");return r.json()}).then(j=>{if(j?.schema!==1||typeof j.series!=="object"||!Array.isArray(j.series.xau?.bars))throw Error("Format data tidak valid");data=j;select(symbol)}).catch(err=>{showError("Grafik belum tersedia: "+err.message)});
})();
