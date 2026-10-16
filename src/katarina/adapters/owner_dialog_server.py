"""Explicit foreground Owner browser surface, bearer-authenticated; never starts on import."""
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import ipaddress
import json
import os
import ssl

PAGE = '''<!doctype html><html lang="id"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Katarina AI</title><style>body{font:17px system-ui;background:#101826;color:#e4eefb;max-width:820px;margin:30px auto;padding:20px}
input,textarea,button,select{box-sizing:border-box;font:inherit;padding:12px;border:1px solid #40516a;border-radius:8px;background:#19283a;color:inherit;margin:6px 0;width:100%}
button{background:#256a67;cursor:pointer}pre{white-space:pre-wrap;overflow-wrap:anywhere;padding:16px;background:#19283a;border-radius:12px}small{color:#a9c4d8}</style>
<h1>Katarina AI</h1><p>Satu otak · LIVE OFF</p><small>Akses Owner. Jawaban model belum tentu benar; lihat bukti alat. Ctrl+C pada komputer host untuk berhenti.</small>
<p><input id="token" type="password" autocomplete="off" placeholder="Token Owner"><input id="session" value="owner" aria-label="Sesi">
<select id="mode" aria-label="Mode"><option value="auto">Otomatis</option><option>fast</option><option>deep</option></select></p>
<div id="history" aria-live="polite"></div><form id="form"><textarea id="prompt" rows="4" maxlength="8000" required placeholder="Perintah untuk Katarina" aria-label="Perintah"></textarea><button id="send">Kirim</button></form><p id="status" role="status">Siap</p>
<script>
const byId=id=>document.getElementById(id);
byId('form').onsubmit=async event=>{event.preventDefault();byId('send').disabled=true;byId('status').textContent='Berjalan…';
const input=byId('prompt').value;try{const response=await fetch('/turn',{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+byId('token').value},body:JSON.stringify({text:input,session_id:byId('session').value,mode:byId('mode').value})});
if(!response.ok)throw Error('Permintaan ditolak ('+response.status+')');const report=await response.json();
const entry=document.createElement('pre');entry.textContent='Owner: '+input+'\\n\\nKatarina: '+report.answer+'\\n\\nBukti alat: '+JSON.stringify(report.trace,null,2);byId('history').append(entry);byId('status').textContent=report.status;byId('prompt').value='';
}catch(error){byId('status').textContent=error.message}finally{byId('send').disabled=false}};
</script></html>'''


def handler_type(turn, token, *, access_config=None):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def log_message(self, *args):
            pass

        def reply(self, code, content, mime='application/json'):
            raw = content.encode('utf-8')
            self.send_response(code)
            self.send_header('Content-Type', mime + '; charset=utf-8')
            self.send_header('Content-Length', str(len(raw)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('X-Frame-Options', 'DENY')
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            if self.path != '/':
                self.reply(404, '{}')
                return
            self.reply(200, PAGE, 'text/html')

        def do_POST(self):
            principal = None
            allowed = False
            try:
                if access_config:
                    from katarina.adapters.owner_access import authenticate
                    principal = authenticate(access_config, self.headers.get('Authorization', ''))
                    allowed = principal is not None
                else:
                    allowed = hmac.compare_digest(self.headers.get('Authorization', '').encode('utf-8'),
                                                  ('Bearer ' + token).encode('utf-8'))
            except (ValueError, OSError):
                pass
            if self.path != '/turn' or not allowed:
                self.reply(403, '{}')
                return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if self.headers.get('Transfer-Encoding') or not 0 < length <= 40000:
                    raise ValueError()
                value = json.loads(self.rfile.read(length))
                if not isinstance(value, dict) or set(value) != {'text', 'session_id', 'mode'}:
                    raise ValueError()
                if principal:
                    from katarina.adapters.owner_access import scoped_session
                    report = turn(value['text'], session_id=scoped_session(principal, value['session_id']),
                                  mode=value['mode'], principal=principal)
                else:
                    report = turn(value['text'], session_id=value['session_id'], mode=value['mode'])
                self.reply(200, json.dumps(report, ensure_ascii=False, allow_nan=False))
            except Exception:
                self.reply(400, '{"status":"REQUEST_BLOCKED"}')
    return Handler


def create_server(turn, *, bind='127.0.0.1', port=8765, cert=None, key=None, access_config=None):
    token = os.environ.get('KATARINA_OWNER_TOKEN', '')
    if access_config:
        from katarina.adapters.owner_access import load_access
        load_access(access_config)
    elif len(token) < 32 or not token.isascii() or any(x.isspace() for x in token):
        raise ValueError('owner_token_required')
    loopback = bind == 'localhost'
    try:
        loopback = loopback or ipaddress.ip_address(bind).is_loopback
    except ValueError:
        pass
    if not loopback and not (cert and key):
        raise ValueError('remote_owner_surface_requires_tls')
    context = None
    if cert or key:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(cert, key)
    class BoundedServer(HTTPServer):
        def get_request(self):
            client, address = super().get_request()
            try:
                client.settimeout(10)
                if context is not None:
                    client = context.wrap_socket(client, server_side=True, do_handshake_on_connect=False)
                    client.do_handshake()
                return client, address
            except BaseException:
                client.close()
                raise
    server = BoundedServer((bind, port), handler_type(turn, token, access_config=access_config))
    try:
        print('KATARINA_OWNER_UI_READY · LIVE OFF · port ' + str(server.server_port), flush=True)
        server.timeout = 1
        return server
    except BaseException:
        server.server_close()
        raise


def serve(turn, **options):
    server = create_server(turn, **options)
    try:
        server.serve_forever()
    finally:
        server.server_close()
