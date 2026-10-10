'use strict';
// KATARINA marketplace task discovery — uses existing Debian Chromium CDP.
// Read-only, small bounded scans of public job listings displayed in the browser.
// No account secrets, page HTML, cookies, screenshots, contact data, or submission actions.
const {chromium}=require('playwright-core');
const RULES={
 truelancer:{origin:'https://www.truelancer.com',prefix:'/freelance-project/',seed:'https://www.truelancer.com/freelance-jobs/data-entry-66-jobs'},
 peopleperhour:{origin:'https://www.peopleperhour.com',prefix:'/freelance-jobs/',seed:'https://www.peopleperhour.com/freelance-data-entry-form-filling-jobs'}
};
const safe=x=>String(x||'').replace(/\s+/g,' ').trim().slice(0,900);
const error=x=>String(x?.message||x).replace(/https?:\/\/[^\s]+/gi,'[URL]').slice(0,100);
(async()=>{
 const mode=process.argv[2]||'scan';
 if(mode!=='scan')throw Error('UNSUPPORTED_ACTION');
 const browser=await chromium.connectOverCDP('http://127.0.0.1:9223',{timeout:17000});
 const c=browser.contexts()[0];if(!c)throw Error('NO_EXISTING_CONTEXT');
 const result={ok:true,mode:'public_listing_scan',read_only:true,time:new Date().toISOString(),sites:[]};
 try{
  for(const [key,site] of Object.entries(RULES)){
   const p=await c.newPage();const item={site:key,status:'ERROR',http:null,jobs:[]};
   try{
    const resp=await p.goto(site.seed,{waitUntil:'domcontentloaded',timeout:18000});
    item.http=resp?.status()??null;await p.waitForTimeout(1200);
    const x=await Promise.race([p.evaluate(({prefix,origin})=>{
     const list=[],seen=new Set();
     for(const a of document.querySelectorAll('a[href]')){
      const link=a.getAttribute('href')||'';let u;
      try{u=new URL(link,location.origin)}catch{continue}
      if(u.origin!==origin||!u.pathname.startsWith(prefix)||!/-[0-9]{6,8}$/.test(u.pathname)||seen.has(u.pathname))continue;
      const title=(a.innerText||a.textContent||'').trim().replace(/\s+/g,' ');
      if(title.length<9||title.length>170||/^(view\s*&\s*apply|apply now|details|read more)$/i.test(title))continue;
      seen.add(u.pathname);
      let cur=a.parentElement,txt='';
      for(let i=0;i<5&&cur;i++,cur=cur.parentElement){
       const text=(cur.innerText||'').replace(/\s+/g,' ').trim();
       if(text.length>=120&&text.length<2300){txt=text;break}
      }
      const n=/(?:₹\s?[\d,]+(?:\s?\/\s?Hr)?|\$\s?[\d,]+|£\s?[\d,]+)/.exec(txt);
      const proposals=/(?:([\d,]+)\s+PROPOSALS?|([\d,]+)\s+proposals?|BE THE FIRST ONE)/i.exec(txt);
      list.push({title:title.slice(0,145),url:u.origin+u.pathname,budget:n?.[0]||null,proposal_count:proposals?.[1]?Number(proposals[1].replace(/,/g,'')):proposals?.[2]?Number(proposals[2].replace(/,/g,'')):null,detail_excerpt:txt.slice(0,550)});
      if(list.length>=8)break;
     }
     return {title:document.title,found:list};
    },{prefix:site.prefix,origin:site.origin}),new Promise((_,rej)=>setTimeout(()=>rej(Error('DOM_TIMEOUT')),10000))]);
    item.status='OK';item.jobs=x.found.filter(j=>!/\b(password|account credentials|give review|fake reviews)\b/i.test(j.title)).slice(0,8);
   }catch(e){item.status='ERROR_'+error(e).replace(/[^a-zA-Z0-9_]/g,'_').slice(0,70)}
   finally{await p.close().catch(()=>{})}
   result.sites.push(item);
  }
 }finally{await browser.close().catch(()=>{})}
 console.log(JSON.stringify(result));
})().catch(e=>{console.log(JSON.stringify({ok:false,error:error(e)}));process.exitCode=1});
