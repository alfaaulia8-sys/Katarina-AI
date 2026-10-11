/* bilingual long-form research/trust pages; no analytics and no advertising calls */
(function(){'use strict';
const buttons=[...document.querySelectorAll('[data-publisher-lang]')];
const content=[...document.querySelectorAll('[data-publisher-content]')];
if(!buttons.length||!content.length)return;
let preference='id';
try{const v=localStorage.getItem('katarina_public_lang');if(v==='en'||v==='id')preference=v}catch(e){}
function switchLang(value){const l=value==='en'?'en':'id';buttons.forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.publisherLang===l)));content.forEach(a=>a.hidden=a.dataset.publisherContent!==l);document.documentElement.lang=l;}
buttons.forEach(b=>b.addEventListener('click',()=>{switchLang(b.dataset.publisherLang);try{localStorage.setItem('katarina_public_lang',b.dataset.publisherLang)}catch(e){}}));
switchLang(preference);
})();