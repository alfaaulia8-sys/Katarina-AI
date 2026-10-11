#!/usr/bin/env python3
"""KATARINA market hot news. Headlines only, attributed RSS sources, no AI invention."""
from __future__ import annotations
import argparse
import datetime as dt
import email.utils
import html
import json
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

UTC=dt.timezone.utc
NOW=dt.datetime.now(UTC)
HEADERS={"User-Agent":"KatarinaMarketResearch/1.0 (+https://katarina-research.pages.dev/; attributed news links)",
         "Accept":"application/rss+xml,application/xml,text/xml;q=0.9,*/*;q=0.5"}
FEEDS=[
 ("CNBC Pasar","https://www.cnbc.com/id/10000664/device/rss/rss.html","www.cnbc.com"),
 ("CNBC Dunia","https://www.cnbc.com/id/100727362/device/rss/rss.html","www.cnbc.com"),
 ("CNBC Utama","https://www.cnbc.com/id/100003114/device/rss/rss.html","www.cnbc.com"),
 ("Federal Reserve","https://www.federalreserve.gov/feeds/press_monetary.xml","www.federalreserve.gov"),
]
KEYWORDS=re.compile(r"\b(fed|federal reserve|fomc|rate[s]?|bond[s]?|treasur(?:y|ies)|inflation|cpi|ppi|nfp|oil|crude|energy|gold|silver|dollar|forex|currency|currencies|yen|euro|pound|market[s]?|wall street|stock[s]?|equities|s&p|nasdaq|dow jones|geopolitic\w*|iran|saudi|china|tariff[s]?|commodit\w*|payroll[s]?|employment|central bank|crypto\w*|bitcoin|debt|yield[s]?|jpmorgan|bank[s]?|econom\w*|recession|monetary|interest|imf|world bank)\b", re.I)
EXCLUDED=re.compile(r"\b(NBA|NFL|basketball|baseball|soccer|football|hockey|tennis|athlete|smart ball|celebrity|movie|entertainment|music awards|actor|streaming series)\b",re.I)
def topic(title):
 text=title.lower()
 if re.search(r"\b(gold|silver|precious metal)\b",text):return "Emas / Logam"
 if re.search(r"\b(oil|crude|iran|middle east|saudi|energy|war|geopolitic)\b",text):return "Energi / Geopolitik"
 if re.search(r"\b(bitcoin|crypto|blockchain|digital asset)\b",text):return "Kripto"
 if re.search(r"\b(yen|euro|dollar|forex|currency|sterling)\b",text):return "Valas"
 if re.search(r"\b(fed|fomc|inflation|cpi|ppi|rate[s]?|treasury|bond|yield|monetary|payroll)\b",text):return "Suku Bunga / Inflasi"
 return "Pasar Global"
def fetch(url):
 request=urllib.request.Request(url,headers=HEADERS)
 with urllib.request.urlopen(request,timeout=22) as response:
  if response.status != 200:raise ValueError("HTTP error")
  payload=response.read(900_000)
 return ET.fromstring(payload)
def normalize(title):
 return re.sub(r"\s+"," ",html.unescape(re.sub(r"<[^>]+>","",title or ""))).strip()
def valid_link(url,host):
 try:
  uri=urllib.parse.urlsplit(url.strip())
  return uri.scheme=="https" and (uri.hostname or "").lower()==host
 except ValueError:return False
def collect():
 found={}
 failures=[]
 for source,feed,host in FEEDS:
  try:
   xml=fetch(feed)
   for node in xml.findall(".//item"):
    title=normalize(node.findtext("title"))
    link=(node.findtext("link") or "").strip()
    date=node.findtext("pubDate") or ""
    if not (24<=len(title)<=215 and KEYWORDS.search(title) and not EXCLUDED.search(title) and valid_link(link,host)):continue
    try:published=email.utils.parsedate_to_datetime(date).astimezone(UTC)
    except (ValueError,TypeError,OverflowError):continue
    age=(NOW-published).total_seconds()
    if age< -30*60 or age > 72*3600:continue
    # CNBC article URL should match the year/month of RSS publication;
    # prevents resurfaced old stories from being presented as current hot news.
    if host=="www.cnbc.com" and not re.search(r"/"+str(published.year)+r"/"+str(published.month).zfill(2)+r"/",urllib.parse.urlsplit(link).path):continue
    canon=link.split("#")[0].split("?")[0]
    if canon in found:continue
    found[canon]={"title":title,"source":source,"url":canon,"publishedAt":published.isoformat(timespec="seconds").replace("+00:00","Z"),"category":topic(title),"language":"en"}
  except Exception as error:
   failures.append(source+": "+type(error).__name__)
 return sorted(found.values(),key=lambda x:x["publishedAt"],reverse=True)[:12],failures
def main():
 parser=argparse.ArgumentParser()
 parser.add_argument("--output",default="website/hot-news.json")
 args=parser.parse_args()
 target=Path(args.output)
 items,failures=collect()
 if not items:
  print("No valid fresh source headlines; refusing to replace existing news",failures,file=sys.stderr)
  sys.exit(2)
 old={}
 if target.exists():
  try:old=json.loads(target.read_text(encoding="utf-8"))
  except Exception:pass
 if old.get("items")==items:
  print("No new headlines; existing verified snapshot preserved.")
  return
 snapshot={"schema":1,"kind":"attributed-headline-feed","updatedAt":NOW.isoformat(timespec="seconds").replace("+00:00","Z"),"scope":"market-moving headlines from dated publisher RSS (not independently fact-checked claims)","status":"source-headlines","items":items}
 target.parent.mkdir(parents=True,exist_ok=True)
 target.write_text(json.dumps(snapshot,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
 print("Published",len(items),"sourced headlines; unavailable sources:",",".join(failures) or "none")
if __name__=="__main__":main()
