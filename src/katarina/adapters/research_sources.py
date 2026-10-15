"""Explicit Owner allowlist of HTTPS research documents; no arbitrary model URLs."""
from hashlib import sha256
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, ProxyHandler
from katarina.adapters.dialog_model import NoRedirect


def load_sources(path):
    value = json.loads(Path(path).read_text(encoding='utf-8'))
    if not isinstance(value, dict) or not 1 <= len(value) <= 12:
        raise ValueError('invalid_research_sources')
    for key, url in value.items():
        if not isinstance(key, str) or not re.fullmatch('[A-Za-z0-9_-]{1,40}',key) or not isinstance(url,str):
            raise ValueError('invalid_research_source')
        p = urlsplit(url)
        if p.scheme != 'https' or not p.hostname or p.username or p.password or p.query or p.fragment:
            raise ValueError('invalid_research_source_url')
    return value


class TextParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts, self.skip = [], 0

    def handle_starttag(self, tag, attrs):
        if tag in ('script','style'):
            self.skip += 1

    def handle_endtag(self, tag):
        if tag in ('script','style'):
            self.skip = max(0, self.skip-1)

    def handle_data(self, data):
        if not self.skip and data.strip():
            self.parts.append(data.strip())


def read_source(source_id, sources, *, opener=None):
    if source_id not in sources:
        raise ValueError('source_not_granted')
    url = sources[source_id]
    fetch = opener or build_opener(ProxyHandler({}), NoRedirect()).open
    with fetch(Request(url, headers={'User-Agent':'Katarina-Research/1'}), timeout=10) as response:
        raw = response.read(64001)
        kind = response.headers.get('Content-Type','').lower()
    if len(raw) > 64000 or not any(x in kind for x in ('text/html','text/plain','application/json')):
        raise ValueError('source_type_or_size_rejected')
    text = raw.decode('utf-8')
    if 'text/html' in kind:
        parser = TextParser(); parser.feed(text)
        text = '\n'.join(parser.parts)
    return {'source_id':source_id, 'url':url, 'sha256':sha256(raw).hexdigest(),
            'text':text[:18000], 'truncated':len(text)>18000,
            'source_status':'FETCHED_UNVERIFIED_EXTERNAL_CONTENT',
            'trading_evidence_validated':False}
