
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
function compactEvent(x){
let card=element('article','econ-entry');
const when=element('div','econ-when',dateLabel(x.dateWIB)+' • '+x.timeWIB+' WIB');card.append(when);
const info=element('div');info.append(element('strong','',x.title));
const metrics=element('div','econ-metrics');
const translations={
 id:['Aktual','Prediksi','Sebelumnya','Belum rilis','Belum tersedia','Analisis singkat'],
 en:['Actual','Consensus','Previous','Not released','Unavailable','Quick analysis'],
 es:['Actual','Consenso','Anterior','Sin publicar','No disponible','Análisis breve'],
 fr:['Réel','Consensus','Précédent','Non publié','Indisponible','Analyse brève'],
 pt:['Real','Consenso','Anterior','Não publicado','Indisponível','Análise breve'],
 de:['Istwert','Konsens','Vorher','Noch offen','Nicht verfügbar','Kurzanalyse'],
 ar:['الفعلي','التوقع','السابق','لم يصدر','غير متاح','تحليل موجز'],
 hi:['वास्तविक','अनुमान','पिछला','जारी नहीं','उपलब्ध नहीं','संक्षिप्त विश्लेषण'],
 zh:['实际','预期','前值','尚未公布','暂无','简析'],
 ja:['実績','予想','前回','未発表','不明','簡易分析'],
 ko:['실제','예측','이전','미발표','없음','간단 분석'],
 ru:['Факт','Прогноз','Прошлое','Не вышел','Нет данных','Краткий анализ'],
 ms:['Sebenar','Ramalan','Terdahulu','Belum terbit','Tiada data','Analisis ringkas'],
 tr:['Gerçek','Beklenti','Önceki','Yayınlanmadı','Mevcut değil','Kısa analiz']
};
const words=translations[d.documentElement.lang]||translations.en;
for(const [label,val,source,hasReleased] of [[words[0],x.actual,x.actualSource,false],[words[1],x.forecast,x.forecastSource,true],[words[2],x.previous,x.previousSource,true]]){
 const cell=element('div','econ-metric');cell.append(element('small','',label));const verified=val!==null&&val!==undefined&&String(val).length>0&&safeUrl(source);
 cell.append(element('b','',verified?String(val):(hasReleased?words[4]:words[3])));metrics.append(cell);
}
info.append(metrics);
info.append(element('p','econ-comment',x.description));
const analysis=element('p','econ-comment');analysis.append(element('span','econ-label',words[5]+': '));analysis.append(d.createTextNode(x.analysisShort||x.conditional||x.whatToWatch||''));info.append(analysis);
const imp=window.katarinaInstrument?(x.instrumentImpact?.[window.katarinaInstrument]||0):0;const impTxt=imp>=4?'SANGAT TINGGI':imp===3?'TINGGI':imp===2?'SEDANG':x.impact;const attributions=element('div','econ-sources');const origin=element('a','econ-badge',impTxt+' · '+(x.region||'')+' ↗');origin.href=safeUrl(x.source)||sources.bls;origin.target='_blank';origin.rel='noopener noreferrer';attributions.append(origin);
if(safeUrl(x.forecastSource)){const market=element('a','econ-badge',d.documentElement.lang==='id'?'Sumber konsensus ↗':'Consensus source ↗');market.href=x.forecastSource;market.target='_blank';market.rel='noopener noreferrer';attributions.append(market)}
info.append(attributions);
const details=element('div','econ-effects');
details.append(element('h4','econ-effects-title',d.documentElement.lang==='id'?'Penjelasan dampak & skenario ekonomi':'Economic impact and scenarios'));
const add=(label,content)=>{if(!content)return;const row=element('div','econ-effect-row');row.append(element('strong','',label));row.append(element('p','',content));details.append(row)};
add(d.documentElement.lang==='id'?'Mengapa rilis ini penting':'Why this matters',x.transmission||x.description);
add(d.documentElement.lang==='id'?'Jika aktual di atas prediksi':'If actual exceeds consensus',x.ifAbove);
add(d.documentElement.lang==='id'?'Jika aktual di bawah prediksi':'If actual misses consensus',x.ifBelow);
add(d.documentElement.lang==='id'?'Apa yang wajib dipantau':'What to monitor',x.detailedWatch||x.whatToWatch);
if(document.querySelector('.kt-unified')){
 const disclosure=element('details','kt-calendar-details');
 const heading=element('summary','kt-calendar-summary','Lihat penjelasan dan skenario dampak');
 disclosure.append(heading,details);
 info.append(disclosure);
}else info.append(details);
card.append(info);return card;
}
function renderCalendar(){const root=qs('#economic-events');if(root){root.replaceChildren();
if(!state.cal?.events?.length){root.append(element('p','placeholder',lex('Kalender resmi belum dimuat.','Official schedule not available.')))}
else {const relevant=state.cal.events.filter(x=>!window.katarinaInstrument||(x.instrumentImpact?.[window.katarinaInstrument]||0)>=2);if(!relevant.length)root.append(element('p','placeholder',lex('Belum ada agenda berdampak tinggi yang diverifikasi untuk pasangan ini.','No verified high-impact event available for this pair.')));for(const ev of relevant){if(!safeDate(ev.dateWIB)||!/^\d\d:\d\d$/.test(ev.timeWIB)||!safeUrl(ev.source))continue;root.append(compactEvent(ev))}}
}

}
function watchCategory(){const controls=all('.pulse-tags button[data-filter]');
if(!controls.length)return;for(const button of controls){button.addEventListener('click',()=>{controls.forEach(x=>x.setAttribute('aria-pressed',String(x===button)));window.katarinaMarketFilter=button.dataset.filter||'all';window.dispatchEvent(new Event('katarina-language'))})}}
function validCandles(items){if(!Array.isArray(items)||items.length<10||items.length>500)return false;let previous='';for(const c of items){if(!c||!safeDate(c.time)||typeof c.open!=='number'||typeof c.high!=='number'||typeof c.low!=='number'||typeof c.close!=='number'||![c.open,c.high,c.low,c.close].every(x=>Number.isFinite(x)&&x>0))return false;if(c.low>Math.min(c.open,c.close)||c.high<Math.max(c.open,c.close)||previous>=c.time)return false;previous=c.time}return true}
function validApprovedAnalysis(a){return a&&a.verified===true&&a.approvedForPublication===true&&typeof a.verification==='string'&&a.verification.trim().length>=20&&typeof a.evidenceUrl==='string'&&safeUrl(a.evidenceUrl)&&(['OANDA:XAUUSD','INDEX:DJI','INDEX:SPX','OANDA:EURUSD','OANDA:GBPUSD','BITSTAMP:BTCUSD','OANDA:XAGUSD','OANDA:NAS100USD'].includes(a.symbol) || /^FX:(?:EUR|GBP|USD|AUD|NZD|CAD|CHF|JPY){2}$/.test(a.symbol))&&['D','240','60','W'].includes(a.timeframe)&&validCandles(a.candles)&&Array.isArray(a.zones)&&a.zones.length<=12&&a.zones.every(z=>z&&['support','resistance','liquidity','invalidation'].includes(z.type)&&typeof z.low==='number'&&typeof z.high==='number'&&Number.isFinite(z.low)&&Number.isFinite(z.high)&&z.low>0&&z.high>=z.low&&typeof z.reason==='string'&&z.reason.length>=10&&z.reason.length<=350)&&typeof a.macroThesis==='string'&&a.macroThesis.length>=20&&typeof a.microThesis==='string'&&a.microThesis.length>=20&&safeDate(a.date)}
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
'/research.html':['Riset & Analisa','Research & Analysis'],
'/analisa.html':['Analisa Lengkap','Full Market Analysis'],
'/journal.html':['Jurnal Trading','Trading Journal'],
'/sponsors.html':['Sponsors & Kolaborasi','Sponsors & Collaboration']};
const pair=titles[location.pathname];if(pair)document.title='KATARINA AI · '+pair[activeLang()==='id'?0:1];}
fixTitle();window.addEventListener('katarina-language',fixTitle);
watchCategory();bindCharts();
requestJson('/calendar-brief.json').then(x=>{if(x.schema===1&&Array.isArray(x.events))state.cal=x;renderCalendar()}).catch(renderCalendar);
requestJson('/market-analysis.json').then(x=>{if(x.schema===1&&Array.isArray(x.analyses))state.analysis=x;renderZones()}).catch(renderZones);
window.addEventListener('katarina-language',()=>{renderCalendar();renderZones()});window.addEventListener('katarina-instrument',renderCalendar);
window.addEventListener('katarina-select-symbol',event=>{
  const symbol=event.detail?.symbol;
  if(typeof symbol!=='string'||symbol===state.symbol)return;
  state.symbol=symbol;
  renderZones();
  toggleChart('external');
});
})();

