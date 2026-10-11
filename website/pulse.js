
/* KATARINA PUBLIC V3 — data provenance gated UX
 * TradingView iframe = external chart. Annotated Lightweight Charts only from
 * verified and approved research, never sample/proprietary account data.
 */
(function(){
'use strict';
const d=document;
const qs=s=>d.querySelector(s);
const all=s=>Array.from(d.querySelectorAll(s));
const element=(tag,cls,txt)=>{const n=d.createElement(tag);if(cls)n.className=cls;if(txt!=null)n.textContent=String(txt);return n};
const activeLang=()=>d.documentElement.lang==='id'?'id':'en';
const lex=(id,en)=>activeLang()==='id'?id:en;
const REPORT_PENDING=lex('Belum ada laporan KATARINA yang telah diverifikasi dan disetujui untuk publikasi.','No KATARINA report has been verified and cleared for publication.');
function requestJson(url){return fetch(url,{cache:'no-store'}).then(r=>{if(!r.ok)throw Error('Unavailable');return r.json()})}
const state={cal:null,analysis:null,symbol:'OANDA:XAUUSD',charts:{},selected:null};
const sources={bls:'https://www.bls.gov/schedule/2026/10_sched_list.htm'};
function safeDate(x){return typeof x==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(x)&&Number.isFinite(Date.parse(x+'T12:00:00Z'))}
function safeUrl(s){try{let u=new URL(s);return u.protocol==='https:'?u.href:null}catch(e){return null}}
function dateLabel(x){try{return new Intl.DateTimeFormat(activeLang()==='id'?'id-ID':'en-US',{weekday:'short',day:'numeric',month:'short',year:'numeric',timeZone:'UTC'}).format(new Date(x+'T12:00:00Z'))}catch(e){return x}}
function compactEvent(x){let card=element('article','econ-entry');const when=element('div','econ-when',dateLabel(x.dateWIB)+'\n'+x.timeWIB+' WIB');when.style.whiteSpace='pre-line';card.append(when);
const info=element('div');info.append(element('strong','',x.title));info.append(element('p','',x.description));card.append(info);
const a=element('a','econ-badge',x.impact+' ↗');a.href=safeUrl(x.source)||sources.bls;a.target='_blank';a.rel='noopener noreferrer';card.append(a);return card;}
function renderCalendar(){const root=qs('#economic-events');if(root){root.replaceChildren();
if(!state.cal?.events?.length){root.append(element('p','placeholder',lex('Kalender resmi belum dimuat.','Official schedule not available.')))}
else for(const ev of state.cal.events){if(!safeDate(ev.dateWIB)||!/^\d\d:\d\d$/.test(ev.timeWIB)||!safeUrl(ev.source))continue;root.append(compactEvent(ev))}
}
const right=qs('#analysis-calendar');
if(right){right.replaceChildren();if(state.cal?.events){for(const ev of state.cal.events){let p=element('article','econ-entry');p.style.gridTemplateColumns='1fr';let title=element('strong','',dateLabel(ev.dateWIB)+' · '+ev.timeWIB+' WIB');let desc=element('p','',ev.title+' — '+ev.whatToWatch);p.append(title,desc);right.append(p)}}else right.append(element('p','muted',lex('Agenda ekonomi resmi belum tersedia.','Official events unavailable.')))}
}
function watchCategory(){const controls=all('.pulse-tags button[data-filter]');
if(!controls.length)return;for(const button of controls){button.addEventListener('click',()=>{controls.forEach(x=>x.setAttribute('aria-pressed',String(x===button)));window.katarinaMarketFilter=button.dataset.filter||'all';window.dispatchEvent(new Event('katarina-language'))})}}
function validCandles(items){if(!Array.isArray(items)||items.length<10||items.length>500)return false;let previous='';for(const c of items){if(!c||!safeDate(c.time)||typeof c.open!=='number'||typeof c.high!=='number'||typeof c.low!=='number'||typeof c.close!=='number'||![c.open,c.high,c.low,c.close].every(x=>Number.isFinite(x)&&x>0))return false;if(c.low>Math.min(c.open,c.close)||c.high<Math.max(c.open,c.close)||previous>=c.time)return false;previous=c.time}return true}
function validApprovedAnalysis(a){return a&&a.verified===true&&a.approvedForPublication===true&&typeof a.verification==='string'&&a.verification.trim().length>=20&&typeof a.evidenceUrl==='string'&&safeUrl(a.evidenceUrl)&&['OANDA:XAUUSD','OANDA:EURUSD','OANDA:GBPUSD','BITSTAMP:BTCUSD','OANDA:XAGUSD','OANDA:NAS100USD'].includes(a.symbol)&&['D','240','60','W'].includes(a.timeframe)&&validCandles(a.candles)&&Array.isArray(a.zones)&&a.zones.length<=12&&a.zones.every(z=>z&&['support','resistance','liquidity','invalidation'].includes(z.type)&&typeof z.low==='number'&&typeof z.high==='number'&&Number.isFinite(z.low)&&Number.isFinite(z.high)&&z.low>0&&z.high>=z.low&&typeof z.reason==='string'&&z.reason.length>=10&&z.reason.length<=350)&&typeof a.macroThesis==='string'&&a.macroThesis.length>=20&&typeof a.microThesis==='string'&&a.microThesis.length>=20&&safeDate(a.date)}
function analysisForSymbol(symbol){return (state.analysis?.analyses||[]).filter(validApprovedAnalysis).filter(x=>x.symbol===symbol).sort((a,b)=>b.date.localeCompare(a.date))[0]||null}
function appendReasonList(a){const el=qs('#zone-reasons');if(!el)return;el.replaceChildren();if(!a){el.textContent=lex('Area support, resistance, invalidasi, dan alasan analisa baru muncul setelah keluaran KATARINA diaudit.','Support, resistance and invalidation levels appear only after KATARINA analysis is audited.');return}
el.append(element('b','',lex('ALASAN MEMETAKAN AREA','RATIONALE FOR MARKING THESE ZONES')));
el.append(element('p','',a.macroThesis));el.append(element('p','',a.microThesis));let source=element('a','data-pill','Bukti verifikasi ↗');source.href=a.evidenceUrl;source.target='_blank';source.rel='noopener noreferrer';el.append(source);
}
function renderZones(){const selected=analysisForSymbol(state.symbol);state.selected=selected;const button=qs('#chart-annotated'),container=qs('#watch-zones'),outcome=qs('#analysis-outcome');
if(button){button.disabled=!selected;button.textContent=selected?lex('Zona KATARINA terverifikasi','Verified KATARINA zones'):lex('Zona KATARINA (menunggu data)','KATARINA zones (pending)')}
appendReasonList(selected);
if(container){container.replaceChildren();if(!selected){let empty=element('div','empty-visual');empty.style.minHeight='143px';empty.append(element('b','',lex('Menunggu zona terverifikasi','Awaiting verified zones')));empty.append(element('small','','Support · Resistance · Liquidity · Invalidation'));container.append(empty)}else{for(const zone of selected.zones){let card=element('div','risk-tag');card.style.marginBottom='7px';card.append(element('b','',zone.type.toUpperCase()+' · '+zone.low+'–'+zone.high));card.append(element('small','',zone.reason));container.append(card)}}}
if(outcome&&selected)outcome.textContent=selected.conclusion||lex('Laporan publik telah diverifikasi; tinjau sumber sebelum menggunakannya.','Verified public analysis; inspect source before use.');
if(!selected&&qs('#zone-annotated')?.classList.contains('visible'))toggleChart('external');
}
function toggleChart(mode){const frame=qs('#tv-host'),div=qs('#zone-annotated'),a=qs('#chart-default'),b=qs('#chart-annotated');if(!frame||!div)return;const showZones=mode==='zones'&&!!state.selected;
frame.classList.toggle('chart-hidden',showZones);div.classList.toggle('visible',showZones);if(a)a.setAttribute('aria-pressed',String(!showZones));if(b)b.setAttribute('aria-pressed',String(showZones));if(showZones){drawApprovedChart(state.selected)}}
function drawApprovedChart(a){const target=qs('#zone-chart');if(!target||!a||!validApprovedAnalysis(a))return;target.replaceChildren();if(!window.LightweightCharts){target.append(element('div','empty-visual',lex('Pustaka chart terverifikasi tidak tersedia.','Chart library unavailable.')));return}
const options={width:target.clientWidth||800,height:target.clientHeight||450,layout:{background:{color:'#031327'},textColor:'#a9c9e3'},grid:{vertLines:{color:'#102e49'},horzLines:{color:'#10304e'}},crosshair:{mode:1},timeScale:{borderColor:'#1a6594',timeVisible:false},rightPriceScale:{borderColor:'#1a6594'}};
const chart=window.LightweightCharts.createChart(target,options);
const candles=chart.addCandlestickSeries({upColor:'#15e4c6',downColor:'#ff6077',borderUpColor:'#15e4c6',borderDownColor:'#ff6077',wickUpColor:'#15e4c6',wickDownColor:'#ff6077'});
candles.setData(a.candles);
const cols={support:'#16daac',resistance:'#ff6b83',liquidity:'#42bfff',invalidation:'#ffd274'};
for(const z of a.zones){const col=cols[z.type];candles.createPriceLine({price:z.low,color:col,lineStyle:2,axisLabelVisible:true,title:z.type.toUpperCase()+' LOW',lineWidth:2});if(z.high!==z.low)candles.createPriceLine({price:z.high,color:col,lineStyle:2,axisLabelVisible:true,title:z.type.toUpperCase()+' HIGH',lineWidth:1})}
chart.timeScale().fitContent();
if(window.ResizeObserver){const resize=new ResizeObserver(entries=>{const r=entries[0]?.contentRect;if(r?.width)chart.resize(r.width,r.height)});resize.observe(target)}
}
function bindCharts(){if(!qs('#tv-host'))return;
all('[data-tv-symbol]').forEach(button=>{button.addEventListener('click',()=>{state.symbol=button.dataset.tvSymbol;renderZones();toggleChart('external')})});
qs('#chart-default')?.addEventListener('click',()=>toggleChart('external'));
qs('#chart-annotated')?.addEventListener('click',()=>toggleChart('zones'));
renderZones();
}
function fixTitle(){const titles={
'/':['Dashboard Utama','Dashboard'],
'/research.html':['Pusat Research','Research Hub'],
'/analisa.html':['Analisa Lengkap','Full Market Analysis'],
'/journal.html':['Jurnal Trading','Trading Journal'],
'/sponsors.html':['Sponsors & Kolaborasi','Sponsors & Collaboration']};
const pair=titles[location.pathname];if(pair)document.title='KATARINA AI · '+pair[activeLang()==='id'?0:1];}
fixTitle();window.addEventListener('katarina-language',fixTitle);
watchCategory();bindCharts();
requestJson('/calendar-brief.json').then(x=>{if(x.schema===1&&x.weekStart==='2026-10-12'&&Array.isArray(x.events))state.cal=x;renderCalendar()}).catch(renderCalendar);
requestJson('/market-analysis.json').then(x=>{if(x.schema===1&&Array.isArray(x.analyses))state.analysis=x;renderZones()}).catch(renderZones);
window.addEventListener('katarina-language',()=>{renderCalendar();renderZones()});
})();
