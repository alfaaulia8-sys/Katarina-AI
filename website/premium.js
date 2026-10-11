/* KATARINA AI premium live-chart loader, TradingView official advanced-chart widget */
(function(){
'use strict';
const doc=document;
const host=doc.getElementById('tv-host');
const map={
'OANDA:XAUUSD':{symbol:'OANDA:XAUUSD',url:'https://www.tradingview.com/symbols/XAUUSD/'},
'OANDA:EURUSD':{symbol:'OANDA:EURUSD',url:'https://www.tradingview.com/symbols/EURUSD/'},
'OANDA:GBPUSD':{symbol:'OANDA:GBPUSD',url:'https://www.tradingview.com/symbols/GBPUSD/'},
'BITSTAMP:BTCUSD':{symbol:'BITSTAMP:BTCUSD',url:'https://www.tradingview.com/symbols/BTCUSD/'},
'OANDA:XAGUSD':{symbol:'OANDA:XAGUSD',url:'https://www.tradingview.com/symbols/XAGUSD/'},
'OANDA:NAS100USD':{symbol:'OANDA:NAS100USD',url:'https://www.tradingview.com/symbols/NAS100/'}
};
if(!host)return;
let version=0,observer=null,timeout=null;
const text=(id,en)=>document.documentElement.lang==='id'?id:en;
function make(tag,cls,value){const el=doc.createElement(tag);if(cls)el.className=cls;if(value)el.textContent=value;return el}
function externalLink(url,label){const a=make('a','',label);a.href=url;a.target='_blank';a.rel='noopener noreferrer';return a}
function fresh(symbol){
if(!Object.prototype.hasOwnProperty.call(map,symbol))symbol='OANDA:XAUUSD';
const ticket=++version;if(observer)observer.disconnect();if(timeout)clearTimeout(timeout);
host.replaceChildren();host.classList.remove('chart-hidden');
const view=make('div','tradingview-widget-container');view.style.cssText='height:100%;width:100%';
const widget=make('div','tradingview-widget-container__widget');widget.style.cssText='height:100%;width:100%';
view.append(widget);host.append(view);
const loading=make('div','tv-loading');loading.setAttribute('role','status');
loading.append(make('span','tv-graphic','⌁'));
loading.append(make('strong','',text('Memuat Grafik Pasar','Loading Market Chart')));
loading.append(make('p','',text('Menghubungkan chart interaktif TradingView untuk '+symbol.split(':')[1]+'…','Connecting interactive TradingView chart…')));
const fail=externalLink(map[symbol].url,text('Buka chart langsung ↗','Open chart ↗'));fail.style.cssText='display:inline-block;padding:10px 15px;border:1px solid #218bbd;color:#c9f5ff;border-radius:7px;text-decoration:none;font-size:12px';
loading.append(fail);host.append(loading);
const source=doc.getElementById('source-chart');if(source)source.href=map[symbol].url;
const direct=doc.getElementById('chart-direct-link');if(direct)direct.href=map[symbol].url;
const live=doc.getElementById('chart-symbol-label');if(live)live.textContent=symbol.split(':')[1];
function loaded(){if(ticket!==version)return;loading.classList.add('is-hidden');}
observer=new MutationObserver(()=>{if(ticket!==version)return;const iframe=host.querySelector('iframe');if(iframe){iframe.setAttribute('title','TradingView '+symbol);iframe.style.background='#04152a';iframe.addEventListener('load',()=>setTimeout(loaded,800),{once:true})}});
observer.observe(widget,{childList:true,subtree:true});
const script=doc.createElement('script');script.type='text/javascript';script.src='https://s3.tradingview.com/external-embedding/embed-widget-advanced-chart.js';script.async=true;
script.textContent=JSON.stringify({autosize:true,symbol,interval:'240',timezone:'Asia/Jakarta',theme:'dark',style:'1',locale:'id',backgroundColor:'#061225',gridColor:'rgba(30,98,146,0.18)',hide_top_toolbar:false,hide_legend:false,hide_side_toolbar:true,allow_symbol_change:false,save_image:false,calendar:false,details:false,withdateranges:true,support_host:'https://www.tradingview.com'});
script.onerror=()=>{if(ticket===version){loading.querySelector('strong').textContent=text('Chart eksternal tidak dapat dimuat','External chart unavailable');loading.querySelector('p').textContent=text('Gunakan tautan di bawah untuk membuka TradingView.','Use the link below to open TradingView.')}};
view.append(script);
timeout=setTimeout(()=>{if(ticket===version&&!loading.classList.contains('is-hidden')){loading.querySelector('strong').textContent=text('Chart lambat atau diblokir jaringan','Chart delayed or blocked');loading.querySelector('p').textContent=text('Grafik eksternal mungkin tidak didukung pada jaringan ini. Buka chart TradingView secara langsung.','External widget may not load on this network. Open TradingView directly.')}},10000);
}
const choices=Array.from(doc.querySelectorAll('[data-tv-symbol]'));
choices.forEach(button=>button.addEventListener('click',()=>{const symbol=button.dataset.tvSymbol;fresh(symbol);choices.forEach(x=>x.setAttribute('aria-selected',String(x===button)))}));
fresh('OANDA:XAUUSD');
})();