/* KATARINA AI — independent market news cards, source-linked and scrollable */
(function(){
'use strict';
const root=document.querySelector('#news-feed');if(!root)return;
const langs={id:{source:'Sumber',analysis:'Analisis Singkat',empty:'Belum ada berita terverifikasi.',view:'Baca sumber ↗',news:'Berita Pasar'},en:{source:'Source',analysis:'Quick Analysis',empty:'No verified news available.',view:'Read source ↗',news:'Market News'},es:{source:'Fuente',analysis:'Análisis breve',empty:'Sin noticias verificadas.',view:'Leer fuente ↗'},fr:{source:'Source',analysis:'Analyse brève',empty:'Aucune actualité vérifiée.',view:'Lire la source ↗'},pt:{source:'Fonte',analysis:'Análise breve',empty:'Sem notícias verificadas.',view:'Ver fonte ↗'},de:{source:'Quelle',analysis:'Kurzanalyse',empty:'Keine geprüften Nachrichten.',view:'Quelle ↗'},ar:{source:'المصدر',analysis:'تحليل موجز',empty:'لا توجد أخبار موثقة.',view:'المصدر ↗'},hi:{source:'स्रोत',analysis:'संक्षिप्त विश्लेषण',empty:'सत्यापित समाचार नहीं।',view:'स्रोत ↗'},zh:{source:'来源',analysis:'简析',empty:'暂无核实新闻。',view:'阅读来源 ↗'},ja:{source:'出典',analysis:'簡易分析',empty:'確認済み記事なし。',view:'情報源 ↗'},ko:{source:'출처',analysis:'간단 분석',empty:'검증된 뉴스가 없습니다.',view:'출처 ↗'},ru:{source:'Источник',analysis:'Краткий анализ',empty:'Нет проверенных новостей.',view:'Источник ↗'},ms:{source:'Sumber',analysis:'Analisis ringkas',empty:'Tiada berita disahkan.',view:'Baca sumber ↗'},tr:{source:'Kaynak',analysis:'Kısa analiz',empty:'Doğrulanmış haber yok.',view:'Kaynağı aç ↗'}};
const text=(t,v)=>{const e=document.createElement(t);e.textContent=String(v);return e};
let cached=[];let filtering='all';
function render(){
root.replaceChildren();let lang=document.documentElement.lang||'id';const word=langs[lang]||langs.en;
const focus=window.katarinaInstrument;
const ranks={'SANGAT TINGGI':4,'TINGGI':3,'SEDANG':2,'RENDAH':1};
const visible=cached.filter(item=>(!focus||(item.symbols||[]).includes(focus))&&(filtering==='all'||(item.markets||[]).includes(filtering))).slice().sort((a,b)=>(ranks[b.impact]||0)-(ranks[a.impact]||0)||b.date.localeCompare(a.date));
if(!visible.length){root.append(text('p',word.empty));return}
for(const item of visible){
const url=(()=>{try{let u=new URL(item.url);return u.protocol==='https:'?u.href:null}catch(e){return null}})();
if(!url||!item.date?.match(/^\d{4}-\d{2}-\d{2}$/))continue;
let article=document.createElement('article');article.className='market-news-card';
let top=document.createElement('div');top.className='market-news-top';top.append(text('time',item.date));top.append(text('span',item.sourceName+' · '+item.impact));article.append(top);
const h=text('h3',item.title);article.append(h);
article.append(text('p',item.summary));let insight=document.createElement('div');insight.className='market-insight';
const label=text('strong',word.analysis);insight.append(label);insight.append(text('p',item.analysis));article.append(insight);
let link=text('a',word.view||langs.en.view);link.href=url;link.target='_blank';link.rel='noopener noreferrer';link.className='news-source-link';article.append(link);root.append(article);
}}
fetch('/calendar-brief.json',{cache:'no-store'}).then(r=>{if(!r.ok)throw Error('Unavailable');return r.json()}).then(j=>{if(j.schema===1&&Array.isArray(j.news))cached=j.news.filter(x=>x&&typeof x.title==='string'&&typeof x.summary==='string'&&typeof x.analysis==='string'&&typeof x.sourceName==='string'&&typeof x.url==='string');render()}).catch(()=>render());
document.addEventListener('click',e=>{const b=e.target.closest?.('[data-filter]');if(!b)return;filtering=b.dataset.filter||'all';render()});
window.addEventListener('katarina-language',render);window.addEventListener('katarina-instrument',render);
})();
