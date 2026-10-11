/* KATARINA static market chart v5, mobile-safe. No third-party iframe.
   All OHLC snapshots are independently sourced and timestamped.
   GBPUSD official-reference rate is intentionally a LINE, not synthetic OHLC.
   NASDAQ data is an index proxy and must never be labelled a NAS100 CFD. */
(()=>{"use strict";
const root=document.getElementById("tv-host");if(!root)return;
const mapping={"OANDA:XAUUSD":"xau","INDEX:DJI":"us30","OANDA:NAS100USD":"nasdaq","INDEX:SPX":"sp500","OANDA:EURUSD":"eurusd","OANDA:GBPUSD":"gbpusd","BITSTAMP:BTCUSD":"bitcoin","OANDA:XAGUSD":"silver"};
const names={"xau":"XAUUSD · Gold Spot","us30":"US30 · Dow Jones Index ^DJI (proxy CFD)","nasdaq":"NASDAQ Composite (bukan NAS100 CFD)","sp500":"S&P 500 (proxy US500 CFD)","eurusd":"EURUSD","gbpusd":"GBPUSD · Kurs referensi","bitcoin":"BTCUSD","silver":"XAGUSD · Silver"};
const providerLink={"xau":"https://www.tradingview.com/symbols/XAUUSD/","us30":"https://www.tradingview.com/symbols/DJ-DJI/","nasdaq":"https://www.tradingview.com/symbols/NASDAQ-IXIC/","sp500":"https://www.tradingview.com/symbols/SP-SPX/","eurusd":"https://www.tradingview.com/symbols/EURUSD/","gbpusd":"https://www.tradingview.com/symbols/GBPUSD/","bitcoin":"https://www.tradingview.com/symbols/BTCUSD/","silver":"https://www.tradingview.com/symbols/XAGUSD/"};
let data=null,symbol="OANDA:XAUUSD",range=70,hover=-1,canvas,ctx,frame,stats,status,selection,retainedObserver;
const $=s=>document.querySelector(s);
function el(tag,cls,value){const e=document.createElement(tag);if(cls)e.className=cls;if(value!==undefined)e.textContent=String(value);return e}
function fmt(n,type){const decimal=(type==="eurusd"||type==="gbpusd")?5:2;return Number(n).toLocaleString("id-ID",{maximumFractionDigits:decimal,minimumFractionDigits:decimal})}
function showError(message){root.replaceChildren();const box=el("div","market-empty");box.append(el("strong",null,message));box.append(el("p",null,"Gunakan tombol TradingView untuk membuka grafik penyedia secara langsung."));root.append(box)}
function niceStep(x){const raw=x||1,base=Math.pow(10,Math.floor(Math.log10(raw)));const r=raw/base;return(r<=1?1:r<=2?2:r<=5?5:10)*base}
function paint(){if(!canvas||!ctx||!frame)return;const key=mapping[symbol],pack=data?.series?.[key],raw=pack?.bars;
if(!Array.isArray(raw)||!raw.length)return;
const list=raw.slice(-range),isLine=pack.type==="close-only";if(list.length<8)return;
const bbox=frame.getBoundingClientRect(),w=Math.max(280,Math.floor(bbox.width)),h=Math.max(280,Math.floor(bbox.height)),dpr=Math.min(2.4,devicePixelRatio||1);
canvas.width=Math.floor(w*dpr);canvas.height=Math.floor(h*dpr);canvas.style.width=w+"px";canvas.style.height=h+"px";
ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,w,h);
const left=12,right=72,top=57,bottom=37,plotW=w-left-right,plotH=h-top-bottom;
ctx.fillStyle="#041226";ctx.fillRect(0,0,w,h);
let lows=list.map(b=>isLine?b[1]:b[3]),highs=list.map(b=>isLine?b[1]:b[2]);const low=Math.min(...lows),high=Math.max(...highs),ext=Math.max((high-low)*.09,Math.abs(high)*.0009),min=low-ext,max=high+ext;
const y=v=>top+(max-v)/(max-min)*plotH;
const xx=i=>left+((i+.5)*plotW/list.length);
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
const rangeCaption=range===30?"1 bulan":"3 bulan";ctx.textAlign="left";ctx.fillStyle="#7fabc9";ctx.font="11px system-ui,Arial";ctx.fillText((isLine?"KURS REFERENSI · LINE":"OHLC · CANDLE") +"  •  1D  •  "+rangeCaption,left,42);
if(hover>=0&&hover<list.length){const b=list[hover],x=xx(hover),p=isLine?b[1]:b[4],cy=y(p);ctx.save();ctx.setLineDash([3,4]);ctx.strokeStyle="#8dcef8";ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(x,top);ctx.lineTo(x,top+plotH);ctx.moveTo(left,cy);ctx.lineTo(w-right,cy);ctx.stroke();ctx.restore();
 let text=isLine?"C "+fmt(p,key):"O "+fmt(b[1],key)+"   H "+fmt(b[2],key)+"   L "+fmt(b[3],key)+"   C "+fmt(b[4],key);
 ctx.fillStyle="#031729";ctx.fillRect(left,top,Math.min(w-right-left,340),22);ctx.fillStyle="#b9e9ff";ctx.font="10px system-ui,Arial";ctx.textAlign="left";ctx.fillText(new Date(b[0]*1000).toISOString().slice(0,10)+"   "+text,left+4,top+12);
 ctx.beginPath();ctx.arc(x,cy,3,0,Math.PI*2);ctx.fillStyle="#aaf1ff";ctx.fill();
}
}
function pointer(e){const r=frame.getBoundingClientRect(),key=mapping[symbol],count=Math.min(data?.series?.[key]?.bars?.length||0,range),plotW=r.width-84;hover=Math.min(count-1,Math.max(0,Math.floor(((e.clientX-r.left-12)/plotW)*count)));requestAnimationFrame(paint)}
function build(){root.replaceChildren();const wrap=el("div","self-chart-frame");root.append(wrap);frame=wrap;canvas=document.createElement("canvas");canvas.setAttribute("role","img");canvas.setAttribute("aria-label","Grafik historis OHLC atau garis dari data pasar eksternal, bukan hasil trading KATARINA");canvas.style.cssText="display:block;width:100%;height:100%;touch-action:pan-y";wrap.append(canvas);ctx=canvas.getContext("2d");if(!ctx){showError("Canvas grafik tidak didukung");return}
canvas.addEventListener("pointermove",pointer,{passive:true});canvas.addEventListener("pointerleave",()=>{hover=-1;paint()});
retainedObserver=new ResizeObserver(()=>requestAnimationFrame(paint));retainedObserver.observe(wrap);
stats=el("div","market-chart-meta");root.append(stats);
const nav=el("div","market-chart-controls");for(const [period,value] of [["1 bulan",30],["3 bulan",70]]){const b=el("button","market-period",period);b.type="button";b.dataset.days=value;b.setAttribute("aria-pressed",String(range===value));b.addEventListener("click",()=>{range=value;hover=-1;nav.querySelectorAll("button").forEach(z=>z.setAttribute("aria-pressed",String(z===b)));update()});nav.append(b)}root.append(nav);
update()}
function update(){const key=mapping[symbol],item=data?.series?.[key];if(!item||!item.bars?.length){showError("Data grafik belum tersedia");return}
const dt=new Date(item.asOf);const asOf=Number.isFinite(dt.getTime())?dt.toLocaleString("id-ID",{dateStyle:"medium",timeStyle:"short",timeZone:"Asia/Jakarta"})+" WIB":"waktu tidak tersedia";
const days=Math.max(0,Math.floor((Date.now()-new Date(item.asOf).getTime())/86400000));stats.textContent="Sumber: "+(item.source||data.provider)+" • Terakhir: "+asOf+(days>3?" • DATA LAMA, bukan harga terkini":"")+" • "+(item.type==="close-only"?"kurs penutupan referensi":"candle historis")+" • Bukan sinyal KATARINA";
if(ctx)requestAnimationFrame(paint);}
function select(s){symbol=s;hover=-1;const key=mapping[s];const btns=document.querySelectorAll("[data-tv-symbol]");btns.forEach(b=>b.setAttribute("aria-selected",String(b.dataset.tvSymbol===s)));
const tv=$('#chart-direct-link');const lbl=$('#chart-symbol-label');if(tv)tv.href=providerLink[key]||"https://www.tradingview.com/";if(lbl)lbl.textContent=key==="nasdaq"?"NASDAQ":key.toUpperCase();
const source=$('#source-chart');if(source)source.href="https://www.tradingview.com/chart/";
if(data?.series?.[key]){if(!frame)build();else update()}else showError("Data harga "+key.toUpperCase()+" belum tersedia dari penyedia tepercaya");}
document.querySelectorAll("[data-tv-symbol]").forEach(b=>b.addEventListener("click",()=>select(b.dataset.tvSymbol)));
const warning=el("p","market-disclaimer","Grafik ini menggunakan snapshot harga publik yang diperiksa berkala. Bukan data tick real-time MT5. Gunakan chart broker untuk eksekusi.");
root.after(warning);
fetch("/market-ohlc.json",{cache:"no-store"}).then(r=>{if(!r.ok)throw Error("Gagal ambil market-ohlc.json");return r.json()}).then(j=>{if(j?.schema!==1||typeof j.series!=="object"||!Array.isArray(j.series.xau?.bars))throw Error("Format data tidak valid");data=j;select(symbol)}).catch(err=>{showError("Grafik belum tersedia: "+err.message)});
})();
