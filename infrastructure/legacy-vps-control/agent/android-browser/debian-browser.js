'use strict';
// KATARINA Debian Chromium read-only worker. Reuses existing profile via CDP.
// No cookies, tokens, screenshots, localStorage, full page text or external uploads.
const fs=require('fs');
const {URL}=require('url');
const ALLOWED=['mql5.com','freelancer.com','peopleperhour.com','guru.com','contra.com','truelancer.com','upwork.com','github.com','clickworker.com','crowdgen.com'];
const permitted=host=>ALLOWED.some(x=>host===x||host.endsWith('.'+x));
const safeURL=value=>{
 const u=new URL(String(value||''));if(u.protocol!=='https:'||u.username||u.password||u.port||!permitted(u.hostname.toLowerCase()))throw Error('URL_NOT_ALLOWED');return u.toString();
};
const done=(obj,code=0)=>{console.log(JSON.stringify(obj));process.exitCode=code};
const timeout=(p,ms)=>Promise.race([p,new Promise((_,reject)=>setTimeout(()=>reject(Error('DOM_TIMEOUT')),ms))]);
async function run(){
 const action=process.argv[2]||'status';
 const input=await new Promise(resolve=>{let s='';process.stdin.setEncoding('utf8');process.stdin.on('data',x=>{s+=x.slice(0,4000);if(s.length>4000)process.stdin.destroy()});process.stdin.on('end',()=>resolve(s))});
 const data=input?JSON.parse(input):{};
 if(action!=='status'&&action!=='audit')throw Error('ACTION_NOT_ALLOWED');
 const {chromium}=require('playwright-core');
 const browser=await chromium.connectOverCDP('http://127.0.0.1:9223',{timeout:14000});
 try{
  const contexts=browser.contexts(),ctx=contexts[0];
  if(!ctx)throw Error('CHROME_CONTEXT_UNAVAILABLE');
  if(action==='status'){
   const pages=contexts.flatMap(c=>c.pages());
   const domains=[...new Set(pages.map(x=>{try{return new URL(x.url()).hostname}catch{return ''}}).filter(permitted))];
   done({ok:true,browser:'debian_chromium_existing_profile',connected:true,open_tabs:pages.length,approved_domains_only:domains.sort().slice(0,15)});
   return;
  }
  if(!Array.isArray(data.urls)||data.urls.length===0||data.urls.length>3)throw Error('MAX_THREE_URLS');
  const urls=data.urls.map(safeURL),results=[];
  for(const raw of urls){
   const page=await ctx.newPage();
   let state='unknown',http_status=null,redirected=false;
   try{
    const requested=new URL(raw);
    const r=await page.goto(raw,{waitUntil:'domcontentloaded',timeout:18000});
    const arrived=new URL(page.url());redirected=arrived.hostname!==requested.hostname;
    if(!permitted(arrived.hostname)){state='REDIRECT_OUTSIDE_ALLOWLIST';results.push({domain:requested.hostname,http_status:r?.status()??null,state,redirected});continue;}
    http_status=r?.status()??null;
    // Client-side rendered job sites often have an empty body at DOMContentLoaded.
    // Allow bounded hydration before classifying; never click or submit anything.
    await page.waitForTimeout(1600);
    let initial=await timeout(page.evaluate(()=>({length:(document.body?.innerText||'').trim().length,ready:document.readyState})),4500);
    if(initial.length<120)await page.waitForTimeout(2600);
    const sig=await timeout(page.evaluate(()=>{
     const txt=(document.body?.innerText||'').slice(0,13000);
     const links=[...document.querySelectorAll('a,button')].map(e=>(e.innerText||e.getAttribute('aria-label')||'').trim()).filter(Boolean).slice(0,200);
     const vis=e=>!!(e.offsetWidth||e.offsetHeight||e.getClientRects().length);
     const controls=[...document.querySelectorAll('button,a,input[type=submit],[role=button]')].filter(vis);
     const ctl=controls.map(e=>(e.innerText||e.value||e.getAttribute('aria-label')||'').trim()).filter(Boolean);
     return {
      body_length:txt.trim().length,
      ready_state:document.readyState,
      button_count:controls.length,
      action_button_visible:ctl.some(x=>/^(place bid|bid on this project|apply now|send proposal|submit proposal|apply for this job)$/i.test(x)),
      account_menu_visible:controls.some(e=>/account|profile|avatar|user menu/i.test(e.getAttribute('aria-label')||'')&&!/log ?in|sign ?in/i.test(e.getAttribute('aria-label')||'')),
      login_form:[...document.querySelectorAll('input[type=password]')].some(vis),
      login_redirect:/\/(login|signin|auth_login)(?:[\/?#]|$)/i.test(location.pathname),
      sign_out:links.some(x=>/^(log ?out|sign ?out)$/i.test(x)),
      sign_in:links.some(x=>/^(log ?in|sign ?in)$/i.test(x)),
      dashboard:links.some(x=>/^(dashboard|my projects|my account|my profile|my jobs)$/i.test(x)),
      access_blocked:/access denied|verify you are human|checking your browser|captcha/i.test(txt.slice(0,2200)),
      visible_content:txt.length>180
     };
    }),7000);
    state=sig.access_blocked?'ACCESS_CHALLENGE':(sig.login_form||sig.login_redirect?'LOGIN_REQUIRED':(sig.sign_out?'LOGGED_IN_SIGNAL':(sig.dashboard&&!sig.sign_in?'ACCOUNT_UI_SIGNAL':(sig.account_menu_visible&&!sig.sign_in?'ACCOUNT_MENU_SIGNAL':(sig.visible_content?'ACCESSIBLE_AUTH_UNCERTAIN':'EMPTY_PAGE')))));
    // A visible "Apply" or "Bid" control is not evidence of eligible/free submission.
    results.push({domain:requested.hostname,http_status,state,redirected,body_text_length:sig.body_length,document_ready:sig.ready_state,apply_cta_visible:sig.action_button_visible,submission_authorized:false});
    continue;
   }catch(e){state='ERROR_'+String(e.message||e).replace(/[^A-Za-z_]/g,'_').slice(0,50);}
   finally{await page.close().catch(()=>{})}
   results.push({domain:new URL(raw).hostname,http_status,state,redirected,submission_authorized:false});
  }
  done({ok:true,browser:'debian_chromium_existing_profile',read_only:true,results});
 }finally{await browser.close().catch(()=>{})}
}
run().catch(e=>done({ok:false,error:String(e.message||e).replace(/[^A-Za-z_]/g,'_').slice(0,70)},1));
