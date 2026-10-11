/* KATARINA Cloudflare Pages Function: on-demand, cached headline checking.
 * No API keys, paid API, VPS, cron worker, invented headlines, or financial signals.
 * Runs only on requests; CDN caches successful results for 15 minutes.
 */
const FEEDS = [
  ["CNBC Pasar","https://www.cnbc.com/id/10000664/device/rss/rss.html","www.cnbc.com"],
  ["CNBC Dunia","https://www.cnbc.com/id/100727362/device/rss/rss.html","www.cnbc.com"],
  ["CNBC Utama","https://www.cnbc.com/id/100003114/device/rss/rss.html","www.cnbc.com"],
  ["Federal Reserve","https://www.federalreserve.gov/feeds/press_monetary.xml","www.federalreserve.gov"]
];
const TOPICS = /\b(fed|federal reserve|fomc|rates?|bonds?|treasur(?:y|ies)|inflation|cpi|ppi|nfp|oil|crude|energy|gold|silver|dollar|forex|currenc(?:y|ies)|yen|euro|pound|markets?|wall street|stocks?|equities|nasdaq|dow jones|geopolitic\w*|iran|saudi|china|tariffs?|commodit\w*|payrolls?|employment|central bank|crypto\w*|bitcoin|debt|yields?|jpmorgan|banks?|econom\w*|recession|monetary|interest|imf|world bank)\b/i;
const EXCLUDED = /\b(NBA|NFL|basketball|baseball|soccer|football|hockey|tennis|athlete|celebrity|movie|entertainment|music awards|actor|streaming series)\b/i;
function decode(text){
  return String(text||"").replace(/&#(x[0-9a-f]+|\d+);/gi,(_,s)=>{const n=s[0]?.toLowerCase()==="x"?parseInt(s.slice(1),16):parseInt(s,10);return Number.isFinite(n)&&n>0&&n<=0x10ffff?String.fromCodePoint(n):""}).replace(/&(?:amp|lt|gt|quot|apos|nbsp);/gi,s=>({"&amp;":"&","&lt;":"<","&gt;":">","&quot;":'"',"&apos;":"'","&nbsp;":" "}[s.toLowerCase()]||s));
}
function clean(s){
  return decode(String(s||"").replace(/<!\[CDATA\[([\s\S]*?)\]\]>/gi,"$1").replace(/<[^>]*>/g,"")).replace(/\s+/g," ").trim();
}
function tag(xml,name){
  const match=xml.match(new RegExp("<"+name+"(?:\\s[^>]*)?>([\\s\\S]*?)<\\/"+name+"\\s*>","i"));
  return match?clean(match[1]):"";
}
function topic(title){
  if(/\b(gold|silver|precious metal)\b/i.test(title))return "Emas / Logam";
  if(/\b(oil|crude|iran|middle east|saudi|energy|war|geopolitic)\b/i.test(title))return "Energi / Geopolitik";
  if(/\b(bitcoin|crypto|blockchain|digital asset)\b/i.test(title))return "Kripto";
  if(/\b(yen|euro|dollar|forex|currency|sterling)\b/i.test(title))return "Valas";
  if(/\b(fed|fomc|inflation|cpi|ppi|rates?|treasury|bond|yield|monetary|payroll)\b/i.test(title))return "Suku Bunga / Inflasi";
  return "Pasar Global";
}
async function source([name,feed,host],now){
  const controller=new AbortController();
  const id=setTimeout(()=>controller.abort(),8000);
  try{
    const r=await fetch(feed,{signal:controller.signal,headers:{"Accept":"application/rss+xml,application/xml,text/xml;q=0.9,*/*;q=0.5"},cf:{cacheEverything:true,cacheTtl:900}});
    if(!r.ok) return [];
    const payload=await r.text();
    if(payload.length>900000) return [];
    const chunks=payload.match(/<item(?:\s[^>]*)?>[\s\S]*?<\/item\s*>/gi)||[];
    const found=[];
    for(const item of chunks.slice(0,100)){
      const title=tag(item,"title"),rawLink=tag(item,"link"),rawDate=tag(item,"pubDate");
      if(title.length<24||title.length>215||!TOPICS.test(title)||EXCLUDED.test(title))continue;
      let u;
      try{u=new URL(rawLink)}catch{continue}
      if(u.protocol!=="https:"||u.hostname!==host)continue;
      const timestamp=Date.parse(rawDate);
      if(!Number.isFinite(timestamp)||timestamp>now+1800000||now-timestamp>72*3600000)continue;
      const date=new Date(timestamp);
      if(host==="www.cnbc.com"&&!u.pathname.includes("/"+date.getUTCFullYear()+"/"+String(date.getUTCMonth()+1).padStart(2,"0")+"/"))continue;
      u.hash="";u.search="";
      found.push({title,source:name,url:u.href,publishedAt:date.toISOString(),category:topic(title),language:"en"});
    }
    return found;
  }catch{return []}
  finally{clearTimeout(id)}
}
export async function onRequestGet({request}){
  const cacheKey=new Request(new URL("/api/hot-news",request.url).toString());
  try{const hit=await caches.default.match(cacheKey);if(hit)return hit}catch{}
  const now=Date.now();
  const batches=await Promise.all(FEEDS.map(feed=>source(feed,now)));
  const uniq=new Map();
  for(const item of batches.flat()){if(!uniq.has(item.url))uniq.set(item.url,item)}
  const items=[...uniq.values()].sort((a,b)=>Date.parse(b.publishedAt)-Date.parse(a.publishedAt)).slice(0,12);
  const ok=items.length>0;
  const data={schema:1,kind:"attributed-headline-feed",updatedAt:new Date(now).toISOString(),status:ok?"source-headlines":"temporarily-unavailable",items};
  const response=new Response(JSON.stringify(data),{status:ok?200:503,headers:{"Content-Type":"application/json; charset=utf-8","Cache-Control":ok?"public, max-age=0, s-maxage=900":"no-store","X-Content-Type-Options":"nosniff"}});
  if(ok){try{await caches.default.put(cacheKey,response.clone())}catch{}}
  return response;
}
