/* KATARINA AI — independent market news cards, source-linked and scrollable */
(function(){
'use strict';
const root=document.querySelector('#news-feed');if(!root)return;
const langs={id:{source:'Sumber',analysis:'Analisis Singkat',empty:'Belum ada berita terverifikasi.',view:'Baca sumber ↗',news:'Berita Pasar'},en:{source:'Source',analysis:'Quick Analysis',empty:'No verified news available.',view:'Read source ↗',news:'Market News'},es:{source:'Fuente',analysis:'Análisis breve',empty:'Sin noticias verificadas.',view:'Leer fuente ↗'},fr:{source:'Source',analysis:'Analyse brève',empty:'Aucune actualité vérifiée.',view:'Lire la source ↗'},pt:{source:'Fonte',analysis:'Análise breve',empty:'Sem notícias verificadas.',view:'Ver fonte ↗'},de:{source:'Quelle',analysis:'Kurzanalyse',empty:'Keine geprüften Nachrichten.',view:'Quelle ↗'},ar:{source:'المصدر',analysis:'تحليل موجز',empty:'لا توجد أخبار موثقة.',view:'المصدر ↗'},hi:{source:'स्रोत',analysis:'संक्षिप्त विश्लेषण',empty:'सत्यापित समाचार नहीं।',view:'स्रोत ↗'},zh:{source:'来源',analysis:'简析',empty:'暂无核实新闻。',view:'阅读来源 ↗'},ja:{source:'出典',analysis:'簡易分析',empty:'確認済み記事なし。',view:'情報源 ↗'},ko:{source:'출처',analysis:'간단 분석',empty:'검증된 뉴스가 없습니다.',view:'출처 ↗'},ru:{source:'Источник',analysis:'Краткий анализ',empty:'Нет проверенных новостей.',view:'Источник ↗'},ms:{source:'Sumber',analysis:'Analisis ringkas',empty:'Tiada berita disahkan.',view:'Baca sumber ↗'},tr:{source:'Kaynak',analysis:'Kısa analiz',empty:'Doğrulanmış haber yok.',view:'Kaynağı aç ↗'}};
const text=(t,v)=>{const e=document.createElement(t);e.textContent=String(v);return e};
let cached=[];let filtering='all';
function render(){
root.replaceChildren();let lang=document.documentElement.lang||'id';const word=langs[lang]||langs.en;
const visible=cached.filter(item=>filtering==='all'||(item.markets||[]).includes(filtering)).slice().sort((a,b)=>b.date.localeCompare(a.date));
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
fetch('/market-news.json',{cache:'no-store'}).then(r=>{if(!r.ok)throw Error('Unavailable');return r.json()}).then(j=>{if(j.schema===1&&Array.isArray(j.items))cached=j.items.filter(x=>x&&typeof x.title==='string'&&typeof x.summary==='string'&&typeof x.analysis==='string'&&typeof x.sourceName==='string'&&typeof x.url==='string');render()}).catch(()=>render());
document.addEventListener('click',e=>{const b=e.target.closest?.('[data-filter]');if(!b)return;filtering=b.dataset.filter||'all';render()});
window.addEventListener('katarina-language',render);
})();
